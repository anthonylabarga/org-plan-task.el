;;; org-plan-task-org.el --- Org sources and atomic plan updates -*- lexical-binding: t; -*-

;; Copyright (C) 2026 John Anthony Labarga
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Read explicit timed spans from live Org buffers and maintain PLAN
;; drawers without changing child headings or other section contents.

;;; Code:

(require 'org)
(require 'org-agenda)
(require 'org-element)
(require 'org-plan-task-time)

(defun org-plan-task--target ()
  "Return a marker at the source heading, or signal a context error."
  (cond
   ((derived-mode-p 'org-agenda-mode)
    (let ((marker (or (org-get-at-bol 'org-hd-marker)
                      (org-get-at-bol 'org-marker))))
      (unless (and (markerp marker) (marker-buffer marker)
                   (buffer-live-p (marker-buffer marker)))
        (user-error "Agenda entry has no live Org source marker"))
      (with-current-buffer (marker-buffer marker)
        (save-restriction
          (widen)
          (save-excursion
            (goto-char marker)
            (unless (and (derived-mode-p 'org-mode) (org-at-heading-p))
              (user-error "Agenda source marker is stale or is not an Org heading"))
            (copy-marker (point)))))))
   ((derived-mode-p 'org-mode)
    (save-restriction
      (widen)
      (save-excursion
        (when (org-before-first-heading-p)
          (user-error "Move to an Org task heading first"))
        (org-back-to-heading t)
        (copy-marker (point)))))
   (t (user-error "Invoke org-plan-task in an Org task or on an agenda entry"))))

(defun org-plan-task--timestamp-span (timestamp)
  "Return the explicit active timed span in TIMESTAMP, or nil.
Point timestamps may have end fields too; check the raw range syntax."
  (when (and timestamp
             (eq (org-element-property :type timestamp) 'active-range))
    (let ((raw (org-element-property :raw-value timestamp)))
      (when (or (string-match-p "[0-9]:[0-9][0-9]-[0-9]+:[0-9][0-9]" raw)
                (string-match-p
                 "[0-9]:[0-9][0-9][^>]*>--<[^>]*[0-9]:[0-9][0-9]" raw))
        (let ((start (org-plan-task--timestamp-time timestamp "start"))
              (end (org-plan-task--timestamp-time timestamp "end")))
          (unless (< start end)
            (user-error "Timed span must end after its start: %s" raw))
          (cons start end))))))

(defun org-plan-task--timestamp-time (timestamp side)
  "Return the time of TIMESTAMP at SIDE, either \"start\" or \"end\"."
  (let ((field (lambda (name)
                 (org-element-property (intern (concat ":" name "-" side))
                                       timestamp))))
    (unless (and (calendar-date-is-valid-p
                  (list (funcall field "month") (funcall field "day")
                        (funcall field "year")))
                 (integerp (funcall field "hour"))
                 (<= 0 (funcall field "hour") 23)
                 (integerp (funcall field "minute"))
                 (<= 0 (funcall field "minute") 59))
      (user-error "Invalid date or clock in timed span: %s"
                  (org-element-property :raw-value timestamp)))
    (float-time
     (encode-time 0 (funcall field "minute") (funcall field "hour")
                  (funcall field "day") (funcall field "month")
                  (funcall field "year")))))

(defun org-plan-task--event (timestamp)
  "Return a conflict event for TIMESTAMP, or nil for a reminder."
  (let ((span (org-plan-task--timestamp-span timestamp)))
    (when span
      (list :span span :raw (org-element-property :raw-value timestamp)
            :repeat (org-element-property :repeater-value timestamp)
            :unit (org-element-property :repeater-unit timestamp)))))

(defun org-plan-task--buffer-events ()
  "Read conflict events in the current buffer, including planning metadata."
  (save-excursion
    (save-restriction
      (widen)
      (let (events)
        (org-element-map (org-element-parse-buffer) '(timestamp planning)
          (lambda (element)
            (dolist (timestamp
                     (if (eq (org-element-type element) 'planning)
                         (list (org-element-property :scheduled element)
                               (org-element-property :deadline element))
                       (unless (org-element-lineage element '(clock))
                         (list element))))
              (let ((event (org-plan-task--event timestamp)))
                (when event (push event events))))))
        events))))

(defun org-plan-task--events (task-buffer)
  "Read all agenda conflict sources and TASK-BUFFER, using unsaved edits.
Unreadable registered files are errors even when Org would skip them."
  (let* ((org-agenda-skip-unavailable-files nil)
         (files (condition-case err (org-agenda-files t)
                  (error (user-error "Cannot resolve agenda files: %s"
                                     (error-message-string err)))))
         (buffers (list task-buffer)) events)
    (dolist (file files)
      (unless (file-readable-p file)
        (user-error "Cannot read agenda conflict source: %s" file))
      (condition-case err
          (push (or (find-buffer-visiting file) (find-file-noselect file)) buffers)
        (error (user-error "Cannot read agenda conflict source %s: %s"
                           file (error-message-string err)))))
    (dolist (buffer (delete-dups buffers))
      (with-current-buffer buffer
        (unless (derived-mode-p 'org-mode)
          (user-error "Conflict source is not in Org mode: %s" (buffer-name)))
        (setq events (nconc (org-plan-task--buffer-events) events))))
    events))

(defun org-plan-task--event-spans (event date)
  "Expand EVENT into spans overlapping local calendar DATE.
Use Org recurrence dates for daily, weekly, monthly and yearly spans.
Hourly repeaters recur at elapsed-hour intervals.  Diary sexps are ignored."
  (let* ((span (plist-get event :span))
         (repeat (plist-get event :repeat))
         (unit (plist-get event :unit))
         (lower (org-plan-task--at date 0))
         (upper (org-plan-task--at (org-plan-task--date-add date 1) 0))
         (window (cons lower upper)) result)
    (cond
     ((or (not repeat) (<= repeat 0))
      (when (org-plan-task--overlap-p span window) (list span)))
     ((eq unit 'hour)
      (let* ((step (* repeat 3600))
             (index (max 0 (floor (- lower (cdr span)) step)))
             (start (+ (car span) (* index step)))
             (end (+ (cdr span) (* index step))))
        (while (< start upper)
          (when quit-flag (keyboard-quit))
          (when (org-plan-task--overlap-p (cons start end) window)
            (push (cons start end) result))
          (setq start (+ start step) end (+ end step)))
        (nreverse result)))
     (t
      (let* ((base (org-plan-task--date (car span)))
             (base-day (calendar-absolute-from-gregorian base))
             (end-date (org-plan-task--date (cdr span)))
             (days (- (calendar-absolute-from-gregorian end-date) base-day))
             (start-clock (decode-time (car span)))
             (end-clock (decode-time (cdr span)))
             (start-minute (+ (* 60 (nth 2 start-clock)) (nth 1 start-clock)))
             (end-minute (+ (* 60 (nth 2 end-clock)) (nth 1 end-clock)))
             (raw (plist-get event :raw))
             (day (max base-day
                       (org-closest-date raw
                                         (- (calendar-absolute-from-gregorian date)
                                            days 1)
                                         'past)))
             (start (org-plan-task--at (calendar-gregorian-from-absolute day)
                                       start-minute)))
        (while (< start upper)
          (when quit-flag (keyboard-quit))
          (let ((end (org-plan-task--at
                      (calendar-gregorian-from-absolute (+ day days)) end-minute)))
            (when (org-plan-task--overlap-p (cons start end) window)
              (push (cons start end) result)))
          (let ((next (org-closest-date raw (1+ day) 'future)))
            (unless (> next day)
              (user-error "Cannot advance repeating timestamp: %s" raw))
            (setq day next
                  start (org-plan-task--at (calendar-gregorian-from-absolute day)
                                           start-minute))))
        (nreverse result))))))

(defun org-plan-task--section-end ()
  "Return the end of the current heading's own section."
  (save-excursion (outline-next-heading) (point)))

(defun org-plan-task--plan ()
  "Read the heading's own PLAN drawer at point.
Return a plist with :begin, :end and :spans, or nil.  Reject duplicate,
unclosed, nested, empty or non-timestamp PLAN drawers."
  (save-excursion
    (org-back-to-heading t)
    (let ((limit (org-plan-task--section-end)) open begin end found spans)
      (forward-line 1)
      (while (< (point) limit)
        (cond
         ;; Literal examples of drawers are body text, not a plan.
         ((and (not (equal open "PLAN"))
               (let ((case-fold-search t))
                 (looking-at-p "^[ \t]*#\\+begin_\\(?:src\\|example\\|export\\|comment\\)\\b"))
               (let ((element (org-element-at-point)))
                 (when (memq (org-element-type element)
                             '(src-block example-block export-block comment-block))
                   (goto-char (min limit (org-element-property :end element)))
                   t)))
          (forward-line -1))
         ((looking-at "^[ \t]*:\\([[:alnum:]_@#%]+\\):[ \t]*$")
          (let ((name (upcase (match-string-no-properties 1))))
            (cond
             ((equal name "END")
              (when (equal open "PLAN") (setq end (min limit (1+ (line-end-position)))))
              (setq open nil))
             ((equal name "PLAN")
              (when (or found open) (user-error "Duplicate or nested PLAN drawer"))
              (setq found t open name begin (line-beginning-position)))
             ((equal open "PLAN") (user-error "Nested drawer inside PLAN"))
             (t (setq open name)))))
         ((and (equal open "PLAN") (not (looking-at-p "^[ \t]*$")))
          (let* ((line (string-trim (buffer-substring-no-properties
                                    (line-beginning-position) (line-end-position))))
                 (timestamp (with-temp-buffer
                              (insert line) (goto-char (point-min))
                              (org-element-timestamp-parser)))
                 (span (org-plan-task--timestamp-span timestamp)))
            (unless (and span
                         (equal line (org-element-property :raw-value timestamp))
                         (not (org-element-property :repeater-value timestamp)))
              (user-error "PLAN must contain only explicit, non-repeating timed ranges"))
            (push span spans))))
        (forward-line 1))
      (when found
        (unless (and end spans) (user-error "Unclosed or empty PLAN drawer"))
        (list :begin begin :end end :spans (nreverse spans))))))

(defun org-plan-task--deadline-time (deadline config)
  "Interpret DEADLINE as an instant, using CONFIG end for date-only values."
  (unless (and (stringp deadline)
               (string-match-p "[0-9]\\{4\\}-[0-9][0-9]-[0-9][0-9]" deadline))
    (user-error "Invalid Org deadline: %S" deadline))
  (if (string-match-p "[0-9]:[0-9][0-9]" deadline)
      (float-time (org-time-string-to-time deadline))
    (org-plan-task--at (org-date-to-gregorian deadline) (plist-get config :end))))

(defun org-plan-task--commit (effort deadline spans)
  "Atomically store EFFORT, optional new DEADLINE and all SPANS at point."
  (let ((org-inhibit-logging t)
        (org-log-redeadline nil))
    (atomic-change-group
      (org-entry-put nil "EFFORT" effort)
      (when deadline (org-deadline nil deadline))
      (let ((plan (org-plan-task--plan)))
        (when plan (delete-region (plist-get plan :begin) (plist-get plan :end))))
      (org-back-to-heading t)
      (org-end-of-meta-data)
      (unless (bolp) (insert "\n"))
      (insert ":PLAN:\n"
              (mapconcat #'org-plan-task--format-span (org-plan-task--merge spans) "\n")
              "\n:END:\n"))))

(provide 'org-plan-task-org)
;;; org-plan-task-org.el ends here
