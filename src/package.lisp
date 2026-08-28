(defpackage #:event-backend-nio
  (:use #:cl #:event-protocol)
  (:shadowing-import-from #:event-protocol #:run)
  (:import-from #:cl-stack-executors
                #:make-thread-pool
                #:executor-runner
                #:executor-shutdown)
  (:export #:nio-backend
           #:make-nio-backend
           #:nio-loop
           #:close-loop
           #:wake-call))
(in-package #:event-backend-nio)
