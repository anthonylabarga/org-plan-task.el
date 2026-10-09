;;; dependencies.el --- Isolated development dependencies -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Install check dependencies into the checkout, never the user's ELPA.

;;; Code:

(require 'package)

(setq package-user-dir (expand-file-name ".deps/elpa" default-directory)
      package-archives '(("gnu" . "https://elpa.gnu.org/packages/")
                         ("nongnu" . "https://elpa.nongnu.org/nongnu/")
                         ("melpa" . "https://melpa.org/packages/")))
(package-initialize)
(let ((missing (seq-filter (lambda (name) (not (package-installed-p name)))
                           '(package-lint package-build))))
  (when missing
    (package-refresh-contents)
    (dolist (name missing) (package-install name))))
(require 'package-lint)
(require 'package-build)

;;; dependencies.el ends here
