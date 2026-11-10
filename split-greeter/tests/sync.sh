#!/bin/sh
# Exercise `split-greeter-sync --self` against a fake greeter artwork tree.
# No root and no real /var/lib/greeter access.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SYNC=$HERE/../sync.sh
USER_NAME=$(id -un)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  [ "$1" = "$2" ] || fail "$3: expected '$2', got '$1'"
}

assert_file() {
  [ -f "$1" ] || fail "missing file: $1"
}

DEST=$TMP/greeter
STATE=$TMP/state
ROOT=$DEST/users/$USER_NAME
mkdir -p "$ROOT" "$STATE/theme" "$TMP/shared-theme"
printf 'old-colors\n' >"$TMP/shared-theme/colors.toml"
printf 'old-wallpaper\n' >"$TMP/shared-wallpaper"
printf 'colors-one\n' >"$STATE/theme/colors.toml"
printf 'shell-one\n' >"$STATE/theme/shell.toml"
printf 'wallpaper-one\n' >"$TMP/wall-one"
printf 'wallpaper-two\n' >"$TMP/wall-two"
ln -s "$TMP/wall-one" "$STATE/background"

# Older installs left these as greeter-owned fallbacks; --self must replace
# the links with real, account-owned copies.
ln -s "$TMP/shared-theme" "$ROOT/theme"
ln -s "$TMP/shared-wallpaper" "$ROOT/wallpaper"

run_self() { # dest — run and keep stdout/stderr for assertions
  out=$TMP/out
  err=$TMP/err
  SPLIT_GREETER_DEST=$1 SPLIT_GREETER_STATE_DIR=$STATE "$SYNC" --self >"$out" 2>"$err"
}

run_self "$DEST"
grep -q 'login-screen artwork updated' "$TMP/out" || fail "self sync did not report success"
[ -d "$ROOT/theme" ] || fail "theme is not a directory after sync"
[ ! -L "$ROOT/theme" ] || fail "theme symlink was not replaced"
[ ! -L "$ROOT/wallpaper" ] || fail "wallpaper symlink was not replaced"
assert_file "$ROOT/theme/colors.toml"
assert_file "$ROOT/theme/shell.toml"
assert_file "$ROOT/wallpaper"
cmp -s "$STATE/theme/colors.toml" "$ROOT/theme/colors.toml" || fail "colors were not copied"
cmp -s "$STATE/theme/shell.toml" "$ROOT/theme/shell.toml" || fail "shell.toml was not copied"
cmp -s "$TMP/wall-one" "$ROOT/wallpaper" || fail "wallpaper was not copied"
assert_eq "$(stat -c %a "$ROOT/wallpaper")" "644" "wallpaper mode"

# An unchanged source must not churn the target (theme staging fires the path
# unit several times in a row).
inode_before=$(stat -c %i "$ROOT/wallpaper")
run_self "$DEST"
assert_eq "$(stat -c %i "$ROOT/wallpaper")" "$inode_before" "unchanged wallpaper was rewritten"

# A wallpaper retarget and an in-place palette rewrite both reach the copies.
ln -sfn "$TMP/wall-two" "$STATE/background"
printf 'colors-two\n' >"$STATE/theme/colors.toml"
run_self "$DEST"
cmp -s "$TMP/wall-two" "$ROOT/wallpaper" || fail "retargeted wallpaper was not copied"
cmp -s "$STATE/theme/colors.toml" "$ROOT/theme/colors.toml" || fail "rewritten palette was not copied"

# An account the installer never provisioned is warned about, not treated as a
# failed service.
MISSING=$TMP/missing
SPLIT_GREETER_DEST=$MISSING SPLIT_GREETER_STATE_DIR=$STATE "$SYNC" --self >"$TMP/out" 2>"$TMP/err"
grep -q "sudo split-greeter-sync $USER_NAME" "$TMP/err" || fail "missing artwork dir gave no actionable hint"
[ ! -e "$MISSING/users/$USER_NAME" ] || fail "missing artwork dir was created without root"

# A symlinked per-account directory must be refused: a user could otherwise
# redirect the account-owned sync outside the greeter tree.
BAD=$TMP/bad
mkdir -p "$BAD/users" "$TMP/elsewhere"
ln -s "$TMP/elsewhere" "$BAD/users/$USER_NAME"
if SPLIT_GREETER_DEST=$BAD SPLIT_GREETER_STATE_DIR=$STATE "$SYNC" --self >"$TMP/out" 2>"$TMP/err"; then
  fail "symlinked artwork directory was accepted"
fi
[ -z "$(find "$TMP/elsewhere" -mindepth 1 -print -quit)" ] || fail "symlinked artwork directory was written through"

# --self is an exact, account-only mode.
if "$SYNC" --self extra >"$TMP/out" 2>"$TMP/err"; then
  fail "--self accepted an extra argument"
fi

echo "ok - split-greeter-sync --self"
