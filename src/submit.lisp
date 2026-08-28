(in-package #:event-backend-nio)

;;; Default hop-off runner: per-loop cl-stack-executors thread pool.
;;; A JVM ExecutorService is a later alternative; not required for wave-1.

(defmethod submit ((backend nio-backend) (loop nio-loop) thunk
                   &key callback error-callback executor)
  (call-next-method backend loop thunk
                    :callback callback
                    :error-callback error-callback
                    :executor (or executor
                                  (executor-runner (%ensure-submit-pool loop)))))
