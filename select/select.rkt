#lang racket

(provide select ; wait for first among several events
         after) ; convenient timeout event syntax

(require (for-syntax threading)) ; ~> and ~>> macros

(define-syntax (strip-arrow stx)
  ; If the specified syntax is a symbol that begins with the two characters
  ; "<-", then return the syntax after having stripped that prefix. Otherwise,
  ; return the syntax unmodified.
  (syntax-case stx ()
    [(strip-arrow form)
     (let ([datum (syntax->datum #'form)])
       ; It's a symbol. Make sure it's large enough and begins with an arrow.
       ; If so, return the syntax but without the leading arrow.
       (if (symbol? datum)
         (let ([str (symbol->string datum)])
           (cond
             [(<= (string-length str) (string-length "<-")) #'form] ; too short
             [(not (equal? (substring str 0 2) "<-"))       #'form] ; no arrow
             [else (~> str 
                     (substring 2) string->symbol (datum->syntax #'form _))]))
         ; It's not a symbol, so just return the original syntax.
         #'form))]))

(define-syntax clause->evt
  ; Map supported `select` clause syntaxes to corresponding events on which
  ; `sync` can wait.
  (syntax-rules (:= <-)
    [(_ [expr body])
     (wrap-evt (strip-arrow expr) (lambda args body))]

    [(_ [<- from body])
     (wrap-evt from (lambda args-ignored body))]

    [(_ [to <- expr body])
     (wrap-evt (channel-put-evt to expr) (lambda args-ignored body))]

    [(_ [pattern := <- source body])
     (wrap-evt source (match-lambda [pattern body]))]

    [(_ [pattern patterns ... := <- source body])
     (wrap-evt source (match-lambda [(list pattern patterns ...) body]))]

    [(_ [pattern := arrowed-source body])
     (clause->evt 
       [pattern := <- (strip-arrow arrowed-source) body])]

    [(_ [pattern patterns ... := arrowed-source body])
     (clause->evt 
       [pattern patterns ... := <- (strip-arrow arrowed-source) body])]

    [(_ expr)
     expr]))

(define (timeout-evt delay-milliseconds)
  ; Return an event that becomes available `delay-milliseconds` from now.
  (let ([deadline (+ (current-inexact-milliseconds) delay-milliseconds)])
    (alarm-evt deadline)))

(define-syntax units->milliseconds
  ; Convert the specified "quantity with units" time interval into a number of
  ; milliseconds.
  (syntax-rules 
    (days hours minutes seconds milliseconds microseconds nanoseconds)

    [(units->milliseconds quantity days)
     (* 24 (units->milliseconds quantity hours))]

    [(units->milliseconds quantity hours)
     (* 60 (units->milliseconds quantity minutes))]

    [(units->milliseconds quantity minutes)
     (* 60 (units->milliseconds quantity seconds))]

    [(units->milliseconds quantity seconds)
     (* 1000 (units->milliseconds quantity milliseconds))]

    [(units->milliseconds quantity milliseconds)
     quantity]

    [(units->milliseconds quantity microseconds)
     (/ (units->milliseconds quantity milliseconds) 1000)]

    [(units->milliseconds quantity nanoseconds)
     (/ (units->milliseconds quantity microseconds) 1000)]))

(define-syntax-rule (after timeout units)
  ; Return an event that becomes available after the specified "quantity with
  ; units" time interval.
  (timeout-evt (units->milliseconds timeout units)))

(define-syntax select
  ; Provide Go-like syntax around `sync`.
  (syntax-rules (default after)
    [(select clauses ... [default what-then])
     (sync/timeout (lambda () what-then)
       (clause->evt clauses) ...)]

    [(select clause clauses ...)
     (sync (clause->evt clause) (clause->evt clauses) ...)]))

(module+ example
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
