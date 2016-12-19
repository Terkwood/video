#lang racket/base

(require racket/contract/base
         racket/match
         racket/dict
         racket/class
         racket/file
         file/convertible
         (only-in pict pict? pict->bitmap)
         "private/init-mlt.rkt"
         "init.rkt"
         "private/mlt.rkt"
         "private/video.rkt"
         (for-syntax racket/base
                     racket/list
                     racket/syntax
                     syntax/parse))

(provide
 (contract-out
  ;; Render a video object (including the links
  [render (->* [convertible?]
               [(or/c path-string? path? #f)
                #:render-mixin (-> class? class?)
                #:profile-name (or/c string? #f)
                #:width (and/c integer? positive?)
                #:height (and/c integer? positive?)
                #:fps number?
                #:timeout (or/c number? #f)]
               void?)])
 render%
 render<%>)

(define (render video
                [dest #f]
                #:render-mixin [render-mixin values]
                #:profile-name [profile-name #f]
                #:width [width 720]
                #:height [height 576]
                #:fps [fps 25]
                #:timeout [timeout #f])
  (define dest* (or dest (make-temporary-file "rktvid~a" 'directory)))
  (define r% (render-mixin render%))
  (define renderer
    (new r%
         [dest-dir dest*]
         [width width]
         [height height]
         [fps fps]))
  (let* ([res (send renderer setup-profile!)]
         [res (send renderer prepare video)]
         [res (send renderer render res)]
         [res (send renderer play res timeout)])
    (void)))

(define render<%>
  (interface () setup-profile prepare render play))

(define render%
  (class* object% (render<%>)
    (super-new)
    (init-field dest-dir
                [width 720]
                [height 576]
                [fps 25])
    
    (define res-counter 0)
    (define/private (get-current-filename)
      (begin0 (format "resource~a" res-counter)
              (set! res-counter (add1 res-counter))))
              
    (define/public (setup-profile!)
      (define fps* (rationalize (inexact->exact fps) 1/1000000))
      (set-mlt-profile-width! profile width)
      (set-mlt-profile-height! profile height)
      (set-mlt-profile-frame-rate-den! profile (denominator fps*))
      (set-mlt-profile-frame-rate-num! profile (numerator fps*)))
    
    (define/public (prepare source)
      (cond
        [(list? source)
         (convert
          (make-playlist #:elements (for/list ([i (in-list source)])
                                      (prepare i)))
          'mlt)]
        [(pict? source)
         (define pict-name
           (build-path dest-dir (get-current-filename)))
         (send (pict->bitmap source) save-file pict-name 'png 100)
         (prepare (make-producer #:source (format "pixbuf:~a" pict-name)))]
        [(convertible? source)
         (define ret (convert source 'mlt))
         (or ret (error "Not convertible to video data"))]
        [else (raise-user-error 'render "~a is not convertible" source)]))

    (define/public (render source)
      (mlt-*-connect (make-consumer) source))
    
    (define/public (play target timeout)
      (mlt-consumer-start target)
      (let loop ([timeout timeout])
        (sleep 1)
        (when (and timeout (zero? timeout))
          (mlt-consumer-stop target))
        (unless (mlt-consumer-is-stopped target)
          (loop (and timeout (sub1 timeout))))))))