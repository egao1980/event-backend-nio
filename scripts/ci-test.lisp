;;;; Phase 2: load + run tests.

(setf *debugger-hook*
      (lambda (c h)
        (declare (ignore h))
        (format *error-output* "~&UNHANDLED: ~A~%" c)
        (uiop:quit 1)))

(setf asdf:*compile-file-failure-behaviour* :warn)
(asdf:load-system "cl-repository-client")
(cl-repository-client/asdf-integration:configure-asdf-source-registry)
(cl-repository-client/asdf-integration:load-system-init-files)
(asdf:test-system "event-backend-nio")
(format t "~&; ci: tests ok~%")
(uiop:quit 0)
