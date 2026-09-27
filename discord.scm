(require-builtin steel/json)
(require-builtin steel/process)
(require-builtin steel/threads)
(require-builtin steel/time)
(require "steel/result")
(require "helix/editor.scm")
(require (only-in "helix/misc.scm" enqueue-thread-local-callback-with-delay))

(provide discord-worker-start discord-worker-send! discord-worker-poll
  discord-worker-finished?
  discord-worker-result
  discord-worker-kill!
  discord-start
  discord-stop)

(struct Worker (requests events thread))

(define (next-request inbox)
  (define deadline (+ (current-milliseconds) 15000))
  (let loop ()
    (define request (channel/try-recv inbox))
    (cond
      [(disconnected-channel-object? request) (hash 'v 1 'op "shutdown")]
      [(not (empty-channel-object? request)) request]
      [(>= (current-milliseconds) deadline) (hash 'v 1 'op "shutdown")]
      [else (time/sleep-ms 50) (loop)])))

(define (discord-worker-start executable arguments)
  (define requests (channels/new))
  (define events (channels/new))
  (define inbox (channels-receiver requests))
  (define outbox (channels-sender events))
  (define thread
    (spawn-native-thread
      (lambda ()
        (define child #f)
        (define input #f)
        (define output #f)
        (define (ignore-error thunk)
          (with-handler (lambda (_) #f) (thunk)))
        (define (notify event)
          (ignore-error (lambda () (channel/send outbox event))))
        (with-handler
          (lambda (error)
            (notify (hash 'kind 'error 'message (to-string error)))
            (when input (ignore-error (lambda () (close-output-port input))))
            (when output (ignore-error (lambda () (close-input-port output))))
            (when child (ignore-error (lambda () (subprocess-kill child)))))
          (define builder (command executable arguments))
          (with-stdin-piped builder)
          (with-stdout-piped builder)
          (with-stderr builder (open-output-file "/dev/null" #:exists 'append))
          (set! child (unwrap-ok (spawn-process builder)))
          (set! input (child-stdin child))
          (set! output (child-stdout child))
          (notify (hash 'kind 'started 'child child))
          (let loop ()
            (define request (next-request inbox))
            (display (value->jsexpr-string request) input)
            (newline input)
            (flush-output-port input)
            (define response (read-line output))
            (when (eof-object? response)
              (error "discord-hx closed its output"))
            (define reply (string->jsexpr response))
            (unless (and (= (hash-ref reply 'v) 1) (hash-ref reply 'ok))
              (error (string-append "discord-hx: " (hash-ref reply 'error))))
            (notify (hash 'kind 'reply 'value reply))
            (unless (equal? (hash-ref request 'op) "shutdown") (loop)))
          (close-output-port input)
          (close-input-port output)
          (wait child)))))
  (Worker (channels-sender requests) (channels-receiver events) thread))

(define (discord-worker-send! worker request)
  (channel/send (Worker-requests worker) request))

(define (discord-worker-poll worker)
  (channel/try-recv (Worker-events worker)))

(define (discord-worker-finished? worker)
  (thread-finished? (Worker-thread worker)))

(define (discord-worker-result worker)
  (thread-join! (Worker-thread worker)))

(define (discord-worker-kill! child)
  (spawn-native-thread
    (lambda () (with-handler (lambda (_) #f) (subprocess-kill child)))))

(define *discord-worker* #f)
(define *discord-generation* 0)
(define DISCORD-UPDATE-INTERVAL-MS 2500)

(define (discord-snapshot)
  (define document (editor->doc-id (editor-focus)))
  (define path (editor-document->path document))
  (define language (editor-document->language document))
  (cond
    [(and (string? path) (string? language))
      (hash 'v 1 'op "update" 'path path 'language language)]
    [(string? path)
      (hash 'v 1 'op "update" 'path path)]
    [(string? language)
      (hash 'v 1 'op "update" 'language language)]
    [else (hash 'v 1 'op "update")]))

(define (discord-report-events worker)
  (let loop ()
    (define event (discord-worker-poll worker))
    (cond
      [(empty-channel-object? event) #t]
      [(disconnected-channel-object? event) #f]
      [(equal? (hash-ref event 'kind) 'error)
        (displayln (string-append "discord-hx: " (hash-ref event 'message)))
        #f]
      [else (loop)])))

(define (discord-update generation)
  (when (= generation *discord-generation*)
    (let ([worker *discord-worker*])
      (when worker
        (if (or (not (discord-report-events worker))
             (discord-worker-finished? worker))
          (set! *discord-worker* #f)
          (begin
            (discord-worker-send! worker (discord-snapshot))
            (enqueue-thread-local-callback-with-delay
              DISCORD-UPDATE-INTERVAL-MS
              (lambda () (discord-update generation)))))))))

(define (discord-start application-id . arguments)
  (discord-stop)
  (set! *discord-worker*
    (discord-worker-start
      "discord-hx"
      (append (list "--application-id"
               (if (string? application-id) application-id (to-string application-id)))
        arguments)))
  (let ([generation *discord-generation*])
    (enqueue-thread-local-callback-with-delay
      0
      (lambda () (discord-update generation)))))

(define (discord-stop)
  (set! *discord-generation* (+ *discord-generation* 1))
  (when *discord-worker*
    (discord-worker-send! *discord-worker* (hash 'v 1 'op "shutdown"))
    (set! *discord-worker* #f)))
