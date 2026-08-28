(defsystem "event-backend-nio"
  :version "0.1.1"
  :description "JVM NIO Selector backend for event-protocol (ABCL)"
  :author "egao1980"
  :license "MIT"
  :depends-on ("event-protocol" "bordeaux-threads" "cl-stack-executors")
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "backend")
               (:file "submit"))
  :in-order-to ((test-op (test-op "event-backend-nio/tests")))
  :properties
  (:cl-repo (:provides ("event-backend-nio"))))

(defsystem "event-backend-nio/tests"
  :depends-on ("event-backend-nio" "event-protocol/conformance" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "conformance"))
  :perform (test-op (o c)
             (unless (symbol-call :event-backend-nio/tests :run-conformance)
               (error "event-protocol/conformance failed against nio"))))
