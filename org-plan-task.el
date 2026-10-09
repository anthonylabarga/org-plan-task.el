;;; org-plan-task.el --- Interactive time blocks for Org tasks -*- lexical-binding: t; -*-

;; Copyright (C) 2026 John Anthony Labarga
;; Author: John Anthony Labarga <anthony@anthonylabarga.us>
;; Maintainer: John Anthony Labarga <anthony@anthonylabarga.us>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (org "9.6"))
;; Keywords: outlines, calendar
;; URL: https://github.com/anthonylabarga/org-plan-task.el
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Use M-x org-plan-task on an Org heading or an agenda entry to allocate
;; available half-hour blocks.  Customize the workweek, working hours,
;; and breaks in the org-plan-task group.  Plans are active timestamps
;; in a PLAN drawer; effort and deadline edits are committed only when
;; all blocks have been chosen.  Files are never saved automatically.
;; Implementation developed with AI assistance from OpenAI Codex.

;;; Code:

(declare-function org-plan-task--run "org-plan-task-workflow")

;; Source checkouts keep modules in lisp/.  Package builds flatten them.
(let ((load-path (cons (expand-file-name
                       "lisp" (file-name-directory
                               (or load-file-name buffer-file-name)))
                      load-path)))
  (require 'org-plan-task-workflow))

;;;###autoload
(defun org-plan-task ()
  "Interactively allocate half-hour blocks to the Org task at point.
Also accept agenda entries with a live source marker.  Existing plans
are extended by rounding the increase in effort up to half an hour.
Cancel with q or \\[keyboard-quit] without changing the task.  Successful plans update
the task atomically and refresh existing agenda buffers."
  (interactive)
  (org-plan-task--run))

(provide 'org-plan-task)
;;; org-plan-task.el ends here
