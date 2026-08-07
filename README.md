# event-backend-nio

JVM **NIO `Selector`** backend for [`event-protocol`](https://github.com/egao1980/event-protocol). **ABCL-only.**

## Why

On the JVM, `java.nio` beats libuv-via-JNA (no FFI trampoline). This is the ABCL event-loop path; SBCL/CCL stay on `event-backend-libuv`.

## Usage

```lisp
(asdf:load-system "event-backend-nio")
(let* ((b (event-backend-nio:make-nio-backend))
       (loop (event-protocol:make-event-loop b)))
  (event-protocol:defer b loop (lambda () (print :hi)))
  (event-protocol:run b loop :stop-when-idle t)
  (event-backend-nio:close-loop loop))
```

`register-io` takes a `java.nio.channels.SelectableChannel` (not an OS fd integer).

## Tests

```bash
abcl --batch --load …   # or ros use abcl-bin
# asdf:test-system "event-backend-nio"
```

Requires JDK 11+ (Selector / HttpClient era).
