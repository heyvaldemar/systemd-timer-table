# systemd timer table

[![Tests](https://github.com/heyvaldemar/systemd-timer-table/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/heyvaldemar/systemd-timer-table/actions/workflows/tests.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Every scheduled job on a host, in one table. The units are generated from it, and nothing is written until every line has been checked.

```
backup-nightly	*-*-* 02:30:00	yes	/usr/local/sbin/backup.sh	Nightly backup
deadman	*:0/5	no	/usr/local/sbin/deadman.sh	Ping the switch every five minutes
```

## The failure this exists to prevent

An `OnCalendar` expression that systemd cannot parse installs perfectly cleanly and then never fires. No error, no log line, and nothing that distinguishes it from a job whose time has not come round yet. You find out when you go looking for the thing it should have done — which for a backup is the day you need one.

So every expression in the table goes through `systemd-analyze calendar` before anything is written, and one bad line stops the whole run. So does a command that is missing, or present without its executable bit, or a `persistent` column with a typo in it — because `maybe` read as `no` is a nightly backup that quietly stops catching up after a reboot.

It is all of the table or none of it. A run that installs eleven jobs and dies on the twelfth leaves a host in a state nobody chose and nobody knows about.

## Why a table

A unit and a timer per job is six lines of boilerplate each, and boilerplate is where they drift. One gets `Persistent=true` and the next does not. One names its script by an absolute path, another trusts `$PATH`. One was edited last year for a reason nobody wrote down. Thirty of those and the honest answer to "what runs on this box" is a directory listing.

With a table the difference between two jobs is one line, and the columns are the decisions: does a missed run get caught up, and what does it actually execute.

## Why not cron

Three things this needs that cron does not offer. A missed run can be caught up per job — right for a nightly backup, wrong for a five-minute poll, which would otherwise fire once on boot for every interval it slept through. A job that hangs is bounded by `TimeoutStartSec` and shows up in `systemctl --failed` instead of running until somebody notices. And `systemctl list-timers` answers the question you actually have at three in the morning: when did this last run, and when does it run next.

## Install

```bash
sudo install -m 755 install-timers.sh /usr/local/sbin/install-timers.sh
sudo mkdir -p /etc/systemd-timer-table
sudo cp jobs.tsv.example /etc/systemd-timer-table/jobs.tsv
sudo $EDITOR /etc/systemd-timer-table/jobs.tsv

sudo install-timers.sh --check     # validate, write nothing
sudo install-timers.sh             # generate, reload, enable
install-timers.sh --list           # what is scheduled now
```

Tabs between the columns, not spaces. `TIMER_USER_MODE=true` writes user units instead — with `loginctl enable-linger <user>`, or they will not run without a login session.

## The columns

| Column | What it decides |
|---|---|
| `name` | the unit names: `<name>.service` and `<name>.timer` |
| `schedule` | any `OnCalendar` expression, or `hourly`/`daily`/`weekly`/`monthly` |
| `persistent` | `yes` catches up a run missed while the machine was off |
| `command` | absolute path, or a program on `PATH`; checked before install |
| `description` | what `systemctl status` and `list-timers` show |

`TIMER_TIMEOUT` (default `1h`) bounds every job, and `TIMER_JITTER` spreads them if several land on the same minute.

## What it does not do

It does not manage what your jobs do, or watch whether they succeeded. A job that runs on time and fails every time is still a failure, and the thing that notices is a dead man's switch: [deadman-switch](https://github.com/heyvaldemar/deadman-switch) has a `no_failed_units` check that covers every unit on the host, including the ones this generates.

It does not remove units for jobs you delete from the table. Deleting a schedule is deliberate enough to be worth `systemctl disable --now <name>.timer` by hand.

## Testing

`tests/e2e-install-timers.sh` gives the generator a table broken in exactly one way at a time, twelve scenarios, and most of them are refusals: an unparseable schedule, one bad line among three good ones, a command that is missing, a command without its executable bit, a typo in the persistent column, an empty table. Then it checks that what does get written is right — the persistent flag reaches only the job that asked for it, the service is bounded, running twice changes nothing — and that `systemd-analyze verify` accepts the generated units, because a generator can be right about the table and still emit something systemd will not load.

---

## About the maintainer

<div align="center">

**Maintained by [Vladimir Mikhalev](https://github.com/heyvaldemar)** · Docker Captain · IBM Champion · AWS Community Builder

[YouTube](https://www.youtube.com/channel/UCf85kQ0u1sYTTTyKVpxrlyQ?sub_confirmation=1) · [Blog](https://heyvaldemar.com) · [LinkedIn](https://www.linkedin.com/in/heyvaldemar/)

</div>
