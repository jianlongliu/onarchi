#!/bin/bash
# Contract test for omarchy-battery-care, offline: the power supplies are a fake
# sysfs tree, so nothing here discharges the real battery or writes to /sys.
#
# What is being tested is not "does force-discharge work" (the kernel owns that)
# but the reconciliation contract around it:
#   1. parked above a protective stop, on AC   -> enables force-discharge
#   2. already discharging                      -> writes nothing (idempotent)
#   3. below stop                               -> writes nothing
#   4. on battery                               -> writes nothing (and stops one
#                                                  that is somehow still on)
#   5. Full preset selected (stop above band)   -> writes nothing, and a
#                                                  discharge already running is
#                                                  turned off -- this is the
#                                                  "don't override the user" case
#   6. stop below the protective floor (0/0)    -> writes nothing (must not read
#                                                  as "fall to 0%")
#   7. no battery / no stop threshold           -> exits cleanly, writes nothing
#   8. --dry-run and --status                   -> never write
#
#   ./tests/test-battery-care.sh
#
# checks=N failures=M, exit 1 on any failure.

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CARE=$(dirname "$HERE")/omarchy-battery-care
[[ -f $CARE ]] || { echo "no omarchy-battery-care at $CARE"; exit 1; }

checks=0
failures=0
check() { # name got want
  checks=$((checks + 1))
  if [[ $2 == "$3" ]]; then
    printf '  %-52s ok\n' "$1"
  else
    printf '  %-52s FAIL (got %s, want %s)\n' "$1" "$2" "$3"
    failures=$((failures + 1))
  fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
SYSFS="$tmp/sys"
mkdir -p "$SYSFS/AC" "$SYSFS/BAT0"

# --- fixture writers ---------------------------------------------------------
fixture() { # soc stop [ac] [behaviour] [start]
  printf '%s\n' "${5:-75}" >"$SYSFS/BAT0/charge_control_start_threshold"
  printf '%s\n' "$2" >"$SYSFS/BAT0/charge_control_end_threshold"
  printf '%s\n' "$1" >"$SYSFS/BAT0/capacity"
  printf '%s\n' "${4:-$OFF}" >"$SYSFS/BAT0/charge_behaviour"
  printf 'Mains\n' >"$SYSFS/AC/type"
  printf '%s\n' "${3:-1}" >"$SYSFS/AC/online"
  printf 'Battery\n' >"$SYSFS/BAT0/type"
}

# The fixture is writable by this test, so the script's writes actually land and
# can be inspected. (A real /sys is root-owned; nothing here writes to one.)
run_care() { # [args...]
  OMARCHY_BATTERY_SYSFS="$SYSFS" "$CARE" "$@" >"$tmp/out.log" 2>"$tmp/err.log"
  echo $?
}

behaviour() { cat "$SYSFS/BAT0/charge_behaviour" 2>/dev/null || echo "<absent>"; }

# The two kernel renderings of charge_behaviour: which option is bracketed is
# which one is selected.
ON="[auto] inhibit-charge [force-discharge]"
OFF="[auto] inhibit-charge force-discharge"

# --- 1. parked above a protective stop, on AC -> discharge -------------------
fixture 99 80
check "99% on AC, stop 80 -> enables discharge" \
  "$(run_care)" 0
check "  and charge_behaviour is force-discharge" \
  "$(behaviour)" "force-discharge"

# --- 2. already discharging -> no write --------------------------------------
fixture 95 80 1 "$ON"
check "95% already discharging -> exit 0" "$(run_care)" 0
check "  and behaviour left untouched" \
  "$(behaviour)" "$ON"

# --- 3. at or below stop -> no write ----------------------------------------
fixture 80 80
check "80% == stop -> no write" "$(run_care)" 0
check "  behaviour unchanged" "$(behaviour)" "$OFF"

fixture 70 80
check "70% < stop -> no write" "$(run_care)" 0
check "  behaviour unchanged" "$(behaviour)" "$OFF"

# --- 4. on battery -----------------------------------------------------------
fixture 99 80 0
check "99% but on battery -> no write" "$(run_care)" 0
check "  behaviour unchanged" "$(behaviour)" "$OFF"

# a discharge left on from an earlier AC session must be stopped on battery
fixture 99 80 0 "$ON"
check "on battery with discharge stuck on -> stops it" "$(run_care)" 0
check "  behaviour back to auto" "$(behaviour)" "auto"

# --- 5. Full preset selected -> hands off -----------------------------------
# stop 100 is outside the protective band: this is the panel's Full preset.
fixture 99 100
check "stop 100 (Full) -> no write" "$(run_care)" 0
check "  behaviour unchanged" "$(behaviour)" "$OFF"

# ... and an in-flight discharge must be cancelled, or Full cannot charge
fixture 99 100 1 "$ON"
check "stop 100 with discharge running -> cancels it" "$(run_care)" 0
check "  behaviour back to auto (charging can resume)" "$(behaviour)" "auto"

# --- 6. degenerate stop below the floor -------------------------------------
# START=0 STOP=0 is a real convention meaning "no start threshold"; it must not
# be read as "discharge to 0%".
fixture 99 0 1 "$OFF" 0
check "stop 0 -> no write (not 'fall to 0%')" "$(run_care)" 0
check "  behaviour unchanged" "$(behaviour)" "$OFF"

# --- 7. unsupported / absent -----------------------------------------------
# kernel without charge_behaviour (no force-discharge support)
fixture 99 80 1 ""
rm -f "$SYSFS/BAT0/charge_behaviour"
check "no charge_behaviour sysfile -> no write, exit 0" "$(run_care)" 0

fixture 99 80
rm -f "$SYSFS/BAT0/charge_control_end_threshold"
check "no stop threshold -> no write, exit 0" "$(run_care)" 0

# no battery at all
rm -f "$SYSFS/BAT0/type" "$SYSFS/BAT0/capacity"
check "no battery present -> no write, exit 0" "$(run_care)" 0

# --- 8. read-only modes never write ----------------------------------------
fixture 99 80
check "--dry-run exits 0" "$(run_care --dry-run)" 0
check "  and writes nothing" "$(behaviour)" "$OFF"

check "--status exits 0" "$(run_care --status)" 0
check "  and writes nothing" "$(behaviour)" "$OFF"
check "  and reports the decision" \
  "$(grep -c 'decision.*discharge back to 80%' "$tmp/out.log")" 1

fixture 80 80
run_care --status >/dev/null
check "--status at target says leave alone" \
  "$(grep -c 'decision.*leave alone' "$tmp/out.log")" 1

# unknown option is an error, not a silent no-op
check "unknown option -> exit 2" "$(run_care --nonsense)" 2

# --- 9. --release is the brake, and is unconditional -------------------------
# The unit's ExecStopPost runs --release, so it must disarm even in states where
# reconcile would refuse to touch anything.
fixture 99 100 1 "$ON"          # Full selected, discharge somehow still armed
check "--release disarms outside the band" "$(run_care --release)" 0
check "  behaviour back to auto" "$(behaviour)" "auto"

fixture 99 80 0 "$ON"           # on battery, armed
check "--release disarms on battery" "$(run_care --release)" 0
check "  behaviour back to auto" "$(behaviour)" "auto"

fixture 99 80              # nothing armed: must be a clean no-op
check "--release with nothing armed -> exit 0" "$(run_care --release)" 0
check "  behaviour left alone" "$(behaviour)" "$OFF"

fixture 99 80
rm -f "$SYSFS/BAT0/type"        # no battery at all
check "--release with no battery -> exit 0" "$(run_care --release)" 0

# --- 10. the daemon loop holds the brake -------------------------------------
# This is the property the whole design hangs on: force-discharge does not stop
# at the end threshold by itself, so the loop must notice and disarm. Drive it
# with a fast tick and walk the fixture past the threshold.
fixture 90 80 1 "$OFF"          # on AC, above stop, nothing armed
OMARCHY_BATTERY_SYSFS="$SYSFS" OMARCHY_BATTERY_IDLE_TICK=1 \
  OMARCHY_BATTERY_ACTIVE_TICK=1 "$CARE" --daemon >"$tmp/daemon.log" 2>&1 &
daemon_pid=$!
sleep 1.5
check "daemon arms the discharge" "$(behaviour)" "force-discharge"

fixture 81 80 1 "$ON"           # still above stop: stays armed
sleep 1.5
check "daemon keeps it armed above the stop" "$(behaviour)" "$ON"

fixture 80 80 1 "$ON"           # reached stop: must disarm
sleep 2.5
check "daemon disarms at the stop threshold" "$(behaviour)" "auto"

fixture 60 80 1 "$OFF"          # below stop: stays off
sleep 1.5
check "daemon leaves it off below the stop" "$(behaviour)" "$OFF"

# user picks Full while nothing is running -> the loop must not re-arm
fixture 99 100 1 "$OFF"
sleep 1.5
check "daemon never arms under Full" "$(behaviour)" "$OFF"

# and unplugging cancels an armed discharge (0 = AC offline)
fixture 99 80 0 "$ON"
sleep 1.5
check "daemon disarms when AC is removed" "$(behaviour)" "auto"

# --- 11. stopping the daemon disarms (the traps) ----------------------------
fixture 99 80 1 "$OFF"
sleep 1.5
check "daemon armed again on AC" "$(behaviour)" "force-discharge"
kill -TERM "$daemon_pid" 2>/dev/null
wait "$daemon_pid" 2>/dev/null
check "SIGTERM disarms before exit" "$(behaviour)" "auto"

# --- 12. the SIGKILL gap and its backstop -----------------------------------
# The EXIT trap cannot survive SIGKILL, so a killed daemon CAN leave the discharge
# armed. That is precisely why --release exists as an independent second cleanup
# (the unit's ExecStopPost). This test documents the gap rather than pretending it
# does not exist: it asserts the backstop still works after an unhandleable kill.
fixture 99 80 1 "$OFF"
OMARCHY_BATTERY_SYSFS="$SYSFS" OMARCHY_BATTERY_IDLE_TICK=1 \
  OMARCHY_BATTERY_ACTIVE_TICK=1 "$CARE" --daemon >"$tmp/kill.log" 2>&1 &
kpid=$!
sleep 1.5
check "daemon armed for the SIGKILL probe" "$(behaviour)" "force-discharge"
kill -KILL "$kpid" 2>/dev/null
wait "$kpid" 2>/dev/null
check "SIGKILL leaves it armed (the known gap)" "$(behaviour)" "force-discharge"
check "  and --release still cleans it up" "$(run_care --release)" 0
check "  behaviour back to auto" "$(behaviour)" "auto"

printf '\nchecks=%d failures=%d\n' "$checks" "$failures"
((failures == 0)) || exit 1
