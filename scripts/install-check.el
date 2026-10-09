;;; install-check.el --- Verify installation without source paths -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Start in emacs -Q without checkout load paths and install the tarball.

;;; Code:

(require 'package)
(let ((directory (make-temp-file "org-plan-task-install-" t))
      (artifact (with-temp-buffer
                  (insert-file-contents ".build-artifact")
                  (string-trim (buffer-string)))))
  (unwind-protect
      (progn
        (setq package-user-dir directory
              package-archives nil
              byte-compile-error-on-warn t
              byte-compile-warnings t)
        (package-initialize)
        (package-install-file artifact)
        (unless (autoloadp (symbol-function 'org-plan-task))
          (error "The installed command is not autoloaded"))
        (unless (commandp 'org-plan-task) (error "Missing interactive command"))
        (require 'org-plan-task)
        (dolist (feature '(org-plan-task-time org-plan-task-org org-plan-task-workflow))
          (unless (featurep feature) (error "Missing packaged module: %s" feature)))
        (with-temp-buffer
          (org-mode)
          (insert "* TODO Installed task\n")
          (goto-char (point-min))
          (org-plan-task--commit
           "0:30" "2026-10-05"
           (list (cons (org-plan-task--at '(10 5 2026) 540)
                       (org-plan-task--at '(10 5 2026) 570))))
          (unless (search-backward ":PLAN:" nil t)
            (error "Installed package cannot create a plan")))
        (message "Clean installation and autoload check passed"))
    (delete-directory directory t)))

;;; install-check.el ends here
