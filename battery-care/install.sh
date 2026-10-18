#!/bin/bash
# Install omarchy-battery-care: hold the pack at the protective charge threshold.
#
#   sudo ./install.sh              install and start
#   sudo ./install.sh --dry-run    say what it would do, change nothing
#   sudo ./install.sh --remove      stop, disarm, and take it all back out
#
# Three root-owned artifacts, all under /usr/local and /etc:
#   /usr/local/sbin/omarchy-battery-care                     the script
#   /etc/systemd/system/omarchy-battery-care.service         the loop (the brake)
#   /etc/systemd/system/omarchy-battery-care-sleep.service   disarm before sleep
#   /usr/local/share/omarchy-battery-care/README.md          this rationale
#
# The script is a real root-owned copy, not a symlink into the repository or into
# ~/bin: a root-run path that a normal user could rewrite is a privilege-escalation
# hole. Re-run this installer after changing the repository copy.
#
# Rollback is one command: sudo ./install.sh --remove. It disarms force-discharge
# first, so a pack is never left with an unbraked discharge running.
#
# Nothing here needs a polkit rule or sudoers entry: the script runs as root from
# systemd, and the battery panel's existing pkexec rule for /usr/bin/tlp covers the
# threshold writes it reacts to.
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

SBIN=/usr/local/sbin/omarchy-battery-care
UNIT_DIR=/etc/systemd/system
SVC=omarchy-battery-care.service
SLEEP_SVC=omarchy-battery-care-sleep.service
DOC_DIR=/usr/local/share/omarchy-battery-care
OFF_SWITCH=/etc/omarchy-battery-care-off

dry=0
remove=0
for arg in "$@"; do
  case $arg in
  --dry-run) dry=1 ;;
  --remove) remove=1 ;;
  --help | -h)
    sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    printf 'unknown option: %s\n' "$arg" >&2
    exit 2
    ;;
  esac
done

run() { if ((dry)); then printf '  would: %s\n' "$*"; else "$@"; fi; }

if ((EUID != 0)); then
  printf '%s\n' "install.sh: needs root (pkexec $0 ${*:-})" >&2
  exit 1
fi

# ---- remove -----------------------------------------------------------------
if ((remove)); then
  echo "== stop"
  run systemctl disable --now "$SLEEP_SVC" 2>/dev/null || true
  run systemctl disable --now "$SVC" 2>/dev/null || true
  # Disarm explicitly: if the loop was SIGKILLed it could not clean up after
  # itself, and removing the unit would then leave a discharge with no brake.
  if [[ -x $SBIN ]]; then
    echo "== disarm"
    run "$SBIN" --release || true
  fi
  echo "== remove files"
  run rm -f "$UNIT_DIR/$SVC" "$UNIT_DIR/$SLEEP_SVC" "$SBIN"
  run rm -rf "$DOC_DIR"
  run systemctl daemon-reload
  printf '%s\n' "removed. The battery is back to plain TLP thresholds (stop at the"
  printf '%s\n' "configured value, and no discharge when already above it)."
  exit 0
fi

# ---- checks -----------------------------------------------------------------
echo "== checks"
for f in omarchy-battery-care omarchy-battery-care.service \
  omarchy-battery-care-sleep.service README.md; do
  if [[ ! -f "$HERE/$f" ]]; then
    printf 'missing %s\n' "$HERE/$f" >&2
    exit 1
  fi
done
bash -n "$HERE/omarchy-battery-care"
bash -n "$HERE/install.sh"

# The unit conditions on these; report rather than refuse, since the script is
# also useful for --status on hardware without them.
if [[ -r /sys/class/power_supply/BAT0/charge_behaviour ]] &&
  grep -q force-discharge /sys/class/power_supply/BAT0/charge_behaviour; then
  printf '  force-discharge capability: yes\n'
else
  printf '  force-discharge capability: NO -- the loop will idle (see --status)\n'
fi

echo "== install script"
run install -D -m 0755 -o root -g root "$HERE/omarchy-battery-care" "$SBIN"
echo "== install units"
run install -D -m 0644 -o root -g root "$HERE/$SVC" "$UNIT_DIR/$SVC"
run install -D -m 0644 -o root -g root "$HERE/$SLEEP_SVC" "$UNIT_DIR/$SLEEP_SVC"
echo "== install rationale doc"
run install -D -m 0644 -o root -g root "$HERE/README.md" "$DOC_DIR/README.md"

echo "== enable"
run systemctl daemon-reload
# The sleep unit is enabled (not started): it is pulled in by sleep.target.
run systemctl enable "$SLEEP_SVC"
run systemctl enable --now "$SVC"

printf '\n%s\n' "done."
printf '%s\n' "  status:  $SBIN --status"
printf '%s\n' "  journal: journalctl -u $SVC -f"
printf '%s\n' "  pause:   touch $OFF_SWITCH && systemctl restart $SVC"
printf '%s\n' "  remove:  $0 --remove"
