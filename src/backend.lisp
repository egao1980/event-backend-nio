(in-package #:event-backend-nio)

;;; JVM NIO Selector event loop for ABCL (java.nio.channels.Selector).
;;; register-io accepts a java.nio.channels.SelectableChannel (not an OS fd int).

#-abcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (warn "event-backend-nio: designed for ABCL; other impls lack JVM NIO interop."))

(defclass nio-backend (event-backend)
  ()
  (:default-initargs :name "nio"))

(defun make-nio-backend ()
  #-abcl
  (error 'unsupported-operation
         :operation 'make-nio-backend
         :message "event-backend-nio requires ABCL (JVM NIO)")
  #+abcl
  (make-instance 'nio-backend))

(defclass nio-loop (event-loop)
  ((selector :initarg :selector :reader nio-loop-selector)
   (lock :initform (bt:make-lock "nio-loop") :reader nio-loop-lock)
   (defer-queue :initform nil :accessor nio-loop-defer-queue)
   (wake-queue :initform nil :accessor nio-loop-wake-queue)
   (timers :initform nil :accessor nio-loop-timers) ; sorted by deadline ascending
   (stop-p :initform nil :accessor nio-loop-stop-p)
   (closed :initform nil :accessor nio-loop-closed-p)
   (io-count :initform 0 :accessor nio-loop-io-count)))

(defclass nio-handle (event-handle)
  ((kind :initarg :kind :reader nio-handle-kind)
   (fn :initarg :fn :accessor nio-handle-fn)
   (deadline :initarg :deadline :accessor nio-handle-deadline :initform nil)
   (key :initarg :key :accessor nio-handle-key :initform nil)
   (direction :initarg :direction :accessor nio-handle-direction :initform nil)))

(defun %now ()
  (/ (get-internal-real-time) (float internal-time-units-per-second 1d0)))

#+abcl
(defun %jcall (method obj &rest args)
  (apply #'java:jcall method obj args))

#+abcl
(defun %jstatic (method class &rest args)
  (apply #'java:jstatic method class args))

(defmethod make-event-loop ((backend nio-backend) &key)
  #+abcl
  (let ((sel (%jstatic "open" "java.nio.channels.Selector")))
    (make-instance 'nio-loop :backend backend :selector sel))
  #-abcl
  (error 'unsupported-operation :operation 'make-event-loop
         :message "event-backend-nio requires ABCL"))

(defun close-loop (loop)
  "Close the Selector and mark LOOP closed."
  (bt:with-lock-held ((nio-loop-lock loop))
    (unless (nio-loop-closed-p loop)
      (setf (nio-loop-closed-p loop) t
            (nio-loop-stop-p loop) t
            (nio-loop-defer-queue loop) nil
            (nio-loop-wake-queue loop) nil
            (nio-loop-timers loop) nil)
      #+abcl
      (ignore-errors (%jcall "close" (nio-loop-selector loop)))))
  loop)

(defun %assert-open (loop)
  (when (nio-loop-closed-p loop)
    (error "nio loop is closed"))
  loop)

(defun %push-queue (loop accessor fn)
  (bt:with-lock-held ((nio-loop-lock loop))
    (push fn (slot-value loop accessor))))

(defun %steal-queue (loop accessor)
  (bt:with-lock-held ((nio-loop-lock loop))
    (shiftf (slot-value loop accessor) nil)))

(defun %wakeup (loop)
  #+abcl
  (ignore-errors (%jcall "wakeup" (nio-loop-selector loop))))

(defun wake-call (loop function)
  "Enqueue FUNCTION and wake LOOP (thread-safe)."
  (%assert-open loop)
  (%push-queue loop 'wake-queue function)
  (%wakeup loop)
  function)

(defmethod wake ((backend nio-backend) (loop nio-loop))
  (%assert-open loop)
  (%wakeup loop)
  loop)

(defmethod defer ((backend nio-backend) (loop nio-loop) function &key)
  (%assert-open loop)
  (let ((h (make-instance 'nio-handle
                          :loop loop :kind :defer :fn function)))
    (%push-queue loop 'defer-queue h)
    (%wakeup loop)
    h))

(defun %insert-timer (loop handle)
  "Insert HANDLE into LOOP's timer list sorted by ascending deadline."
  (let* ((dl (nio-handle-deadline handle))
         (timers (nio-loop-timers loop))
         (pos (or (position-if (lambda (h) (> (nio-handle-deadline h) dl)) timers)
                  (length timers))))
    (setf (nio-loop-timers loop)
          (append (subseq timers 0 pos) (list handle) (subseq timers pos)))))

(defmethod sleep* ((backend nio-backend) (loop nio-loop) seconds &key callback)
  (%assert-open loop)
  (let* ((sec (max 0d0 (float seconds 1d0)))
         (h (make-instance 'nio-handle
                           :loop loop
                           :kind :timer
                           :fn callback
                           :deadline (+ (%now) sec))))
    (bt:with-lock-held ((nio-loop-lock loop))
      (%insert-timer loop h))
    (%wakeup loop)
    h))

(defmethod cancel ((backend nio-backend) (handle nio-handle))
  (call-next-method)
  #+abcl
  (when (eq (nio-handle-kind handle) :io)
    (let ((key (nio-handle-key handle)))
      (when key
        (ignore-errors (%jcall "cancel" key))
        (setf (nio-handle-key handle) nil)
        (let ((loop (event-handle-loop handle)))
          (when (and loop (not (nio-loop-closed-p loop)))
            (decf (nio-loop-io-count loop))
            (ignore-errors (%jcall "selectNow" (nio-loop-selector loop))))))))
  handle)

(defun %direction-ops (direction)
  #+abcl
  (let ((read (java:jfield "java.nio.channels.SelectionKey" "OP_READ"))
        (write (java:jfield "java.nio.channels.SelectionKey" "OP_WRITE")))
    (ecase direction
      (:read read)
      (:write write)
      (:read-write (logior read write))
      (:none 0)))
  #-abcl
  (declare (ignore direction))
  #-abcl
  0)

(defmethod register-io ((backend nio-backend) (loop nio-loop) fd direction callback &key)
  "FD must be a java.nio.channels.SelectableChannel (non-blocking)."
  (%assert-open loop)
  #+abcl
  (progn
    (unless (java:jinstance-of-p fd (java:jclass "java.nio.channels.SelectableChannel"))
      (error 'event-io-error
             :message "nio register-io expects a SelectableChannel"))
    (when (%jcall "isBlocking" fd)
      (%jcall "configureBlocking" fd (java:make-immediate-object nil :boolean)))
    (let* ((ops (%direction-ops direction))
           (h (make-instance 'nio-handle
                             :loop loop :kind :io :fn callback
                             :direction direction))
           (key (%jcall "register" fd (nio-loop-selector loop) ops h)))
      (setf (nio-handle-key h) key)
      (incf (nio-loop-io-count loop))
      (%wakeup loop)
      h))
  #-abcl
  (progn
    (declare (ignore fd direction callback))
    (error 'unsupported-operation :operation 'register-io
           :message "event-backend-nio requires ABCL")))

(defmethod update-io ((backend nio-backend) (handle nio-handle) direction &key callback)
  (unless (eq (nio-handle-kind handle) :io)
    (error 'unsupported-operation :operation 'update-io
           :message "update-io only applies to IO handles"))
  #+abcl
  (let ((key (nio-handle-key handle)))
    (unless key
      (error 'event-io-error :message "IO handle has no SelectionKey"))
    (when callback
      (setf (nio-handle-fn handle) callback))
    (setf (nio-handle-direction handle) direction)
    (%jcall "interestOps" key (%direction-ops direction))
    (%wakeup (event-handle-loop handle))
    handle)
  #-abcl
  (progn
    (declare (ignore direction callback))
    (error 'unsupported-operation :operation 'update-io
           :message "event-backend-nio requires ABCL")))

(defun %drain-handles (handles)
  (dolist (h (nreverse handles))
    (when (and (not (event-handle-canceled-p h)) (nio-handle-fn h))
      (handler-case (funcall (nio-handle-fn h))
        (error (e) (warn "nio callback error: ~A" e))))))

(defun %drain-wake (loop)
  (dolist (fn (nreverse (%steal-queue loop 'wake-queue)))
    (handler-case (funcall fn)
      (error (e) (warn "nio wake callback error: ~A" e)))))

(defun %fire-due-timers (loop)
  (let ((now (%now)) due)
    (bt:with-lock-held ((nio-loop-lock loop))
      (loop for h = (first (nio-loop-timers loop))
            while (and h (<= (nio-handle-deadline h) now))
            do (pop (nio-loop-timers loop))
               (push h due)))
    (%drain-handles due)))

(defun %next-timeout-ms (loop)
  "Milliseconds until next timer, or NIL if none, or 0 if overdue/defer pending."
  (bt:with-lock-held ((nio-loop-lock loop))
    (when (or (nio-loop-defer-queue loop) (nio-loop-wake-queue loop))
      (return-from %next-timeout-ms 0))
    (let ((h (first (nio-loop-timers loop))))
      (if (null h)
          nil
          (max 0 (ceiling (* 1000d0 (- (nio-handle-deadline h) (%now)))))))))

(defun %idle-p (loop)
  (bt:with-lock-held ((nio-loop-lock loop))
    (and (null (nio-loop-defer-queue loop))
         (null (nio-loop-wake-queue loop))
         (null (nio-loop-timers loop))
         (zerop (nio-loop-io-count loop))
         (not (nio-loop-stop-p loop)))))

#+abcl
(defun %process-selected (loop)
  (let* ((sel (nio-loop-selector loop))
         (keys (%jcall "selectedKeys" sel))
         (iter (%jcall "iterator" keys)))
    (loop while (%jcall "hasNext" iter)
          do (let* ((key (%jcall "next" iter))
                    (h (%jcall "attachment" key)))
               (%jcall "remove" iter)
               (when (and (typep h 'nio-handle)
                          (not (event-handle-canceled-p h))
                          (nio-handle-fn h))
                 (let ((ok (%jcall "isValid" key)))
                   (handler-case
                       (funcall (nio-handle-fn h) (if ok :ok :error))
                     (error (e)
                       (warn "nio io callback error: ~A" e)))))))))

(defmethod stop ((backend nio-backend) (loop nio-loop))
  (setf (nio-loop-stop-p loop) t)
  (%wakeup loop)
  loop)

(defmethod run ((backend nio-backend) (loop nio-loop) &key (stop-when-idle t))
  (%assert-open loop)
  (setf (nio-loop-stop-p loop) nil)
  #+abcl
  (let ((sel (nio-loop-selector loop)))
    (loop
      (when (nio-loop-stop-p loop)
        (return))
      (%drain-handles (%steal-queue loop 'defer-queue))
      (%drain-wake loop)
      (%fire-due-timers loop)
      (when (nio-loop-stop-p loop)
        (return))
      (when (and stop-when-idle (%idle-p loop))
        (return))
      (let ((timeout (%next-timeout-ms loop)))
        (cond ((null timeout)
               (if (and stop-when-idle (zerop (nio-loop-io-count loop)))
                   (return)
                   (%jcall "select" sel)))
              ((zerop timeout)
               (%jcall "selectNow" sel))
              (t
               (%jcall "select" sel timeout))))
      (%process-selected loop)))
  #-abcl
  (error 'unsupported-operation :operation 'run)
  loop)
