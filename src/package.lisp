(defpackage #:event-backend-nio
  (:use #:cl #:event-protocol)
  (:shadowing-import-from #:event-protocol #:run)
  (:export #:nio-backend
           #:make-nio-backend
           #:nio-loop
           #:close-loop
           #:wake-call))
(in-package #:event-backend-nio)
