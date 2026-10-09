;;; org-plan-task-time.el --- Calendar and interval calculations -*- lexical-binding: t; -*-

;; Copyright (C) 2026 John Anthony Labarga
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Local calendar arithmetic and half-open intervals for org-plan-task.
;; Intervals are cons cells of floating point Unix seconds.

;;; Code:

(require 'calendar)
(require 'cl-lib)
(require 'org)
(require 'seq)

(defgroup org-plan-task nil
  "Interactively plan time blocks for Org tasks."
  :group 'org :prefix "org-plan-task-")

(defcustom org-plan-task-workday-list
  '("Monday" "Tuesday" "Wednesday" "Thursday" "Friday")
  "Working weekdays as full English names, ignoring case.
Accept a list or vector.  At least one weekday must be specified."
  :type '(choice (repeat string) (sexp :tag "Vector of weekday names"))
  :group 'org-plan-task)

(defcustom org-plan-task-start-workday "09:00"
  "Local start of the workday, in 24-hour HH:MM format."
  :type 'string :group 'org-plan-task)

(defcustom org-plan-task-end-workday "17:00"
  "Local end of the workday, in 24-hour HH:MM format.
The end must be later than the start on the same calendar day."
  :type 'string :group 'org-plan-task)

(defcustom org-plan-task-breaks nil
  "Daily breaks as pairs of HH:MM strings.
For example, ((\"12:00\" \"13:00\") (\"15:00\" \"15:15\")).
Accept lists or vectors, including vector pairs.  Breaks must not
overlap and must be entirely inside the workday."
  :type '(choice (repeat (list string string))
                 (sexp :tag "List or vector of break pairs"))
  :group 'org-plan-task)

(defconst org-plan-task--weekdays
  '("sunday" "monday" "tuesday" "wednesday" "thursday" "friday" "saturday")
  "English weekday names indexed from Sunday.")

(defun org-plan-task--clock (value)
  "Convert HH:MM string VALUE to minutes, rejecting invalid clocks."
  (unless (and (stringp value)
               (string-match "\\`\\([01][0-9]\\|2[0-3]\\):\\([0-5][0-9]\\)\\'" value))
    (user-error "Invalid workday clock: %S (expected HH:MM)" value))
  (+ (* 60 (string-to-number (match-string 1 value)))
     (string-to-number (match-string 2 value))))

(defun org-plan-task--sequence (value)
  "Convert list or vector VALUE to a list, rejecting other values."
  (unless (or (proper-list-p value) (vectorp value))
    (user-error "Expected a list or vector: %S" value))
  (append value nil))

(defun org-plan-task--overlap-p (a b)
  "Return non-nil if half-open intervals A and B overlap positively."
  (and (< (car a) (cdr b)) (< (car b) (cdr a))))

(defun org-plan-task--configuration ()
  "Validate customization and return a normalized configuration plist."
  (let* ((start (org-plan-task--clock org-plan-task-start-workday))
         (end (org-plan-task--clock org-plan-task-end-workday))
         (days (mapcar
                (lambda (name)
                  (or (and (stringp name)
                           (cl-position (downcase name) org-plan-task--weekdays
                                        :test #'equal))
                      (user-error "Invalid weekday: %S" name)))
                (org-plan-task--sequence org-plan-task-workday-list)))
         (breaks
          (sort (mapcar
                 (lambda (pair)
                   (setq pair (org-plan-task--sequence pair))
                   (unless (= (length pair) 2)
                     (user-error "A break must contain two clocks: %S" pair))
                   (cons (org-plan-task--clock (car pair))
                         (org-plan-task--clock (cadr pair))))
                 (org-plan-task--sequence org-plan-task-breaks))
                (lambda (a b) (< (car a) (car b)))))
         (previous-end start))
    (unless days (user-error "At least one workday is required"))
    (unless (< start end) (user-error "Work hours must increase within one day"))
    (dolist (break breaks)
      (unless (and (<= start (car break)) (< (car break) (cdr break))
                   (<= (cdr break) end) (<= previous-end (car break)))
        (user-error "Breaks must increase, not overlap, and be inside work hours"))
      (setq previous-end (cdr break)))
    (let ((config (list :days days :start start :end end :breaks breaks)))
      (unless (org-plan-task--slot-minutes config)
        (user-error "Work hours and breaks leave no complete half-hour block"))
      config)))

(defun org-plan-task--slot-minutes (config)
  "Return available half-hour start minutes in CONFIG."
  (let ((minute (* 30 (ceiling (plist-get config :start) 30))) result)
    (while (<= (+ minute 30) (plist-get config :end))
      (unless (seq-some (lambda (break)
                          (org-plan-task--overlap-p (cons minute (+ minute 30)) break))
                        (plist-get config :breaks))
        (push minute result))
      (setq minute (+ minute 30)))
    (nreverse result)))

(defun org-plan-task--date (time)
  "Return the local Gregorian date (month day year) of TIME."
  (let ((decoded (decode-time time)))
    (list (nth 4 decoded) (nth 3 decoded) (nth 5 decoded))))

(defun org-plan-task--date-add (date days)
  "Advance Gregorian DATE by calendar DAYS, independently of DST."
  (calendar-gregorian-from-absolute
   (+ days (calendar-absolute-from-gregorian date))))

(defun org-plan-task--at (date minute)
  "Return local time on Gregorian DATE at MINUTE after midnight."
  (float-time (encode-time 0 (% minute 60) (/ minute 60)
                           (nth 1 date) (car date) (nth 2 date))))

(defun org-plan-task--day-slots (date config now)
  "Return complete work blocks on DATE in CONFIG, starting at or after NOW.
Skip nonexistent local times during daylight-saving transitions."
  (when (memq (calendar-day-of-week date) (plist-get config :days))
    (delq nil
          (mapcar
           (lambda (minute)
             (let ((start (org-plan-task--at date minute))
                   (end (org-plan-task--at date (+ minute 30))))
               (when (and (>= start now) (= (- end start) 1800)
                          (equal (format-time-string "%H:%M" start)
                                 (format "%02d:%02d" (/ minute 60) (% minute 60))))
                 (cons start end))))
           (org-plan-task--slot-minutes config)))))

(defun org-plan-task--minutes (effort)
  "Parse positive EFFORT according to Org duration conventions."
  (let ((minutes (and (stringp effort)
                      (condition-case nil (org-duration-to-minutes effort)
                        (error nil)))))
    (unless (and minutes (> minutes 0))
      (user-error "Effort must be a positive Org duration: %S" effort))
    minutes))

(defun org-plan-task--allocation (effort &optional old)
  "Return rounded minutes to allocate for EFFORT, or its increase over OLD."
  (let ((increase (- (org-plan-task--minutes effort)
                     (if old (org-plan-task--minutes old) 0))))
    (unless (> increase 0)
      (user-error "New effort must exceed the old estimate (%s)" old))
    (* 30 (ceiling increase 30))))

(defun org-plan-task--merge (spans)
  "Sort and merge SPANS touching or overlapping on the same local date."
  (let (result)
    (dolist (span (sort (copy-tree spans) (lambda (a b) (< (car a) (car b)))))
      (let ((previous (car result)))
        (if (and previous (<= (car span) (cdr previous))
                 (equal (org-plan-task--date (car previous))
                        (org-plan-task--date (car span)))
                 (equal (org-plan-task--date (car previous))
                        (org-plan-task--date (cdr previous)))
                 (equal (org-plan-task--date (car span))
                        (org-plan-task--date (cdr span))))
            (setcdr previous (max (cdr previous) (cdr span)))
          (push span result))))
    (nreverse result)))

(defun org-plan-task--format-span (span)
  "Format SPAN as an active Org timestamp range with English weekdays."
  (let ((system-time-locale "C"))
    (if (equal (org-plan-task--date (car span))
               (org-plan-task--date (cdr span)))
        (concat (format-time-string "<%Y-%m-%d %a %H:%M" (car span))
                (format-time-string "-%H:%M>" (cdr span)))
      (concat (format-time-string "<%Y-%m-%d %a %H:%M>" (car span))
              "--" (format-time-string "<%Y-%m-%d %a %H:%M>" (cdr span))))))

(provide 'org-plan-task-time)
;;; org-plan-task-time.el ends here
