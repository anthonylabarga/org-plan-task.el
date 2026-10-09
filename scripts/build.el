;;; build.el --- Build a local MELPA recipe artifact -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Validate the real recipe and package the current checkout, including
;; uncommitted work, with MELPA's builder.  Never fetch or clean this tree.

;;; Code:

(require 'package)
(setq package-user-dir (expand-file-name ".deps/elpa" default-directory))
(package-initialize)
(unless (require 'package-build nil t)
  (error "Missing package-build; run make deps"))
(setq package-build-recipes-dir (expand-file-name "recipes" default-directory)
      package-build-archive-dir (expand-file-name "dist" default-directory)
      package-build-tar-executable (or (executable-find "gtar")
                                      (executable-find "tar")))
(make-directory package-build-archive-dir t)
(let* ((recipe (package-recipe-lookup "org-plan-task"))
       (files (package-build-expand-files-spec recipe t default-directory))
       (version (with-temp-buffer
                  (insert-file-contents "org-plan-task.el")
                  (lm-header "version"))))
  (unless (= (length (seq-filter (lambda (file)
                                  (string-suffix-p ".el" (car file))) files)) 4)
    (error "Recipe must include the public entry point and all three modules"))
  (oset recipe version version)
  (oset recipe time (truncate (float-time)))
  (package-build--build-package recipe files)
  (let ((tar (expand-file-name (format "org-plan-task-%s.tar" version)
                               package-build-archive-dir)))
    (unless (file-exists-p tar) (error "Package builder did not create %s" tar))
    (with-temp-file ".build-artifact" (insert tar "\n"))))

;;; build.el ends here
