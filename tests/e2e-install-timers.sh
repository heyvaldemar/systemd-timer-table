#!/bin/bash
# Does it refuse to install a schedule that would never fire?
#
# That is the whole point. A bad OnCalendar expression installs cleanly and
# then never runs: no error, no log line, and nothing to tell it apart from a
# job whose time has not come. You find out when you go looking for the thing
# it should have done - which for a backup is the day you need one.
#
# So the scenarios below are mostly refusals, and each is given a table broken
# in exactly one way. Needs systemd-analyze, so it runs in a container.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/install-timers.sh"
WORK="$(mktemp -d)"
PASSED=0; FAILED=0
trap 'rm -rf "$WORK"' EXIT

pass() { echo "  PASS: $1"; PASSED=$((PASSED+1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED+1)); }

mkdir -p "$WORK/units" "$WORK/bin"
printf '#!/bin/sh\nexit 0\n' > "$WORK/bin/ok.sh"; chmod +x "$WORK/bin/ok.sh"
printf 'not executable\n' > "$WORK/bin/nox.sh"

run() {  # run <table-file> [mode]
  TIMER_TABLE="$1" TIMER_UNIT_DIR="$WORK/units" bash "$SCRIPT" "${2:-}" 2>&1
}
units_present() { find "$WORK/units" -name '*.timer' 2>/dev/null | grep -c . ; }

echo "=== systemd timer table ==="
echo

# ------------------------------------------------------------------ control
t="$WORK/good.tsv"
printf 'job-a\t*-*-* 02:30:00\tyes\t%s/ok.sh\tA nightly job\n' "$WORK/bin" > "$t"
printf 'job-b\t*:0/5\tno\t%s/ok.sh\tEvery five minutes\n' "$WORK/bin" >> "$t"
out="$(run "$t" --check)"
if printf '%s' "$out" | grep -q '2 jobs, all valid'; then
  pass "a valid table is accepted"
else
  fail "a valid table was rejected"; printf '%s\n' "$out" | sed 's/^/        /'
fi

# ------------------------------------------- the refusals, one break each
t="$WORK/badcal.tsv"
printf 'job-a\tevery second tuesday-ish\tno\t%s/ok.sh\tNonsense\n' "$WORK/bin" > "$t"
rm -f "$WORK/units"/*; out="$(run "$t")"; rc=$?
if [ $rc -ne 0 ] && [ "$(units_present)" -eq 0 ]; then
  pass "a calendar expression systemd cannot parse stops the run, and writes nothing"
else
  fail "an unparseable schedule was installed"; printf '%s\n' "$out" | sed 's/^/        /'
fi

t="$WORK/mixed.tsv"
printf 'job-a\t*-*-* 02:30:00\tyes\t%s/ok.sh\tFine\n' "$WORK/bin" > "$t"
printf 'job-b\tnonsense here\tno\t%s/ok.sh\tBroken\n' "$WORK/bin" >> "$t"
printf 'job-c\t*-*-* 04:00:00\tno\t%s/ok.sh\tAlso fine\n' "$WORK/bin" >> "$t"
rm -f "$WORK/units"/*; out="$(run "$t")"
# ALL OF IT OR NONE. A run that installs the first job and dies on the second
# leaves a host in a state nobody chose and nobody knows about.
if [ "$(units_present)" -eq 0 ]; then
  pass "one bad line in three stops everything — no partial install"
else
  fail "$(units_present) timers were written despite a bad line"
fi

t="$WORK/nox.tsv"
printf 'job-a\t*-*-* 02:30:00\tno\t%s/nox.sh\tNot executable\n' "$WORK/bin" > "$t"
rm -f "$WORK/units"/*; out="$(run "$t")"
if printf '%s' "$out" | grep -q 'not executable' && [ "$(units_present)" -eq 0 ]; then
  pass "a command without the executable bit is caught before install"
else
  fail "a non-executable command was scheduled"; printf '%s\n' "$out" | sed 's/^/        /'
fi

t="$WORK/missing.tsv"
printf 'job-a\t*-*-* 02:30:00\tno\t/does/not/exist.sh\tMissing\n' > "$t"
rm -f "$WORK/units"/*; out="$(run "$t")"
if [ "$(units_present)" -eq 0 ]; then
  pass "a command that is not there is caught before install"
else
  fail "a missing command was scheduled"
fi

t="$WORK/badpersist.tsv"
printf 'job-a\t*-*-* 02:30:00\tmaybe\t%s/ok.sh\tTypo\n' "$WORK/bin" > "$t"
out="$(run "$t" --check)"
if printf '%s' "$out" | grep -q 'persistent must be yes or no'; then
  pass "a typo in the persistent column is rejected rather than read as no"
else
  fail "an unrecognised persistent value was accepted"; printf '%s\n' "$out" | sed 's/^/        /'
fi

t="$WORK/empty.tsv"
printf '# only a comment\n' > "$t"
out="$(run "$t" --check)"
if printf '%s' "$out" | grep -q 'defines no jobs'; then
  pass "a table with no jobs is an error, not a quiet success"
else
  fail "an empty table reported success"
fi

# ---------------------------------------------------------------- it writes
t="$WORK/good.tsv"
rm -f "$WORK/units"/*; out="$(run "$t")"
if [ "$(units_present)" -eq 2 ]; then
  pass "a valid table produces one timer per job"
else
  fail "expected 2 timers, found $(units_present)"; printf '%s\n' "$out" | sed 's/^/        /'
fi
if grep -q 'Persistent=true' "$WORK/units/job-a.timer" && ! grep -q 'Persistent' "$WORK/units/job-b.timer"; then
  pass "persistent is set for the job that asked for it and only that one"
else
  fail "the persistent column did not reach the units"
fi
if grep -q 'TimeoutStartSec' "$WORK/units/job-a.service"; then
  pass "the service is bounded, so a hung job fails its unit rather than running on"
else
  fail "no TimeoutStartSec in the generated service"
fi

# ------------------------------------------------- what it writes is valid
# The generator can be right about the table and still emit something systemd
# will not load, which would be a fine way to break every schedule at once.
if systemd-analyze verify "$WORK/units/job-a.timer" 2>&1 | grep -viE 'Failed to (prepare|resolve)|not found' | grep -q .; then
  fail "systemd rejects the generated timer: $(systemd-analyze verify "$WORK/units/job-a.timer" 2>&1 | head -2)"
else
  pass "systemd accepts the generated units"
fi

# ------------------------------------------------------------- idempotent
before="$(cat "$WORK/units/job-a.timer")"
run "$t" >/dev/null 2>&1
if [ "$before" = "$(cat "$WORK/units/job-a.timer")" ]; then
  pass "running it twice changes nothing"
else
  fail "a second run rewrote the unit differently"
fi

echo
echo "passed: $PASSED   failed: $FAILED"
[ "$FAILED" -eq 0 ]
