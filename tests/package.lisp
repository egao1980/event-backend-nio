(defpackage #:event-backend-nio/tests
  (:use #:cl #:rove)
  (:export #:run-conformance))
(in-package #:event-backend-nio/tests)

(defun run-conformance ()
  "Set backend maker and run shared event-protocol/conformance suite."
  #+abcl
  (progn
    (setf event-protocol/conformance:*test-backend-maker*
          (lambda () (event-backend-nio:make-nio-backend)))
    (rove:run (asdf:find-system "event-protocol/conformance")))
  #-abcl
  (progn
    (format t "~&; event-backend-nio tests skipped (ABCL only)~%")
    t))
