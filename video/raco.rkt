#lang racket/base

#|
   Copyright 2016-2018 Leif Andersen

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
|#

(require racket/cmdline
         racket/file
         racket/path
         racket/match
         racket/runtime-path
         "base.rkt"
         "render.rkt"
         "convert.rkt"
         "private/ffmpeg/ffmpeg.rkt")
;; Only require this if the -p flag is given, it requires gtk.
;; (require "player.rkt")

(define output-path (make-parameter (build-path (current-directory) "out.mp4")))
(define output-type (make-parameter #f))
(define output-video-codec (make-parameter 'h264))
(define output-video? (make-parameter #t))
(define output-audio? (make-parameter #t))
(define output-audio-codec (make-parameter 'aac))
(define output-subtitle-codec (make-parameter #f))
(define output-pixel-format (make-parameter 'yuv420p))
(define output-sample-format (make-parameter 'fltp))
(define output-sample-rate (make-parameter '44100))
(define output-channel-layout (make-parameter 'stereo))
(define output-width (make-parameter 1920))
(define output-height (make-parameter 1080))
(define output-start (make-parameter #f))
(define output-end (make-parameter #f))
(define output-fps (make-parameter 30))
(define output-verbose (make-parameter #f))
(define output-silent (make-parameter #f))
(define output-preview? (make-parameter #f))
(define output-vframes (make-parameter #f))
(define output-aframes (make-parameter #f))
(define output-dframes (make-parameter #f))
(define input-media? (make-parameter #f))
(define probe-media? (make-parameter #f))

(define rendering-box (box #f))

(define (cmd-str->num who val)
  (define ret (string->number val))
  (unless ret
    (raise-user-error '|raco video| "The ~a parameter must be a number" val))
  ret)

(define-runtime-path here ".")

(module+ main
  (define video-string
    (command-line
     #:program "video"
     #:once-any
     [("--enable-video") "Enable Video Output"
                         (output-video? #t)]
     [("--disable-video") "Disable Video Output"
                          (output-video? #f)]
     #:once-any
     [("--enable-audio") "Enable Audio Output"
                         (output-audio? #t)]
     [("--disable-audio") "Disable Audio Output"
                          (output-audio? #f)]
     #:once-each
     [("-f" "--format") format
                        "Output type"
                        (output-type (string->symbol format))]
     [("--video-codec") video-codec
                        "Output video codec"
                        (output-video-codec (string->symbol video-codec))]
     [("--audio-codec") audio-codec
                        "Output audio codec"
                        (output-audio-codec (string->symbol audio-codec))]
     [("--subtitle-codec") subtitle-codec
                           "Output subtitle codec"
                           (output-subtitle-codec (string->symbol subtitle-codec))]
     [("--pixel-format") pixel-format
                         "Output pixel format"
                         (output-pixel-format (string->symbol pixel-format))]
     [("--sample-format") sample-format
                          "Output sample format"
                          (output-sample-format (string->symbol sample-format))]
     [("--sample-rate") sample-rate
                        "Output sample rate"
                        (output-sample-rate (cmd-str->num "--sample-rate" sample-rate))]
     [("--channel-layout") channel-layout
                           "Output channel layout"
                           (output-channel-layout (string->symbol channel-layout))]
     [("-o" "--out") file
                     "Output File"
                     (output-path (path->complete-path file))]
     [("-w" "--width") width
                       "Video width"
                       (output-width  (cmd-str->num "--width" width))]
     [("-l" "--height") height
                        "Video height"
                        (output-height (cmd-str->num "--height" height))]
     [("-s" "--start") start
                       "Rendering start start"
                       (output-start (cmd-str->num "--start" start))]
     [("-e" "--end")  end
                      "Rendering end position"
                      (output-end (cmd-str->num "--end" end))]
     [("--fps") fps
                "Rendering FPS"
                (output-fps (cmd-str->num "--fps" fps))]
     [("--vframes") vframes
                    "Number of video frames to output"
                    (output-vframes (cmd-str->num "--vframes" vframes))]
     [("--aframes") aframes
                    "Number of audio frames to output"
                    (output-aframes (cmd-str->num "--aframes" aframes))]
     [("--dframes") dframes
                    "Number of data frames to output"
                    (output-dframes (cmd-str->num "--dframes" dframes))]
     [("-v" "--verbose") "Output a copy of the graph used for rendering"
                         (output-verbose #t)]
     [("-q" "--silent") "Do not print any output, used for scripts"
                        (output-silent #t)]
     [("-p" "--preview") "Preview the output in a player"
                         (output-preview? #t)]
     [("-m" "--media") "Play or encode a media file directly"
                       (input-media? #t)]
     [("--probe") "Probe a media file"
                  (probe-media? #t)]
     #:args (video)
     video))

  (define video-path
    (with-handlers ([exn:fail
                     (λ (e)
                       (raise-user-error '|raco video|
                                         "The file parameter must be a path, given: ~a"
                                         video-string))])
      (string->path video-string)))

  (define video
    (if (input-media?)
        (clip video-path)
        (dynamic-require video-path 'vid)))

  (define render-mixin
    #f
    #;
    (match (output-type)
      ["mp4" mp4:render-mixin]
      ["jpg" jpg:render-mixin]
      ["png" png:render-mixin]
      ["xml" xml:render-mixin]
      [_ #f]))

  (when (probe-media?)
    (av-log-set-callback av-log-default-callback))

  (cond
    [(output-preview?)
     (define preview (dynamic-require (build-path here "player.rkt") 'player))
     (void (preview video #:convert-database (make-base-database)))]
    [else
     (match (output-type)
       [_ ;(or "png" "jpg" "mp4" "xml")
        (render/pretty video (output-path)
                       #:probe? (probe-media?)
                       #:convert-database (make-base-database)
                       #:start (output-start)
                       #:end (output-end)
                       #:width (output-width)
                       #:height (output-height)
                       #:render-mixin render-mixin
                       #:render-video? (output-video?)
                       #:render-audio? (output-audio?)
                       #:format (output-type)
                       #:sample-fmt (output-sample-format)
                       #:pix-fmt (output-pixel-format)
                       #:mode (cond
                                [(output-silent) 'silent]
                                [(output-verbose) 'verbose]
                                [else #f]))])]))
#|
     (newline)
     (let loop ()
       (let ()
         (define r (unbox rendering-box))
         (when r
           (define len (get-rendering-length r))
           (define pos (get-rendering-position r))
           (if len
               (printf "\r~a/~a (~a%)            " pos len (* (/ pos len) 100.0))
               (displayln "Unbounded Video"))))
       (sleep 1)
       (if (thread-running? t)
           (loop)
           (newline)))]
    [_ (void (preview video))]))
|#
