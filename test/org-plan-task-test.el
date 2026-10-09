;;; org-plan-task-test.el --- Regression tests -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Run with emacs -Q --batch -L . -L test -l this file and ERT.

;;; Code:

(require 'ert)
(require 'cl-lib)
(setq load-prefer-newer t)
(require 'org-plan-task)

(defmacro org-plan-task-test--task (text &rest body)
  "Execute BODY in a fresh Org task containing TEXT and default options."
  (declare (indent 1) (debug t))
  `(let ((org-plan-task-workday-list '("Monday" "Tuesday" "Wednesday" "Thursday" "Friday"))
         (org-plan-task-start-workday "09:00")
         (org-plan-task-end-workday "17:00")
         (org-plan-task-breaks nil)
         (org-agenda-files nil)
         (org-mode-hook nil)
         (org-inhibit-startup t)
         (org-log-done nil)
         (org-log-redeadline nil)
         (org-read-date-popup-calendar nil))
     (with-temp-buffer
       (org-mode)
       (insert ,text)
       (goto-char (point-min))
       ,@body)))

(defun org-plan-task-test--time (text)
  "Return local floating point time for ISO date and clock TEXT."
  (+ (float-time (org-time-string-to-time text))
     (if (string-match "[0-9][0-9]:[0-9][0-9]:\\([0-9][0-9]\\)" text)
         (string-to-number (match-string 1 text)) 0)))

(defun org-plan-task-test--span (start end)
  "Return an interval between ISO strings START and END."
  (cons (org-plan-task-test--time start) (org-plan-task-test--time end)))

(defun org-plan-task-test--events (text)
  "Parse conflict events from Org TEXT."
  (org-plan-task-test--task text (org-plan-task--buffer-events)))

(defmacro org-plan-task-test--answers (now choices &rest body)
  "Run BODY with time NOW, CHOICES and agenda refresh disabled."
  (declare (indent 2) (debug t))
  `(let ((answers ,choices)
         (instant (org-plan-task-test--time ,now)))
     (cl-letf (((symbol-function 'current-time) (lambda () instant))
               ((symbol-function 'org-plan-task--choose)
                (lambda (_span _remaining)
                  (or (pop answers) (error "Unexpected allocation prompt"))))
               ((symbol-function 'org-plan-task--refresh) #'ignore))
       ,@body)))

(ert-deftest org-plan-task-effort-rounding ()
  (dolist (case '(("0:01" 30) ("0:30" 30) ("75" 90) ("1:30" 90)
                  ("1h 15min" 90) ("0:30:01" 60)))
    (should (= (org-plan-task--allocation (car case)) (cadr case))))
  (should (= (org-plan-task--allocation "90" "75") 30))
  (should (= (org-plan-task--allocation "120" "75") 60))
  (dolist (value '(nil "" "0" "nonsense" "-1"))
    (should-error (org-plan-task--allocation value) :type 'user-error))
  (dolist (value '("75" "60"))
    (should-error (org-plan-task--allocation value "75") :type 'user-error)))

(ert-deftest org-plan-task-configuration-lists-and-vectors ()
  (org-plan-task-test--task "* Task\n"
    (setq org-plan-task-workday-list ["mOnDaY" "SUNDAY"]
          org-plan-task-breaks [["12:00" "13:00"] ["15:10" "15:20"]])
    (let ((config (org-plan-task--configuration)))
      (should (equal (plist-get config :days) '(1 0)))
      (should (= (length (org-plan-task--slot-minutes config)) 13))
      (should-not (memq 900 (org-plan-task--slot-minutes config)))
      (should (memq 930 (org-plan-task--slot-minutes config))))))

(ert-deftest org-plan-task-configuration-invalid ()
  (dolist (case '((org-plan-task-workday-list nil)
                  (org-plan-task-workday-list ("Mon"))
                  (org-plan-task-workday-list "Monday")
                  (org-plan-task-start-workday "9:00")
                  (org-plan-task-start-workday "24:00")
                  (org-plan-task-start-workday "18:00")
                  (org-plan-task-end-workday "09:00")
                  (org-plan-task-end-workday "09:20")
                  (org-plan-task-breaks (("08:30" "09:30")))
                  (org-plan-task-breaks (("16:30" "17:30")))
                  (org-plan-task-breaks (("12:00" "11:30")))
                  (org-plan-task-breaks (("12:00" "13:00") ("12:30" "14:00")))
                  (org-plan-task-breaks (("09:00" "17:00")))
                  (org-plan-task-breaks (("12:00")))))
    (org-plan-task-test--task "* Task\n"
      (set (car case) (cadr case))
      (should-error (org-plan-task--configuration) :type 'user-error))))

(ert-deftest org-plan-task-current-boundaries ()
  (org-plan-task-test--task "* Task\n"
    (let ((config (org-plan-task--configuration)))
      (dolist (case '(("08:59" "09:00") ("09:00" "09:00")
                      ("09:00:01" "09:30") ("09:20" "09:30")
                      ("09:30" "09:30")))
        (should (equal (format-time-string
                        "%H:%M" (caar (org-plan-task--day-slots
                                        '(10 5 2026) config
                                        (org-plan-task-test--time
                                         (concat "2026-10-05 " (car case))))))
                       (cadr case))))
      (should-not (org-plan-task--day-slots '(10 3 2026) config 0))
      (should-not (org-plan-task--day-slots
                   '(10 5 2026) config (org-plan-task-test--time "2026-10-05 16:31"))))))

(ert-deftest org-plan-task-irregular-workday-and-break-boundaries ()
  (org-plan-task-test--task "* Task\n"
    (setq org-plan-task-start-workday "09:10"
          org-plan-task-end-workday "11:10"
          org-plan-task-breaks '(("10:05" "10:10")))
    (should (equal (org-plan-task--slot-minutes (org-plan-task--configuration))
                   '(570 630)))))

(ert-deftest org-plan-task-calendar-rollovers ()
  (should (equal (org-plan-task--date-add '(12 31 2026) 1) '(1 1 2027)))
  (should (equal (org-plan-task--date-add '(2 28 2028) 1) '(2 29 2028)))
  (should (equal (org-plan-task--date-add '(2 28 2027) 1) '(3 1 2027))))

(ert-deftest org-plan-task-daylight-saving-calendar ()
  (let ((original (getenv "TZ")))
    (unwind-protect
        (progn
          (set-time-zone-rule "America/New_York")
          (org-plan-task-test--task "* Task\n"
            (setq org-plan-task-workday-list '("Sunday" "Monday"))
            (let ((config (org-plan-task--configuration)))
              (dolist (date '((3 8 2026) (11 1 2026)))
                (let ((slots (org-plan-task--day-slots date config 0)))
                  (should (= (length slots) 16))
                  (should (equal (format-time-string "%H:%M" (caar slots)) "09:00"))))
              (should (= (- (org-plan-task--at '(3 9 2026) 0)
                             (org-plan-task--at '(3 8 2026) 0)) 82800))
              (should (= (- (org-plan-task--at '(11 2 2026) 0)
                             (org-plan-task--at '(11 1 2026) 0)) 90000)))))
      (set-time-zone-rule original))))

(ert-deftest org-plan-task-conflicts-span-versus-reminder ()
  (let ((events
         (org-plan-task-test--events
          "* Appointments\nSCHEDULED: <2026-10-05 Mon 09:00-09:30> DEADLINE: <2026-10-05 Mon 10:00-10:30>\n<2026-10-05 Mon 11:00>\n<2026-10-05 Mon>\n<2026-10-05 Mon>--<2026-10-06 Tue>\n<2026-10-05 Mon 12:00>--<2026-10-06 Tue>\n[2026-10-05 Mon 13:00-14:00]\nCLOCK: [2026-10-05 Mon 14:00]--[2026-10-05 Mon 15:00] => 1:00\n<2026-10-05 Mon 16:00-16:30>\n")))
    (should (= (length events) 3))
    (should (= (length (apply #'append (mapcar
                                        (lambda (event)
                                          (org-plan-task--event-spans event '(10 5 2026)))
                                        events))) 3))))

(ert-deftest org-plan-task-overlap-and-touching ()
  (let ((block '(100 . 200)))
    (dolist (span '((50 . 101) (199 . 220) (110 . 150) (0 . 300)))
      (should (org-plan-task--overlap-p block span)))
    (dolist (span '((0 . 100) (200 . 300)))
      (should-not (org-plan-task--overlap-p block span)))))

(ert-deftest org-plan-task-cross-date-conflicts ()
  (let ((event (car (org-plan-task-test--events
                    "* Trip\n<2026-10-04 Sun 23:30>--<2026-10-05 Mon 09:15>\n"))))
    (should event)
    (should (= (length (org-plan-task--event-spans event '(10 4 2026))) 1))
    (should (= (length (org-plan-task--event-spans event '(10 5 2026))) 1))
    (should-not (org-plan-task--event-spans event '(10 6 2026)))))

(ert-deftest org-plan-task-recurring-events ()
  (dolist (case '(("<2026-10-05 Mon 09:00-09:30 +1d>" (10 6 2026) 1)
                  ("<2026-10-05 Mon 09:00-09:30 ++1w>" (10 12 2026) 1)
                  ("<2026-10-05 Mon 09:00-09:30 .+1w>" (10 13 2026) 0)
                  ("<2026-09-05 Sat 09:00-09:30 +1m>" (10 5 2026) 1)
                  ("<2025-10-05 Sun 09:00-09:30 +1y>" (10 5 2026) 1)
                  ("<2026-10-05 Mon 09:00-09:30 +2h>" (10 5 2026) 8)
                  ("<2026-10-05 Mon 09:00-09:30 +1d>" (10 4 2026) 0)))
    (let ((event (car (org-plan-task-test--events (concat "* Event\n" (car case) "\n")))))
      (should (= (length (org-plan-task--event-spans event (cadr case)))
                 (nth 2 case))))))

(ert-deftest org-plan-task-recurring-cross-date-and-dst ()
  (let ((original (getenv "TZ")))
    (unwind-protect
        (progn
          (set-time-zone-rule "America/New_York")
          (let ((event (car (org-plan-task-test--events
                            "* Night\n<2026-03-07 Sat 23:00 +1d>--<2026-03-08 Sun 09:15>\n"))))
            (should (= (length (org-plan-task--event-spans event '(3 9 2026))) 2))
            (should (equal (format-time-string
                            "%H:%M" (cdar (org-plan-task--event-spans event '(3 9 2026))))
                           "09:15"))))
      (set-time-zone-rule original))))

(ert-deftest org-plan-task-invocation-contexts ()
  (with-temp-buffer (should-error (org-plan-task) :type 'user-error))
  (org-plan-task-test--task "Intro\n* Parent\nBody\n** Child\n"
    (should-error (org-plan-task) :type 'user-error)
    (search-forward "Body")
    (let ((position (point)) (marker (org-plan-task--target)))
      (should (= (point) position))
      (should (= (marker-position marker) 7))
      (set-marker marker nil))))

(ert-deftest org-plan-task-agenda-context-and-stale-marker ()
  (org-plan-task-test--task "* Task\nBody\n"
    (let ((source (point-marker)))
      (unwind-protect
          (with-temp-buffer
            (org-agenda-mode)
            (insert "Task\n")
            (add-text-properties 1 5 (list 'org-hd-marker source))
            (goto-char 1)
            (should (equal (marker-position (org-plan-task--target)) 1))
            (set-marker source 9)
            (should-error (org-plan-task--target) :type 'user-error)
            (set-marker source nil)
            (should-error (org-plan-task--target) :type 'user-error))
        (set-marker source nil)))))

(ert-deftest org-plan-task-missing-properties-commit-and-placement ()
  (org-plan-task-test--task "* TODO Task\nBody text\n:NOTES:\nKeep me\n:END:\n** Child\n:PLAN:\n<2026-10-05 Mon 14:00-14:30>\n:END:\n"
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "75"))
              ((symbol-function 'org-read-date) (lambda (&rest _) "2026-10-05")))
      (org-plan-task-test--answers "2026-10-05 09:00" '(?a ?a ?a)
        (org-plan-task)))
    (should (equal (org-entry-get nil "EFFORT") "75"))
    (should (equal (org-entry-get nil "DEADLINE") "<2026-10-05 Mon>"))
    (should (string-match-p
             (regexp-quote ":END:\n:PLAN:\n<2026-10-05 Mon 09:00-10:30>\n:END:\nBody text")
             (buffer-string)))
    (should (string-match-p (regexp-quote ":NOTES:\nKeep me\n:END:\n** Child\n:PLAN:")
                            (buffer-string)))))

(ert-deftest org-plan-task-cancel-keeps-missing-properties ()
  (org-plan-task-test--task "* TODO Task\nBody\n"
    (let ((before (buffer-string)) (modified (buffer-modified-p)))
      (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "60"))
                ((symbol-function 'org-read-date) (lambda (&rest _) "2026-10-05")))
        (org-plan-task-test--answers "2026-10-05 09:00" '(?a ?q)
          (should-not (org-plan-task))))
      (should (equal before (buffer-string)))
      (should (eq modified (buffer-modified-p))))))

(ert-deftest org-plan-task-quit-keeps-task ()
  (org-plan-task-test--task "* TODO Task\n"
    (let ((before (buffer-string)) quit-seen)
      (cl-letf (((symbol-function 'read-string) (lambda (&rest _) (signal 'quit nil))))
        (condition-case nil (org-plan-task) (quit (setq quit-seen t))))
      (should quit-seen)
      (should (equal before (buffer-string))))))

(ert-deftest org-plan-task-extension-increase-rounding ()
  (org-plan-task-test--task "* TODO Task\nDEADLINE: <2026-10-05 Mon>\n:PROPERTIES:\n:EFFORT: 75\n:END:\n:PLAN:\n<2026-10-05 Mon 09:00-10:30>\n:END:\nBody\n"
    (cl-letf (((symbol-function 'read-string)
               (lambda (prompt &rest _)
                 (should (string-match-p "75" prompt)) "90")))
      (org-plan-task-test--answers "2026-10-05 09:00" '(?a)
        (org-plan-task)))
    (should (equal (org-entry-get nil "EFFORT") "90"))
    (should (equal (plist-get (org-plan-task--plan) :spans)
                   (list (org-plan-task-test--span "2026-10-05 09:00" "2026-10-05 11:00"))))))

(ert-deftest org-plan-task-extension-rejects-invalid-old-or-new ()
  (dolist (old '(nil "nonsense" "0" "75"))
    (org-plan-task-test--task "* Task\nDEADLINE: <2026-10-05 Mon>\n:PLAN:\n<2026-10-05 Mon 09:00-10:30>\n:END:\n"
      (when old (org-entry-put nil "EFFORT" old))
      (let ((before (buffer-string)))
        (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "75")))
          (should-error (org-plan-task) :type 'user-error))
        (should (equal before (buffer-string)))))))

(ert-deftest org-plan-task-plan-drawer-validation ()
  (dolist (text '(":PLAN:\n<2026-10-05 Mon 09:00-09:30>\n"
                  ":PLAN:\n:END:\n"
                  ":PLAN:\n<2026-10-05 Mon 09:00>\n:END:\n"
                  ":PLAN:\n<2026-10-05 Mon 09:00-09:30 +1d>\n:END:\n"
                  ":PLAN:\n<2026-10-05 Mon 09:00-09:30> extra\n:END:\n"
                  ":PLAN:\n<2026-10-05 Mon 10:00-09:00>\n:END:\n"
                  ":PLAN:\n<2026-02-30 Mon 09:00-10:00>\n:END:\n"
                  ":PLAN:\n<2026-10-05 Mon 25:00-26:00>\n:END:\n"
                  ":PLAN:\n<2026-10-05 Mon 09:00-10:00>\n#+begin_example\nUnexpected text\n#+end_example\n:END:\n"
                  ":PLAN:\n:OTHER:\n:END:\n:END:\n"
                  ":OTHER:\n:PLAN:\n:END:\n:END:\n"
                  ":PLAN:\n<2026-10-05 Mon 09:00-09:30>\n:END:\n:PLAN:\n<2026-10-05 Mon 10:00-10:30>\n:END:\n"))
    (org-plan-task-test--task (concat "* Task\n" text)
      (should-error (org-plan-task--plan) :type 'user-error))))

(ert-deftest org-plan-task-merge-preserves-gaps-and-dates ()
  (let ((spans (list (org-plan-task-test--span "2026-10-05 10:00" "2026-10-05 10:30")
                     (org-plan-task-test--span "2026-10-05 09:00" "2026-10-05 09:30")
                     (org-plan-task-test--span "2026-10-05 09:15" "2026-10-05 09:45")
                     (org-plan-task-test--span "2026-10-05 23:30" "2026-10-06 00:00")
                     (org-plan-task-test--span "2026-10-06 00:00" "2026-10-06 00:30"))))
    (should (= (length (org-plan-task--merge spans)) 4))
    (should (equal (car (org-plan-task--merge spans))
                   (org-plan-task-test--span "2026-10-05 09:00" "2026-10-05 09:45")))))

(ert-deftest org-plan-task-atomic-commit-failure ()
  (org-plan-task-test--task "* TODO Task\nBody\n"
    (set-buffer-modified-p nil)
    (let ((before (buffer-string)))
      (cl-letf (((symbol-function 'org-plan-task--format-span)
                 (lambda (_) (error "Injected write failure"))))
        (should-error (org-plan-task--commit
                       "30" "2026-10-05"
                       (list (org-plan-task-test--span "2026-10-05 09:00" "2026-10-05 09:30")))))
      (should (equal before (buffer-string)))
      (should-not (buffer-modified-p)))))

(ert-deftest org-plan-task-skip-next-day-and-weekend ()
  (org-plan-task-test--task "* Task\n"
    (org-plan-task-test--answers "2026-10-02 16:00" '(?s ?n ?a)
      (let ((spans (org-plan-task--collect 30 (org-plan-task--configuration) nil instant)))
        (should (equal (format-time-string "%F %H:%M" (caar spans))
                       "2026-10-05 09:00"))))))

(ert-deftest org-plan-task-deadlines-equality-and-overrun ()
  (org-plan-task-test--task "* Task\n"
    (let ((config (org-plan-task--configuration)))
      (should (= (org-plan-task--deadline-time "<2026-10-05 Mon>" config)
                 (org-plan-task-test--time "2026-10-05 17:00")))
      (should (= (org-plan-task--deadline-time "<2026-10-05 Mon 12:00>" config)
                 (org-plan-task-test--time "2026-10-05 12:00")))))
  (dolist (case '(("09:30" nil) ("09:29" t)))
    (org-plan-task-test--task
        (concat "* Task\nDEADLINE: <2026-10-05 Mon " (car case)
                ">\n:PROPERTIES:\n:EFFORT: 30\n:END:\n")
      (let (warnings)
        (cl-letf (((symbol-function 'display-warning)
                   (lambda (&rest args) (push args warnings))))
          (org-plan-task-test--answers "2026-10-05 09:00" '(?a) (org-plan-task)))
        (should (eq (not (null warnings)) (cadr case)))
        (should (string-match-p (car case) (org-entry-get nil "DEADLINE")))))))

(ert-deftest org-plan-task-preserves-point-and-narrowing ()
  (org-plan-task-test--task "* Task\nDEADLINE: <2026-10-05 Mon>\n:PROPERTIES:\n:EFFORT: 30\n:END:\nBody\n* Other\n"
    (search-forward "Body")
    (let ((position (point-marker)))
      (narrow-to-region 1 (org-plan-task--section-end))
      (let ((maximum (copy-marker (point-max))))
        (org-plan-task-test--answers "2026-10-05 09:00" '(?a) (org-plan-task))
        (should (= (point) position))
        (should (buffer-narrowed-p))
        (should (= (point-max) maximum))
        (set-marker maximum nil))
      (set-marker position nil))))

(ert-deftest org-plan-task-cross-file-unsaved-conflicts ()
  (let* ((directory (make-temp-file "org-plan-task-test-" t))
         (file (expand-file-name "appointments.org" directory)) buffer)
    (unwind-protect
        (progn
          (with-temp-file file (insert "* Meeting\n"))
          (setq buffer (find-file-noselect file))
          (with-current-buffer buffer
            (goto-char (point-max))
            (insert "<2026-10-05 Mon 09:10-09:40>\n"))
          (org-plan-task-test--task "* Task\n"
            (setq org-agenda-files (list directory))
            (org-plan-task-test--answers "2026-10-05 09:00" '(?a)
              (let ((spans (org-plan-task--collect
                            30 (org-plan-task--configuration)
                            (org-plan-task--events (current-buffer)) instant)))
                (should (equal (format-time-string "%H:%M" (caar spans)) "10:00")))))
          (with-temp-buffer
            (insert-file-contents file)
            (should-not (search-forward "09:10" nil t))))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer))
      (delete-directory directory t))))

(ert-deftest org-plan-task-unreadable-sources-not-skipped ()
  (org-plan-task-test--task "* Task\n"
    (let ((org-agenda-skip-unavailable-files t))
      (setq org-agenda-files '("/nonexistent/org-plan-task-missing.org"))
      (should-error (org-plan-task--events (current-buffer)) :type 'user-error))))

(ert-deftest org-plan-task-current-plan-conflicts-outside-agenda ()
  (org-plan-task-test--task "* Task\n:PLAN:\n<2026-10-05 Mon 09:00-10:30>\n:END:\n"
    (should (= (length (org-plan-task--events (current-buffer))) 1))))

(ert-deftest org-plan-task-drawer-examples-are-body-text ()
  (dolist (type '("example" "src org" "export html" "comment"))
    (org-plan-task-test--task
        (format "* Task\n#+begin_%s\n:PLAN:\nAn example, not an allocation\n:END:\n#+end_%s\n"
                type (car (split-string type)))
      (should-not (org-plan-task--plan))
      (let ((body (buffer-substring-no-properties (line-end-position) (point-max))))
        (org-plan-task--commit
         "30" nil (list (org-plan-task-test--span "2026-10-05 09:00" "2026-10-05 09:30")))
        (should (org-plan-task--plan))
        (should (string-suffix-p body (buffer-string)))))))

(ert-deftest org-plan-task-allocation-year-rollover ()
  (org-plan-task-test--task "* Task\n"
    (org-plan-task-test--answers "2026-12-31 16:30" '(?a ?a)
      (let ((spans (org-plan-task--merge
                    (org-plan-task--collect 60 (org-plan-task--configuration) nil instant))))
        (should (equal (mapcar (lambda (span) (format-time-string "%F %H:%M" (car span))) spans)
                       '("2026-12-31 16:30" "2027-01-01 09:00")))))))

(ert-deftest org-plan-task-cancel-and-rollback-existing-plan ()
  (org-plan-task-test--task "* Task\nDEADLINE: <2026-10-05 Mon>\n:PROPERTIES:\n:EFFORT: 30\n:END:\n:PLAN:\n<2026-10-05 Mon 09:00-09:30>\n:END:\nBody\n** Child\nKeep\n"
    (let ((before (buffer-string)))
      (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "60")))
        (org-plan-task-test--answers "2026-10-05 09:00" '(?q)
          (should-not (org-plan-task))))
      (should (equal before (buffer-string)))
      (cl-letf (((symbol-function 'org-plan-task--format-span)
                 (lambda (_) (error "Failed after old drawer removal"))))
        (should-error (org-plan-task--commit
                       "60" nil
                       (list (org-plan-task-test--span "2026-10-05 09:00" "2026-10-05 10:00")))))
      (should (equal before (buffer-string))))))

(ert-deftest org-plan-task-conflict-search-interruptible ()
  (org-plan-task-test--task "* Task\nDEADLINE: <2026-10-05 Mon>\n:PROPERTIES:\n:EFFORT: 30\n:END:\n<2026-10-05 Mon 09:00-17:00 +1d>\n"
    (let ((before (buffer-string)) (calls 0) quit-seen
          (expand (symbol-function 'org-plan-task--event-spans)))
      (org-plan-task-test--answers "2026-10-05 09:00" nil
        (cl-letf (((symbol-function 'org-plan-task--event-spans)
                   (lambda (event date)
                     (cl-incf calls)
                     (when (= calls 5) (signal 'quit nil))
                     (funcall expand event date))))
          (condition-case nil (org-plan-task) (quit (setq quit-seen t)))))
      (should quit-seen)
      (should (= calls 5))
      (should (equal before (buffer-string))))))

(ert-deftest org-plan-task-own-effort-and-buffer-changes ()
  (org-plan-task-test--task "* Parent\n:PROPERTIES:\n:EFFORT: 10:00\n:END:\n** Task\nDEADLINE: <2026-10-05 Mon>\nBody\n"
    (search-forward "** Task")
    (let ((org-use-property-inheritance t) prompted)
      (cl-letf (((symbol-function 'read-string)
                 (lambda (&rest _) (setq prompted t) "30")))
        (org-plan-task-test--answers "2026-10-05 09:00" '(?a) (org-plan-task)))
      (should prompted)
      (should (equal (org-entry-get nil "EFFORT") "30")))
    (let ((before (buffer-string)))
      (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "60"))
                ((symbol-function 'org-plan-task--choose)
                 (lambda (&rest _) (save-excursion (goto-char (point-max)) (insert "User edit\n")) ?a)))
        (should-error (org-plan-task) :type 'user-error))
      (should (equal (buffer-string) (concat before "User edit\n")))
      (should (equal (org-entry-get nil "EFFORT") "30")))))

(ert-deftest org-plan-task-agenda-refresh-failure-retains-plan ()
  (let ((agenda (generate-new-buffer " *org-plan-task-test-agenda*")))
    (unwind-protect
        (progn
          (with-current-buffer agenda (org-agenda-mode))
          (org-plan-task-test--task "* Task\nDEADLINE: <2026-10-05 Mon>\n:PROPERTIES:\n:EFFORT: 30\n:END:\n"
            (let ((instant (org-plan-task-test--time "2026-10-05 09:00")) warnings)
              (cl-letf (((symbol-function 'current-time) (lambda () instant))
                        ((symbol-function 'org-plan-task--choose) (lambda (&rest _) ?a))
                        ((symbol-function 'org-agenda-redo) (lambda (&rest _) (error "Refresh failed")))
                        ((symbol-function 'display-warning) (lambda (&rest args) (push args warnings))))
                (org-plan-task))
              (should (org-plan-task--plan))
              (should (seq-some (lambda (warning) (string-match-p "refresh failed" (cadr warning)))
                                warnings)))))
      (kill-buffer agenda))))

(ert-deftest org-plan-task-generated-timestamps-visible-in-agenda ()
  (let* ((directory (make-temp-file "org-plan-task-agenda-" t))
         (file (expand-file-name "tasks.org" directory)) source agenda)
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* TODO Planned task\nDEADLINE: <2026-10-05 Mon>\n:PROPERTIES:\n:EFFORT: 30\n:END:\n"))
          (setq source (find-file-noselect file))
          (with-current-buffer source
            (goto-char (point-min))
            (org-plan-task--commit
             "30" nil (list (org-plan-task-test--span "2026-10-05 09:00" "2026-10-05 09:30"))))
          (let ((org-agenda-files (list file))
                (org-agenda-window-setup 'current-window)
                (org-agenda-buffer-name "*org-plan-task-agenda-test*")
                (org-agenda-span 1)
                (org-agenda-start-day "2026-10-05"))
            (save-window-excursion
              (org-agenda-list nil "2026-10-05" 1)
              (setq agenda (current-buffer))
              (goto-char (point-min))
              (should (re-search-forward "9:00.*Planned task" nil t))
              ;; Invoke the real public command through this agenda marker.
              (narrow-to-region (line-beginning-position) (1+ (line-end-position)))
              (let ((position (point)) (minimum (point-min)) (maximum (point-max)))
                (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "60"))
                          ((symbol-function 'org-plan-task--choose) (lambda (&rest _) ?a))
                          ((symbol-function 'current-time)
                           (lambda () (org-plan-task-test--time "2026-10-05 09:00"))))
                  (org-plan-task))
                (should (= (point) position))
                (should (= (point-min) minimum))
                (should (= (point-max) maximum)))
              (with-current-buffer source
                (goto-char 1)
                (should (equal (org-entry-get nil "EFFORT") "60"))))))
      (when (buffer-live-p agenda) (kill-buffer agenda))
      (when (buffer-live-p source)
        (with-current-buffer source (set-buffer-modified-p nil))
        (kill-buffer source))
      (delete-directory directory t))))

(provide 'org-plan-task-test)
;;; org-plan-task-test.el ends here
