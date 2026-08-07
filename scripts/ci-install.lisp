;;;; Phase 1: install SUT dependency closure via cl-repository-client.

(setf *debugger-hook*
      (lambda (c h)
        (declare (ignore h))
        (format *error-output* "~&UNHANDLED: ~A~%" c)
        (uiop:quit 1)))

(setf asdf:*compile-file-failure-behaviour* :warn)

(asdf:load-system "cl-repository-client")
(cl-repo:add-registry "https://ghcr.io" :namespace "egao1980/cl-systems" :priority :prepend)
(cl-repo:ensure-system-dependencies "event-backend-nio"
  :also-tests t
  :sources '(("bordeaux-threads" :ql)
             ("rove" :ql)))
(format t "~&; ci: install phase done~%")
(uiop:quit 0)
