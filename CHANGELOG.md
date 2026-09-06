# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_(no unreleased changes yet)_

## [1.0.0] - 2026-09-06

### Added

- **Every scheduled job on a host generated from one tab-separated table**,
  one line per job, with the columns being the decisions: the schedule, whether
  a missed run is caught up, and what is actually executed.
- **Nothing is written until every line has been checked.** An `OnCalendar`
  expression systemd cannot parse installs cleanly and then never fires — no
  error, no log line, and nothing to distinguish it from a job whose time has
  not come. Every expression goes through `systemd-analyze calendar` first.
- **All of the table or none of it.** One bad line stops the run before a
  single file is written, because a run that installs eleven jobs and dies on
  the twelfth leaves a host in a state nobody chose.
- **The command is checked too**, for existence and the executable bit. A timer
  pointing at a path that moved fails once a day in silence.
- **A typo in the `persistent` column is an error**, not a `no`. Read as `no`,
  it is a nightly backup that quietly stops catching up after a reboot.
- **Every generated service is bounded** by `TimeoutStartSec`, so a job that
  hangs fails its unit and appears in `systemctl --failed` rather than running
  until somebody notices.
- **Twelve end-to-end scenarios**, most of them refusals, each given a table
  broken in exactly one way — and a check that `systemd-analyze verify` accepts
  what the generator emits, because being right about the table and still
  emitting something systemd will not load would break every schedule at once.

[Unreleased]: https://github.com/heyvaldemar/systemd-timer-table/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/heyvaldemar/systemd-timer-table/releases/tag/v1.0.0
