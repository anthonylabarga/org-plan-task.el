# Repository guidance

## Package overview

- This repository contains the `org-plan-task` Emacs package.
- `org-plan-task.el` is the public entry point.
- Implementation modules live in `lisp/`.
- ERT tests live in `test/`.
- Files under `docs/generated/` are generated; do not edit them directly.

## Compatibility

- Support Emacs 29 and newer.
- Runtime dependencies must be declared in the package header and must
  be available from GNU ELPA or NonGNU ELPA.

## Emacs Lisp conventions

- Keep `lexical-binding: t` in every Elisp source file.
- Add `;;;###autoload` only to intended user entry points.
- Public functions and variables require docstrings.
- Preserve existing public function signatures unless the task explicitly
  authorizes a breaking change.

## Testing

Run the complete check suite with:

    make check

For a targeted ERT run:

    emacs -Q --batch \
      -L . -L test \
      -l test/org-plan-task-test.el \
      --eval '(ert-run-tests-batch-and-exit "example-")'

After modifying Elisp:

- Run ERT tests.
- Byte-compile with warnings enabled.
- Run `package-lint` and `checkdoc`.
- Treat new byte-compiler warnings as failures.

## Documentation

- Update `README.org` when user-visible behavior changes.
- Update `NEWS.org` for new commands, options, or compatibility changes.
- Examples in documentation must work under `emacs -Q`.
