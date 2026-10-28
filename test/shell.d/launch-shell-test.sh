#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
launch_pid=""

# A supervisor that fails to stop would hang the run instead of failing it.
cleanup() {
  if [[ -n $launch_pid ]]; then
    pkill -TERM -P "$launch_pid" 2>/dev/null || true
    kill -KILL "$launch_pid" 2>/dev/null || true
    wait "$launch_pid" 2>/dev/null || true
  fi
  rm -rf "$test_tmp"
}
trap cleanup EXIT

fake_bin="$test_tmp/bin"
shell_root="$test_tmp/root"
launch_home="$test_tmp/home"
startup_wallpaper="$test_tmp/Selected wallpaper.webp"
mkdir -p "$fake_bin" "$shell_root/shell" "$launch_home/.local/state/omarchy/current"
touch "$startup_wallpaper"
ln -s "$startup_wallpaper" "$launch_home/.local/state/omarchy/current/background"

# Run a scratch copy of the supervisor with its 1s relaunch backoff and
# 0.5s compositor probe shortened; the scenarios only need the waiting
# to happen, not its real duration. The backoff stays well above the
# 0.05s launch poll below so the signal case lands inside it.
launch_shell_bin="$test_tmp/omarchy-launch-shell"
sed -e 's/^  sleep 1$/  sleep 0.3/' -e 's/sleep 0.5$/sleep 0.05/' \
  "$ROOT/bin/omarchy-launch-shell" >"$launch_shell_bin"
chmod +x "$launch_shell_bin"
# The niri port additionally captures the crash-handler flag and needs a
# private XDG_RUNTIME_DIR, so this machine's launcher has both.
runtime_dir="$test_tmp/run"
mkdir -p "$runtime_dir"

# Each launch consumes the next status from OMARCHY_TEST_QS_STATUSES; "run"
# stands in for a healthy shell that keeps going until stopped. The supervisor
# asks this same binary whether the config's instance slot is taken, so a `list`
# answers from a count of live instances: each query consumes one, which lets a
# test keep an instance up for a while and then have it die.
cat >"$fake_bin/quickshell" <<'SH'
#!/bin/bash

if [[ $1 == list ]]; then
  count=$(cat "${OMARCHY_TEST_SHELL_ALIVE:-/nonexistent}" 2>/dev/null || printf '0')

  if (( ${count:-0} > 0 )); then
    printf '%s\n' "$(( count - 1 ))" >"$OMARCHY_TEST_SHELL_ALIVE"
    printf '[\n    {\n        "config_path": "%s/shell/shell.qml",\n        "pid": 1\n    }\n]\n' "$OMARCHY_PATH"
  else
    printf 'No running instances for "%s/shell/shell.qml"\n' "$OMARCHY_PATH"
  fi
  exit 0
fi

printf '%s\n' "$*" >>"$OMARCHY_TEST_QS_LOG"
printf 'watcher=%s popup=%s crashhandler=%s background=%s\n' \
  "${QS_DISABLE_FILE_WATCHER:-unset}" "${QS_NO_RELOAD_POPUP:-unset}" \
  "${QS_DISABLE_CRASH_HANDLER:-unset}" "${OMARCHY_STARTUP_BACKGROUND:-unset}" >>"$OMARCHY_TEST_QS_ENV_LOG"

launches=$(wc -l <"$OMARCHY_TEST_QS_LOG")
status=$(awk -v n="$launches" 'NR == n { print; found = 1 } END { if (!found) print "0" }' <<<"$OMARCHY_TEST_QS_STATUSES")

# A foreign instance answering while nothing holds the slot is the leftover a
# takeover test needs: it arms one as its own shell exits, so the slot frees
# from this supervisor's engine while another instance is there to hold it.
if [[ $status == "0" && -n ${OMARCHY_TEST_QS_ARM:-} ]]; then
  printf '%s\n' "$OMARCHY_TEST_QS_ARM" >"$OMARCHY_TEST_SHELL_ALIVE"
