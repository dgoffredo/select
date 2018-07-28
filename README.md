![`select` mascot](select.png)

`select`
========
Go-style channel `select` syntax in Racket

Why
---
Racket's threads and channels resemble Go's goroutines and channels, and
Racket's [sync][racket-sync] procedure resembles
[Go's select statement][go-select].

Racket comes with `(sync <events> ...)`, which returns the value of the
first of the `<events> ...` to become available. It would be convenient to
automatically associate each possible result with a behavior (a `lambda`),
preferrably without having to type `lambda`.

While we're at it, let's exercise some macro trickery to make it look almost
exactly like Go's `select` statement!

It is overkill.

What
----
[select](select/) is a Racket collection that provides a macro, `select`,
which does multiple-[event][racket-event] synchronization in a syntax
reminiscent of Go.

More
----
### Example
```racket
(define c1 (make-channel))
(define c2 (make-channel))
(define c3 (make-channel))
(define c4 (make-channel))
(define c5 (make-channel))

(define threads
  (list (thread (lambda () (channel-put c1 "hello from thread 1")))
        (thread (lambda () (channel-put c2 "hello from thread 2")))
        (thread (lambda () (channel-get c3)))
        (thread (lambda () (channel-put c4 '("hello from thread" 4))))
        (thread (lambda () (channel-put c5 "I stole this channel!")))))

(sleep 0.1)

(select
  [<-c5                   (printf "got something from c5~n")]
  [foo := <-c1            (printf "got ~s from c1~n" foo)] 
  [bar := <-(if #f c1 c2) (printf "got ~s from c2~n" bar)]
  [c3 <- 3.445            (printf "sent something to c3~n")]
  [a b := <-c4            (printf "got ~s and ~s from c4~n" a b)]
  [(after 5 seconds)      (printf "nothing ready within 5 seconds~n")]
  [<-(after 0.05 minutes) (printf "nothing ready within 0.05 minutes~n")]
  [default                (printf "nothing ready immediately~n")]))
```

### Install
```console
$ cd select
$ raco pkg install
```

### Grammar
`select` evaluates to the result of executing exactly one of its `<body>`
forms. `select` is of the form:
```racket
(select
  [<binding> <body>] ...)
```
where each `<body>` is a single form, and `<binding>` is any of the following:
```racket
event                         ; (1)
<-event                       ; (2)
<-(form ...)                  ; (3)
pattern := expr               ; (4)
multiple patterns ... := expr ; (5)
sink <- value                 ; (6)
default                       ; (7)
```
1. Evaluate `event`. If the resulting event becomes available, execute the body
   without binding any variables.
2. same as `(1)`
3. Evaluate `(form ...)`. If the resulting event becomes available, execute the
   body without binding any variables.
4. Evaluate `expr`. If the resulting event becomes available, `match` the
   received value against the `pattern` and execute the body.
5. Evaluate `expr`. If the resulting event becomes available, `match` the
   received value against the pattern `(list multiple patterns ...)` and
   execute the body.
6. Evaluate `value` and put it into the `sink` channel. If the put is
   successful, execute the body.
7. If no other operations were immediately successful, execute the body.

Additionally, the `after` macro provides convenient syntax for specifying
timeouts. `after` returns an event that becomes available after the
specified timeout. The timeout is expressed in some units. `after` is of the
form `(after <number> <unit>)`, where `<number>` is a number and `<units>`
is one of `days`, `hours`, `minutes`, `seconds`, `milliseconds`,
`microseconds`, or `nanoseconds`. For example,
```racket
(select
  [(after 10 seconds)              "zero"]
  [(after 3 microseconds)          "one"]
  [(after 23 milliseconds)         "two"]
  [(after 0.04 minutes)            "three"]
  [(after (* 4 0.03) days)         "four"]
  [(after (expt 2 12) nanoseconds) "five"])
```
evaluates to `1`.

[racket-sync]: https://docs.racket-lang.org/reference/sync.html#%28def._%28%28quote._~23~25kernel%29._sync%29%29
[go-select]: https://tour.golang.org/concurrency/5
[racket-event]: https://docs.racket-lang.org/reference/sync.html