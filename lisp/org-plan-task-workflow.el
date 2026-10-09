;;; org-plan-task-workflow.el --- Interactive allocation workflow -*- lexical-binding: t; -*-

;; Copyright (C) 2026 John Anthony Labarga
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Collect choices in memory, then commit the whole plan to its source.

;;; Code:

(require 'org-plan-task-org)

(defun org-plan-task--choose (span remaining)
  "Ask how to handle candidate SPAN with REMAINING minutes to allocate."
  (read-char-choice
   (format "%s (%d min remaining): [a]ssign [s]kip [n]ext workday [q]cancel "
           (org-plan-task--format-span span) remaining)
   '(?a ?s ?n ?q)))

(defun org-plan-task--collect (minutes config events now)
  "Collect MINUTES of blocks under CONFIG, avoiding EVENTS from NOW.
Return chosen spans, or nil on cancellation.  Searching remains
interruptible even when all work blocks conflict indefinitely."
  (catch 'org-plan-task--cancel
    (let ((date (org-plan-task--date now)) chosen)
      (while (> minutes 0)
        (when quit-flag (keyboard-quit))
        (let ((conflicts (apply #'append
                                (mapcar (lambda (event)
                                          (org-plan-task--event-spans event date))
                                        events))))
          (catch 'org-plan-task--next-day
            (dolist (span (org-plan-task--day-slots date config now))
              (when quit-flag (keyboard-quit))
              (unless (seq-some (lambda (conflict)
                                  (org-plan-task--overlap-p span conflict))
                                conflicts)
                (pcase (org-plan-task--choose span minutes)
                  (?a (push span chosen) (setq minutes (- minutes 30)))
                  (?s nil)
                  (?n (throw 'org-plan-task--next-day nil))
                  (?q (throw 'org-plan-task--cancel nil)))
                (when (= minutes 0) (throw 'org-plan-task--next-day nil))))))
        (setq date (org-plan-task--date-add date 1)))
      (nreverse chosen))))

(defun org-plan-task--preserve-agenda-position (function)
  "Call FUNCTION preserving point and narrowing in the calling agenda.
Agenda regeneration replaces the text, so retain numeric positions rather
than markers.  Clamp positions when a rebuilt agenda becomes shorter."
  (if (not (derived-mode-p 'org-agenda-mode))
      (funcall function)
    (let ((buffer (current-buffer))
          (position (point)) (minimum (point-min)) (maximum (point-max))
          (narrowed (buffer-narrowed-p)))
      (unwind-protect
          (funcall function)
        (when (buffer-live-p buffer)
          (with-current-buffer buffer
            (widen)
            (when narrowed
              (narrow-to-region (min minimum (point-max))
                                (min maximum (point-max))))
            (goto-char (min (point-max) (max (point-min) position)))))))))

(defun org-plan-task--refresh ()
  "Refresh live agendas and return a list of reported refresh failures."
  (let (failures)
    (dolist (buffer (buffer-list))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (when (derived-mode-p 'org-agenda-mode)
            (condition-case err
                (org-plan-task--preserve-agenda-position
                 (lambda () (widen) (org-agenda-redo t)))
              ((error quit)
               (let ((problem (format "Agenda refresh failed for %s: %s"
                                      (buffer-name buffer) (error-message-string err))))
                 (push problem failures)
                 (display-warning 'org-plan-task
                                  (concat "Plan committed; " problem) :warning))))))))
    (nreverse failures)))

(defun org-plan-task--run ()
  "Plan the task while preserving the calling agenda's position."
  (org-plan-task--preserve-agenda-position #'org-plan-task--run-at-target))

(defun org-plan-task--run-at-target ()
  "Resolve the task, collect allocation choices, and commit a complete plan."
  (let ((target (org-plan-task--target))
        (config (org-plan-task--configuration)))
    (unwind-protect
        (save-window-excursion
          (with-current-buffer (marker-buffer target)
            (save-excursion
              (save-restriction
                (widen)
                (goto-char target)
                (barf-if-buffer-read-only)
                (let* ((tick (buffer-chars-modified-tick))
                       (plan (org-plan-task--plan))
                       (old (org-entry-get nil "EFFORT"))
                       (deadline (org-entry-get nil "DEADLINE"))
                       (effort
                        (cond
                         (plan
                          (unless old (user-error "Existing PLAN requires an old effort estimate"))
                          (org-plan-task--minutes old)
                          (read-string (format "Old effort %s; larger estimate: " old)))
                         (old old)
                         (t (read-string "Effort (Org duration, e.g. 1:30): "))))
                       (minutes (org-plan-task--allocation effort (and plan old)))
                       (new-deadline (unless deadline
                                       (org-read-date nil nil nil "Task deadline: ")))
                       (due (org-plan-task--deadline-time (or deadline new-deadline) config))
                       (events (org-plan-task--events (current-buffer)))
                       (chosen (org-plan-task--collect minutes config events
                                                       (float-time (current-time)))))
                  (if (not chosen)
                      (progn (message "Planning canceled; task unchanged") nil)
                    (unless (and (marker-buffer target)
                                 (= tick (buffer-chars-modified-tick)))
                      (user-error "Task buffer changed during planning; please try again"))
                    (goto-char target)
                    (let* ((spans (org-plan-task--merge
                                   (append (plist-get plan :spans) chosen)))
                           (finish (apply #'max (mapcar #'cdr spans))))
                      (org-plan-task--commit effort new-deadline spans)
                      (when (> finish due)
                        (display-warning
                         'org-plan-task
                         "Plan finishes after the deadline; consider adjusting the deadline"
                         :warning))
                      (let ((failures (org-plan-task--refresh)))
                        (message "Task planned%s%s; save the Org file when ready"
                                 (if (> finish due)
                                     " after the deadline; consider adjusting it" "")
                                 (if failures
                                     (concat "; " (mapconcat #'identity failures "; ")) "")))
                      spans)))))))
      (set-marker target nil))))

(provide 'org-plan-task-workflow)
;;; org-plan-task-workflow.el ends here
