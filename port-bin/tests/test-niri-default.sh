#!/bin/bash
# Offline contract test for omarchy-niri-default.  No niri session, no real
# ~/.config/niri, no sudo: niri/gum/notify are stubs in a temp dir.
#
# Covers: save, status, reset with confirmations, archive contents, cancel paths,
# and automatic restore when the post-install validation fails.
#
#   ./tests/test-niri-default.sh

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SCRIPT=$(dirname "$HERE")/omarchy-niri-default
[[ -x $SCRIPT ]] || { echo "no executable at $SCRIPT"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export HOME=$tmp/home
export XDG_STATE_HOME=$HOME/.local/state
export NIRI_CONFIG_DIR=$HOME/.config/niri
export NIRI_TEMPLATE_DIR=$XDG_STATE_HOME/omarchy/niri-default
export NIRI_BACKUP_DIR=$XDG_STATE_HOME/backups
export NIRI_SOCKET=fake
export STUB_LOG=$tmp/stub.log
export STUB_COUNTER=$tmp/stub.counter
mkdir -p "$NIRI_CONFIG_DIR" "$NIRI_BACKUP_DIR" "$tmp/bin"

for f in config input monitor layout window-rules effects binds; do
  if [[ $f == layout ]]; then
    printf 'live-layout\nfocus-ring {\n    width 2\n    active-color "#aaaaaaff"\n}\n' >"$NIRI_CONFIG_DIR/$f.kdl"
  else
    printf 'live-%s\n' "$f" >"$NIRI_CONFIG_DIR/$f.kdl"
  fi
done

cat >"$tmp/bin/niri" <<'SH'
#!/bin/bash
printf 'niri %s\n' "$*" >>"$STUB_LOG"
if [[ $1 == validate ]]; then
  printf 'WARN niri_config: optional include not found\n' >&2
  if [[ ${FAIL_VALIDATE:-0} == 1 ]]; then
    n=$(cat "$STUB_COUNTER" 2>/dev/null || echo 0)
    n=$((n + 1))
    printf '%s\n' "$n" >"$STUB_COUNTER"
    (( n >= ${FAIL_AT:-2} )) && exit 1
  fi
fi
exit 0
SH
cat >"$tmp/bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf 'notify %s | %s\n' "$1" "$2" >>"$STUB_LOG"
SH
cat >"$tmp/bin/omarchy-niri-apply-theme" <<'SH'
#!/bin/bash
printf 'apply-theme\n' >>"$STUB_LOG"
sed -i 's/^[[:space:]]*active-color .*/    active-color "#123456ff"/' "$NIRI_CONFIG_DIR/layout.kdl"
SH
chmod +x "$tmp/bin/niri" "$tmp/bin/omarchy-notification-send" "$tmp/bin/omarchy-niri-apply-theme"
export PATH="$tmp/bin:/usr/bin:/bin"

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

"$SCRIPT" save >"$tmp/save.out" 2>&1
check "save exits 0" "$?" "0"
grep -q '^live-layout$' "$NIRI_TEMPLATE_DIR/layout.kdl"
check "save writes live layout" "$?" "0"
if grep -q 'optional include not found' "$tmp/save.out"; then leaked=yes; else leaked=no; fi
check "save hides niri validation warnings" "$leaked" "no"

"$SCRIPT" status >"$tmp/status.out" 2>&1
check "status exits 0 when identical" "$?" "0"
grep -q 'same    layout.kdl' "$tmp/status.out"
check "status reports layout same" "$?" "0"

sed -i 's/#aaaaaaff/#ccccccff/' "$NIRI_CONFIG_DIR/layout.kdl"
"$SCRIPT" status >"$tmp/theme.out" 2>&1
check "status ignores theme colour changes" "$?" "0"
grep -q 'same    layout.kdl (theme colours ignored)' "$tmp/theme.out"
check "status labels theme colours ignored" "$?" "0"

sed -i 's/width 2/width 3/' "$NIRI_CONFIG_DIR/layout.kdl"
"$SCRIPT" status >/dev/null 2>&1
check "status still detects structural changes" "$?" "1"
sed -i 's/width 3/width 2/' "$NIRI_CONFIG_DIR/layout.kdl"

printf 'changed-layout\n' >"$NIRI_CONFIG_DIR/layout.kdl"
before=$(find "$NIRI_BACKUP_DIR" -maxdepth 1 -name 'niri-config-*.tar.gz' 2>/dev/null | wc -l)
printf 'y\ny\nDEFAULT\n' | "$SCRIPT" reset >"$tmp/reset.out" 2>&1
check "reset exits 0 after confirmations" "$?" "0"
grep -q '^live-layout$' "$NIRI_CONFIG_DIR/layout.kdl"
check "reset restores the saved layout" "$?" "0"
grep -q '#123456ff' "$NIRI_CONFIG_DIR/layout.kdl"
check "reset refreshes theme colours" "$?" "0"
grep -q '^apply-theme$' "$STUB_LOG"
check "reset calls the theme applier" "$?" "0"
"$SCRIPT" status >/dev/null 2>&1
check "status is clean after theme refresh" "$?" "0"
after=$(find "$NIRI_BACKUP_DIR" -maxdepth 1 -name 'niri-config-*.tar.gz' 2>/dev/null | wc -l)
check "reset creates one archive" "$((after - before))" "1"
archive=$(find "$NIRI_BACKUP_DIR" -maxdepth 1 -name 'niri-config-*.tar.gz' | head -1)
check "archive holds the pre-reset layout" "$(tar -xOzf "$archive" layout.kdl)" "changed-layout"
grep -q "Backed up current niri config to: $archive" "$tmp/reset.out"
check "reset prints the archive path" "$?" "0"
if grep -q 'optional include not found' "$tmp/reset.out"; then leaked=yes; else leaked=no; fi
check "reset hides niri validation warnings" "$leaked" "no"
grep -q 'niri msg action load-config-file' "$STUB_LOG"
check "reset reloads niri" "$?" "0"

printf 'cancel-me\n' >"$NIRI_CONFIG_DIR/layout.kdl"
before=$after
printf 'n\n' | "$SCRIPT" reset >"$tmp/cancel.out" 2>&1
check "first No cancels" "$?" "1"
check "cancel leaves live untouched" "$(cat "$NIRI_CONFIG_DIR/layout.kdl")" "cancel-me"
after=$(find "$NIRI_BACKUP_DIR" -maxdepth 1 -name 'niri-config-*.tar.gz' | wc -l)
check "cancel creates no archive" "$after" "$before"
grep -q 'Cancelled. Nothing was changed.' "$tmp/cancel.out"
check "cancel prints the safe message" "$?" "0"

printf 'y\ny\nNOPE\n' | "$SCRIPT" reset >"$tmp/badword.out" 2>&1
check "wrong keyword cancels" "$?" "1"
check "wrong keyword leaves live untouched" "$(cat "$NIRI_CONFIG_DIR/layout.kdl")" "cancel-me"

printf 'keep-me\n' >"$NIRI_CONFIG_DIR/layout.kdl"
: >"$STUB_COUNTER"
FAIL_VALIDATE=1 FAIL_AT=2 bash -c 'printf "y\ny\nDEFAULT\n" | "$0" reset' "$SCRIPT" >"$tmp/rollback.out" 2>&1
check "post-install validation failure exits 1" "$?" "1"
check "failed reset restores pre-reset layout" "$(cat "$NIRI_CONFIG_DIR/layout.kdl")" "keep-me"
grep -q 'previous config restored from' "$tmp/rollback.out"
check "failed reset reports the restore" "$?" "0"
grep -q 'optional include not found' "$tmp/rollback.out"
check "failed reset shows validation output" "$?" "0"

bash -n "$SCRIPT" 2>/dev/null
check "script parses (bash -n)" "$?" "0"

echo
echo "checks=$checks failures=$failures"
[[ $failures -eq 0 ]]
