# Implementation plan for `org-plan-task`

## Summary

Implement the README's interactive time-block planner for Emacs 29 and newer, incorporating the decisions from this conversation:

- Allocate complete half-hour blocks starting at `:00` or `:30`.
- Reserve time only for explicit timed spans; point timestamps and date-only reminders do not block planning.
- Extend an existing plan by rounding the **increase in effort** up independently.
- Interpret date-only deadlines as the configured workday end.
- Preserve the task unchanged if planning is canceled.

The repository currently contains the specification and guidance but no package implementation or test suite.

## Public interface and structure

- Provide the autoloaded command `(org-plan-task)` in `org-plan-task.el`. Accept invocation within an Org heading or on an agenda entry associated with one. Report a clear error for unsupported contexts or stale agenda entries.
- Keep implementation modules under `lisp/`, separating time calculations, Org data access, and the interactive workflow. Keep ERT tests under `test/`.
- Define a customization group and the four options specified in the README:
  - `org-plan-task-workday-list`: Monday through Friday by default.
  - `org-plan-task-start-workday`: `"09:00"`.
  - `org-plan-task-end-workday`: `"17:00"`.
  - `org-plan-task-breaks`: no breaks by default.
- Document Lisp lists for weekdays and break pairs; also accept vectors as the README describes arrays. Weekday names are full English names, matched without regard to case.
- Support same-day work hours initially. Validate clock strings, increasing boundaries, nonempty valid weekdays, and nonoverlapping breaks entirely within the workday. Reject configurations with no complete half-hour block available.
- Use Emacs and Org facilities without external runtime dependencies. Declare the minimum Emacs and Org versions in the package header. Preserve lexical binding, document public symbols, and autoload only the user command.

## Scheduling and conflict detection

- Read the task's own effort using Org's duration conventions. Require a positive duration. Prompt when effort or deadline is missing, retaining answers in memory until planning succeeds.
- For a new plan, allocate `30 × ceiling(effort / 30)` minutes.
- For an existing plan, display the old effort and require a strictly larger estimate. Allocate `30 × ceiling((new − old) / 30)` additional minutes. Thus, increasing effort from 75 to 90 minutes adds 30 minutes, regardless of previous rounding.
- Begin at the first half-hour boundary at or after the current instant. Offer only blocks entirely within a configured workday. Skip nonworking days and blocks overlapping breaks.
- Resolve all registered agenda files and inspect their live buffers so unsaved appointments count. Include the current task's existing allocations even if its file is not an agenda file. Report unreadable conflict sources rather than silently ignoring them.
- Parse active explicit timed ranges, including ranges crossing dates and timed ranges in scheduled/deadline metadata. Ignore inactive timestamps, clock logs, point timestamps, and ranges containing dates without explicit times.
- Use Org's parsing and recurrence facilities compatible with Emacs 29. Support ordinary hourly, daily, weekly, monthly, and yearly repeating timed spans. Diary expressions are outside the initial implementation.
- Explicitly distinguish spans from points: Org's parser can populate end-time fields even for point timestamps.
- Treat intervals as including their start and excluding their end. Any positive overlap makes a block unavailable; touching endpoints is allowed.
- Advance workdays using local calendar dates, handling month/year changes and daylight-saving transitions without assuming every day lasts 24 hours.
- Prompt with the candidate date, start/end time, and remaining allocation. Offer assign, skip block, next workday, and cancel. Keep searching interruptible with `C-g`, including when conflicts prevent offers.

## Task updates and agenda integration

- Resolve agenda entries to their source heading and preserve the caller's point and narrowing.
- Locate `PLAN` only within the heading's own section. Preserve child headings, unrelated drawers, and body text. Reject duplicate or malformed plan drawers and existing plans without a usable old effort estimate.
- Retain previous allocations when extending. Merge adjacent or overlapping plan spans on the same date, preserving gaps and date boundaries.
- Write active timestamp ranges inside one `:PLAN:` drawer, after planning metadata and any property drawer, before body text.
- Commit effort, any newly entered deadline, and the complete plan atomically after all allocation prompts finish. Cancellation or a commit failure must leave the original task intact.
- Leave normal file saving to the user.
- Warn when the completed plan ends after the deadline; finishing exactly at the deadline is allowed. Preserve the deadline rather than adjusting it automatically.
- Refresh existing agenda buffers after a successful update. If refresh fails, retain the committed plan and report the refresh problem separately.

## Verification, documentation, and packaging

Build `make check` to run ERT, byte compilation with warnings treated as failures, `package-lint`, and `checkdoc`. Provide isolated development-dependency setup; missing checks must fail explicitly rather than be skipped. The prescribed targeted ERT command must also work with the implementation modules.

Cover these scenarios:

- Invocation from Org and agenda, missing properties, invalid context, and stale markers.
- Effort rounding; extension rounding including 75 → 90; rejection of equal or smaller estimates.
- Current time on and between boundaries, seconds after a boundary, weekends, next-workday selection, irregular break boundaries, and invalid configurations.
- Cross-file conflicts, unsaved edits, reminders that reserve no time, partial overlaps, endpoint adjacency, recurring events, and spans crossing dates.
- Month/year rollover and daylight-saving transitions using controlled times and time zones.
- Drawer placement, merging, preservation of body/subtasks, malformed plans, cancellation, and atomic rollback.
- Deadline equality/overrun, agenda refresh, and actual visibility of generated plan timestamps under `emacs -Q`.
- Installation and loading from the packaged artifact, including implementation modules and command autoloads.

Run CI on Emacs 29.1 and the current stable Emacs release. Local Emacs 30.1 and 31.1 are available for additional checks; minimum-version execution belongs in CI.

Keep the existing Markdown README current. Add an Org-format usage guide to satisfy the `README.org` instruction, and add `NEWS.org` for the initial command and options. Document configuration, reminders versus reserved spans, extension rounding, cancellation, and source-checkout installation with examples that work under `emacs -Q`. Do not edit generated documentation.

Prepare MELPA-compatible metadata and a recipe pointing to the existing GitHub repository, including the implementation modules. Default to GPL-3.0-or-later, use the configured author identity, and include the requested AI-assistance attribution. Verify recipe building and clean installation. Publishing, submitting a MELPA pull request, and creating releases remain separate actions.
