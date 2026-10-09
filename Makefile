EMACS ?= emacs
ELISP = org-plan-task.el lisp/org-plan-task-time.el lisp/org-plan-task-org.el lisp/org-plan-task-workflow.el
BATCH = $(EMACS) -Q --batch -L . -L lisp -L test

.NOTPARALLEL:

.PHONY: check test compile lint deps package package-check clean

check: clean
	$(MAKE) test compile lint package-check

test:
	$(BATCH) -l test/org-plan-task-test.el -f ert-run-tests-batch-and-exit

compile:
	$(BATCH) --eval '(setq byte-compile-error-on-warn t byte-compile-warnings t)' -f batch-byte-compile $(ELISP)

lint:
	$(BATCH) -l scripts/check.el

deps:
	$(BATCH) -l scripts/dependencies.el

package:
	$(BATCH) -l scripts/build.el

package-check: package
	$(EMACS) -Q --batch -l scripts/install-check.el

clean:
	rm -f org-plan-task.elc lisp/*.elc