fi

if [[ $status == "run" ]]; then
  trap 'touch "$OMARCHY_TEST_QS_TERMINATED"; exit 143' TERM
  while true; do sleep 0.05; done
fi

exit "${status:-0}"
SH

cat >"$fake_bin/systemd-cat" <<'SH'
#!/bin/bash

while (( $# > 0 )); do
  [[ $1 == "--" ]] && { shift; break; }
  shift
done
exec "$@"
SH

cat >"$fake_bin/hyprctl" <<'SH'
#!/bin/bash

[[ ${OMARCHY_TEST_COMPOSITOR_GONE:-0} == 1 ]] && exit 4

# Refuse the first OMARCHY_TEST_HYPRCTL_MISSES queries, then answer.
if (( ${OMARCHY_TEST_HYPRCTL_MISSES:-0} > 0 )); then
  misses=$(cat "$OMARCHY_TEST_HYPRCTL_MISS_COUNT" 2>/dev/null || printf '0')
  if (( misses < OMARCHY_TEST_HYPRCTL_MISSES )); then
    printf '%s\n' "$(( misses + 1 ))" >"$OMARCHY_TEST_HYPRCTL_MISS_COUNT"
    exit 4
  fi
fi

printf '[]\n'
SH

cat >"$fake_bin/logger" <<'SH'
#!/bin/bash

shift 2
printf '%s\n' "$*" >>"$OMARCHY_TEST_LOGGER_LOG"
SH

chmod +x "$fake_bin/quickshell" "$fake_bin/systemd-cat" "$fake_bin/hyprctl" "$fake_bin/logger"

qs_log="$test_tmp/quickshell.log"
qs_env_log="$test_tmp/quickshell-env.log"
logger_log="$test_tmp/logger.log"
qs_terminated="$test_tmp/quickshell-terminated"
hyprctl_misses="$test_tmp/hyprctl-misses"

launch_shell() {
  : >"$qs_log"
  : >"$qs_env_log"
  : >"$logger_log"

  # A runtime dir of its own: the supervisor lock lives in the real one, and the
  # session's own supervisor holds it.
  PATH="$fake_bin:$PATH" \
  HOME="$launch_home" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  OMARCHY_PATH="$shell_root" \
  OMARCHY_TEST_QS_LOG="$qs_log" \
  OMARCHY_TEST_QS_ENV_LOG="$qs_env_log" \
  OMARCHY_TEST_QS_STATUSES="$1" \
  OMARCHY_TEST_COMPOSITOR_GONE="${2:-0}" \
  OMARCHY_TEST_LOGGER_LOG="$logger_log" \
  OMARCHY_TEST_QS_TERMINATED="$qs_terminated" \
  OMARCHY_TEST_HYPRCTL_MISSES="${3:-0}" \
  OMARCHY_TEST_HYPRCTL_MISS_COUNT="$hyprctl_misses" \
    timeout 30 "$launch_shell_bin"
}

launches() {
  wc -l <"$qs_log" | tr -d ' '
}

launch_shell '0' || fail "a clean launch succeeds"
[[ $(launches) == 1 ]] || fail "a shell that exits cleanly is not relaunched" "$(<"$qs_log")"
grep -F -- "-n -p $shell_root/shell" "$qs_log" >/dev/null || fail "the shell launches from OMARCHY_PATH"
pass "a shell that exits cleanly is left alone"

# A misspelled variable would leave Quickshell hot-reloading the tree pacman
# rewrites underneath it, which is what crashes the restart that follows. Its
# crash handler gets the same treatment: a relaunch of its own races this
# supervisor's and leaves two engines fighting over the session lock.
[[ $(<"$qs_env_log") == "watcher=1 popup=1 crashhandler=1 "* ]] ||
  fail "the shell launches with Quickshell's own reloading off" "$(<"$qs_env_log")"
pass "the shell launches with Quickshell's config watcher, reload popup and crash handler off"
[[ $(<"$qs_env_log") == *"background=$startup_wallpaper" ]] || fail "the shell receives the resolved wallpaper path before startup" "$(<"$qs_env_log")"
pass "the selected wallpaper can decode as soon as Quickshell starts"

# Qt leaves through _exit(), so Quickshell's crash handler never relaunches it.
launch_shell $'255\n0' || fail "a shell that died on a Wayland error is relaunched"
[[ $(launches) == 2 ]] || fail "the dead shell is relaunched exactly once" "$(<"$qs_log")"
grep -F 'exited with status 255' "$logger_log" >/dev/null || fail "the relaunch is recorded in the journal"
pass "a shell that dies without a signal is relaunched"

launch_shell $'255\n255\n255\n255\n255\n255\n255\n255' && fail "a shell that keeps dying is given up on"
[[ $(launches) == 6 ]] || fail "relaunches stop after the attempt budget" "$(<"$qs_log")"
grep -F 'Giving up' "$logger_log" >/dev/null || fail "giving up is recorded in the journal"
pass "a shell that keeps dying is not relaunched forever"

# The compositor takes the shell with it, and the session is already going.
launch_shell $'255\n0' 1 || fail "a shell outliving the compositor exits cleanly"
[[ $(launches) == 1 ]] || fail "the shell is not relaunched into a dead session" "$(<"$qs_log")"
pass "the shell is not relaunched once the compositor is gone"

# A compositor mid-modeset can miss a query without being gone.
rm -f "$hyprctl_misses"
launch_shell $'255\n0' 0 2 || fail "a shell survives a compositor that misses a query"
[[ $(launches) == 2 ]] || fail "a missed compositor query does not end supervision" "$(<"$qs_log")"
pass "a compositor too busy to answer is not mistaken for one that is gone"

# A signal mid-backoff only reaches the trap once the sleep is over.
: >"$qs_log"
: >"$qs_env_log"
: >"$logger_log"

PATH="$fake_bin:$PATH" \
XDG_RUNTIME_DIR="$runtime_dir" \
OMARCHY_PATH="$shell_root" \
OMARCHY_TEST_QS_LOG="$qs_log" \
OMARCHY_TEST_QS_ENV_LOG="$qs_env_log" \
OMARCHY_TEST_QS_STATUSES=$'255\n0' \
OMARCHY_TEST_COMPOSITOR_GONE=0 \
OMARCHY_TEST_LOGGER_LOG="$logger_log" \
OMARCHY_TEST_QS_TERMINATED="$qs_terminated" \
  "$launch_shell_bin" &
launch_pid=$!

for (( waited = 0; waited < 100; waited++ )); do
  [[ $(launches) == 1 ]] && break
  sleep 0.05
done
[[ $(launches) == 1 ]] || fail "the supervised shell launched before the signal" "$(<"$qs_log")"

kill -TERM "$launch_pid"
wait "$launch_pid" || fail "a signalled supervisor exits cleanly"
launch_pid=""
[[ $(launches) == 1 ]] || fail "the shell is not relaunched after the session asked to stop" "$(<"$qs_log")"
pass "a signal during backoff stops the supervisor before it relaunches"

# Stopping the launcher used to stop the shell, back when it exec'd Quickshell.
: >"$qs_log"
: >"$qs_env_log"
: >"$logger_log"
rm -f "$qs_terminated"

PATH="$fake_bin:$PATH" \
XDG_RUNTIME_DIR="$runtime_dir" \
OMARCHY_PATH="$shell_root" \
OMARCHY_TEST_QS_LOG="$qs_log" \
OMARCHY_TEST_QS_ENV_LOG="$qs_env_log" \
OMARCHY_TEST_QS_STATUSES='run' \
OMARCHY_TEST_COMPOSITOR_GONE=0 \
OMARCHY_TEST_LOGGER_LOG="$logger_log" \
OMARCHY_TEST_QS_TERMINATED="$qs_terminated" \
  "$launch_shell_bin" &
launch_pid=$!

for (( waited = 0; waited < 100; waited++ )); do
  [[ $(launches) == 1 ]] && break
  sleep 0.05
done
[[ $(launches) == 1 ]] || fail "the healthy shell launched before the signal" "$(<"$qs_log")"

kill -TERM "$launch_pid"
for (( waited = 0; waited < 100; waited++ )); do
  kill -0 "$launch_pid" 2>/dev/null || break
  sleep 0.05
done
kill -0 "$launch_pid" 2>/dev/null && fail "a signalled supervisor stops instead of waiting on a live shell"
wait "$launch_pid" 2>/dev/null || true
launch_pid=""

[[ -f $qs_terminated ]] || fail "the running shell is signalled when the supervisor is"
[[ $(launches) == 1 ]] || fail "the signalled shell is not relaunched" "$(<"$qs_log")"
pass "stopping the supervisor stops the shell it is watching"

# A shell this supervisor did not start holds the config's instance slot: the
# leftover of a supervisor that died. Leaving it unsupervised is what stranded
# the session when it went, and launching into the slot would be the second
# engine the crash handler used to raise. The arm makes the supervisor's own
# shell exit cleanly with that instance already listed, so the slot frees while
# the instance is still there to hold it.
: >"$qs_log"
: >"$qs_env_log"
: >"$logger_log"
instances="$test_tmp/instances"
printf '0\n' >"$instances"

PATH="$fake_bin:$PATH" \
XDG_RUNTIME_DIR="$runtime_dir" \
OMARCHY_PATH="$shell_root" \
OMARCHY_TEST_QS_LOG="$qs_log" \
OMARCHY_TEST_QS_ENV_LOG="$qs_env_log" \
OMARCHY_TEST_QS_STATUSES=$'0\nrun' \
OMARCHY_TEST_COMPOSITOR_GONE=0 \
OMARCHY_TEST_LOGGER_LOG="$logger_log" \
OMARCHY_TEST_QS_TERMINATED="$qs_terminated" \
OMARCHY_TEST_SHELL_ALIVE="$instances" \
OMARCHY_TEST_QS_ARM=8 \
  "$ROOT/bin/omarchy-launch-shell" &
launch_pid=$!

for (( waited = 0; waited < 100; waited++ )); do
  [[ $(launches) == 1 ]] && break
  sleep 0.05
done
[[ $(launches) == 1 ]] || fail "the supervised shell launched before the slot freed" "$(<"$qs_log")"

# Its own shell exited cleanly while that instance kept answering: the session
# has a shell, so this supervisor must not raise a second one.
sleep 1
[[ $(launches) == 1 ]] || fail "a shell in the slot is not duplicated" "$(<"$qs_log")"

for (( waited = 0; waited < 200; waited++ )); do
  [[ $(launches) == 2 ]] && break
  sleep 0.1
done
[[ $(launches) == 2 ]] || fail "the slot is taken over once the instance in it dies" "$(<"$qs_log")"
grep -F 'holds the slot' "$logger_log" >/dev/null || fail "the take-over is recorded in the journal"
pass "an instance this supervisor did not start is waited out, then taken over"

kill -TERM "$launch_pid" 2>/dev/null || true
wait "$launch_pid" 2>/dev/null || true
launch_pid=""

# Two supervisors would each raise their own engine, so a launcher that cannot
# hold the lock leaves the session to the supervisor that can.
: >"$qs_log"
: >"$logger_log"
display=${WAYLAND_DISPLAY:-nosession}
exec 8>"$runtime_dir/omarchy-shell-supervisor.${display##*/}.lock"
flock -n 8

launch_shell '0' || fail "a launcher that yields still exits cleanly"
[[ $(launches) == 0 ]] || fail "a second supervisor does not raise an engine" "$(<"$qs_log")"
grep -F 'supervisor is running' "$logger_log" >/dev/null || fail "the yield is recorded in the journal"
pass "a second supervisor yields to the one already running"

flock -u 8
exec 8>&-
