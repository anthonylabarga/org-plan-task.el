# org-plan-task

`org-plan-task` is an Emacs package that makes it easy to assign time
blocks to org mode tasks.

The overall time management philosophy implemented in this package
reflects the one described in Cal Newport's book /The Time Block
Planner/. It also integrates ideas from pomodoro planning more
generally. This package is fairly opinionated, and assumes that you
work in the following way:

- Some continuous block of the twenty four hours in the day comprises
  your "workday"
  
- You take a routine set of breaks each day

- The workday is otherwise divided into thirty minute blocks

- Every thirty minute block during the workday is assigned to
  meetings, tasks, or breaks

- You track tasks using Emacs `org-mode`

- You can generally estimate how long a task will take

- You prefer to work on a task until it is complete, rather than cycle
  between tasks


I built this package to combine some functions I developed over the
years to improve my time management. I hope it is useful.


## Features

`org-plan-task` can be invoked while the cursor is on any `org-mode`
task, either in an `org` file or in the `org-agenda`. Invoking it
triggers the following sequence:

1. If no `effort` property is set, the user is asked to enter an
effort amount. This is an estimate of the amount of time that it will
take to complete the task. `org-plan-task` needs an effort estimate to
know how much time to allot to the task. Ideally the effort amount
would be a multiple of thirty minutes. If this is not the case, then
the lowest multiple of thirty minutes that exceeds the effort amount
will be assigned (e.g. if the effort was set to 75 minutes, then 90
minutes of timestamps will be assigned).

2. If no org-deadline is set for the task, then the user is prompted
for a deadline, for the same reason. Deadlines may be either dates or
times; in the case of a deadline being a date, this is interpreted as
"this task must be done before the close of the workday on that date".

3. Starting at the first half-hour boundary at or after the current instant,
`org-plan-task` iterates through
half-hour blocks docked to the hour (i.e. every block starts at XX:00
or XX:30). These blocks span the user's workday, exclusive of breaks,
meetings, or time already reserved by an active timestamp with an explicit
timed range. Point timestamps and date-only reminders reserve no time. All
registered `org-agenda` files are checked, including unsaved edits. The
user is asked whether to assign each half-hour block to the current
task or not. The user is also given the option to skip to the next
workday. This continues until the timestamps assigned to the task
total to the estimated effort. If any of the timestamps form
continuous blocks, those blocks are combined before saving.

4. If the assigned timestamps run until past the task's deadline, the
user receives a warning that suggests adjusting the task's deadline.

5. The assigned timestamps are inserted into the task's body under a
:PLAN: drawer. This is inserted beneath planning metadata and the property
drawer, above
any body text for the task.

6. The `org-agenda` is reloaded so that the user can see the assigned
time block on their agenda.

## Design Decisions

The following opinions are baked into the package:

- Time blocks are allocated thirty minutes at a time.

- Timestamps are docked to :00 or :30.

- If you run org-plan-task on a task that already has a :PLAN:, the
  package interprets this as "this task is taking longer than I
  thought". So, the user is shown the current effort estimate, and is
  prompted to enter a new effort estimate. This new effort estimate
  *must* exceed the old one, and an error will be shown if that is not
  the case. `org-plan-task` will then assign enough timestamps to
cover the increment in the effort estimate, rounded up independently.
For example, increasing the effort from 75 to 90 minutes adds another
30 minutes to the existing 90-minute plan.

All choices are kept in memory until allocation finishes. Cancel with `q`
or `C-g` to leave the task unchanged, including newly entered effort and
deadline answers. Successful updates are atomic; save the file yourself.
The deadline is preserved even if the plan overruns it. Finishing exactly
at the deadline is allowed.

## Configuration

The following package-specific variables are set to form a
configuration for the package:

- org-plan-task-workday-list: a list or vector of strings listing the days of the week that
  comprise your work week.

- org-plan-task-start-workday: a string containing a timestamp in twenty four hour
  format that indicates when your workday starts.

- org-plan-task-end-workday: a string containing a timestamp in twenty four hour
  format that indicates when your workday ends.

- org-plan-task-breaks: a list or vector of pairs of strings of twenty four hour
  timestamps. The first timestamp in the pair is when work stops for a
  break, and the second is when it resumes. A lunch break can be one
  of these breaks. The breaks must be non-overlapping; an error will
  occur otherwise. An error will occur if breaks extend past either
  end of the workday.

Defaults are Monday through Friday, 09:00–17:00, with no breaks. Weekdays
use full English names, ignoring case. Clocks must be `HH:MM`, and working
hours must start and end on the same day. A configuration must leave at
least one complete half-hour block.

```elisp
(require 'org-plan-task)
(setq org-plan-task-workday-list '("Monday" "Tuesday" "Wednesday" "Thursday" "Friday")
      org-plan-task-start-workday "09:00"
      org-plan-task-end-workday "17:00"
      org-plan-task-breaks '(("12:00" "13:00") ("15:00" "15:15")))
```

## Installation and use

Requires Emacs 29.1 or newer and Org 9.6 or newer. There are no external
runtime dependencies. For a source checkout, start `emacs -Q` and evaluate
the following, replacing the path with your checkout location:

```elisp
(add-to-list 'load-path "/path/to/org-plan-task")
(require 'org-plan-task)
```

Open an Org file and run `M-x org-plan-task` within a heading, or on its
agenda entry. Missing effort and deadline values are prompted for. Choose
`a` to assign a block, `s` to skip it, `n` to move to the next workday, or
`q` to cancel. Searching can always be interrupted with `C-g`.

An example task before planning:

```org
* TODO Write proposal
DEADLINE: <2026-10-05 Mon>
:PROPERTIES:
:EFFORT: 1:00
:END:
Notes about the proposal.
```

Choosing two consecutive blocks creates one active range in a `:PLAN:`
drawer above the notes, such as `<2026-10-05 Mon 09:00-10:00>`.

Active timed ranges in task bodies, drawers, scheduled metadata, and
deadline metadata reserve time. This includes ranges spanning dates and
ordinary hourly, daily, weekly, monthly, and yearly repeaters. Inactive
timestamps, clock logs, points, and ranges missing explicit endpoint times
do not reserve time. Diary expressions are outside the initial scope.
Intervals include their start and exclude their end, so adjacent appointments
may touch. Unreadable agenda sources cause an error.

See [README.org](README.org) for the full usage guide.

## Development and packaging

```sh
make deps   # Install lint/build tools into .deps/elpa, isolated from your Emacs
make check  # ERT, compilation, package-lint, checkdoc, recipe build and installation
make package
```

Set `EMACS=/path/to/emacs` to use another Emacs executable. Missing check
dependencies fail explicitly. CI covers Emacs 29.1 and 31.1.

`make package` uses the [MELPA recipe](recipes/org-plan-task) and MELPA's
`package-build` to package the current checkout into
`dist/org-plan-task-0.1.0.tar`, flattening the implementation modules.
The local build does not fetch the remote repository. Install the tarball
with `M-x package-install-file`; the command is autoloaded. Publishing and
MELPA submission are separate actions.

Copyright © 2026 John Anthony Labarga. Licensed under GPL-3.0-or-later;
see [LICENSE](LICENSE). The implementation was developed with AI
assistance from OpenAI Codex.
