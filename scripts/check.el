;;; check.el --- Fail on lint and documentation issues -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Run from the repository root with isolated dependencies installed.

;;; Code:

(require 'package)
(require 'checkdoc)

(setq package-user-dir (expand-file-name ".deps/elpa" default-directory))
(package-initialize)
(unless (require 'package-lint nil t)
  (error "Missing package-lint; run make deps"))
(let ((failed nil))
  (dolist (file '("org-plan-task.el" "lisp/org-plan-task-time.el"
                  "lisp/org-plan-task-org.el" "lisp/org-plan-task-workflow.el"))
    (with-current-buffer (find-file-noselect file)
      (when (equal file "org-plan-task.el")
        (dolist (issue (package-lint-buffer))
          (message "%s: %S" file issue)
          (setq failed t)))
      (let ((checkdoc-create-error-function
             (lambda (text &rest _args)
               (message "%s: %s" file text)
               (setq failed t))))
        (checkdoc-current-buffer t))))
  (when failed (error "Lint or checkdoc failed")))

;;; check.el ends here
