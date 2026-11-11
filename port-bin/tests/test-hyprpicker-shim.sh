#!/bin/bash
# Contract test for the hyprpicker -> niri shim. A fake `niri` prints the line
# the real one prints (`Picked color: rgb(R, G, B)`, read off the string table of
# /usr/bin/niri 26.04), so nothing here touches the compositor or the clipboard.
#
# What is under test is the surface hyprpicker exposes to its callers, because
# the menu's Capture > Color entry and omarchy-capture-{qr,text,region} all reach
# for it and none of them expect niri's spelling:
#
#   -f hex|rgb|hsl|hsv|cmyk   the formats the picker documents
#   -o/--output-format        hyprpicker's {0}, {1}, ... substitution
#   -l/--lowercase-hex        hex case
#   -a/--autocopy             paste the result into the clipboard
#   -r alone                  a freeze request from capture-qr/text/region:
#                             holds the PID without opening niri's picker,
#                             which would otherwise eat slurp's first click
#   -r -a                     asks for a colour, so it still picks
#   -z -d -c -t -s -u         Hyprland-only flags; accepted and ignored
#   cancelled pick            exit 0 with no output, as hyprpicker does
#
#   ./tests/test-hyprpicker-shim.sh
#
# checks=N failures=M, exit 1 on any failure.

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SHIM=$(dirname "$HERE")/hyprpicker
[[ -f $SHIM ]] || { echo "no shim at $SHIM"; exit 1; }
python3 -c "import sys" 2>/dev/null || { echo "python3 required"; exit 1; }

checks=0
failures=0
check() { # name got want
  checks=$((checks + 1))
  if [[ "$2" == "$3" ]]; then
    printf '  %-52s ok\n' "$1"
  else
    printf '  %-52s FAIL (got %s, want %s)\n' "$1" "$2" "$3"
    failures=$((failures + 1))
  fi
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

stub="$work/bin"
mkdir -p "$stub"

# The picker itself, as niri prints it.
mk_niri() { # body
  cat >"$stub/niri" <<SH
#!/bin/bash
$1
SH
  chmod +x "$stub/niri"
}

# A clipboard that records what it was handed.
cat >"$stub/wl-copy" <<'SH'
#!/bin/bash
cat >"$WL_COPY_LOG"
SH
chmod +x "$stub/wl-copy"

run() { # args...
  PATH="$stub:$PATH" NIRI_SOCKET=/nonexistent "$SHIM" "$@" 2>/dev/null
}

mk_niri 'echo "Picked color: rgb(255, 128, 0)"'
export WL_COPY_LOG="$work/clip"

echo "== formats: niri's rgb triple becomes what hyprpicker documents"
check "hex is uppercase by default" "$(run -f hex -q)" "#FF8000"
check "-l lowercases the hex" "$(run -f hex -l -q)" "#ff8000"
check "rgb" "$(run -f rgb -q)" "rgb(255, 128, 0)"
check "hsl" "$(run -f hsl -q)" "hsl(30, 100%, 50%)"
check "hsv" "$(run -f hsv -q)" "hsv(30, 100%, 100%)"
check "cmyk" "$(run -f cmyk -q)" "cmyk(0%, 50%, 100%, 0%)"
check "--format= spelling works too" "$(run --format=rgb -q)" "rgb(255, 128, 0)"
check "an unknown format falls back to hex" "$(run -f nonsense -q)" "#FF8000"

echo
echo "== -o substitutes the format's own values, as hyprpicker does"
check "{0},{1},{2} over rgb" "$(run -f rgb -o '{0},{1},{2}' -q)" "255,128,0"
check "a template over hex gets the channels" \
  "$(run -f hex -o 'rgb({0}, {1}, {2})' -q)" "rgb(255, 128, 0)"

echo
echo "== -a copies the printed line, so callers find hex on the clipboard"
: >"$WL_COPY_LOG"
run -a -f hex -q >/dev/null
check "wl-copy received the colour" "$(cat "$WL_COPY_LOG")" "#FF8000"
: >"$WL_COPY_LOG"
run -a -f rgb -q >/dev/null
check "and it copies what it printed, not always hex" "$(cat "$WL_COPY_LOG")" "rgb(255, 128, 0)"

echo
echo "== -r alone is a freeze request: no picker, no colour"
cat >"$stub/niri" <<'SH'
#!/bin/bash
printf 'called\n' >"$PICK_LOG"
echo "Picked color: rgb(1, 2, 3)"
SH
chmod +x "$stub/niri"
export PICK_LOG="$work/pick"
: >"$PICK_LOG"
freeze_out="$work/freeze.out"
PATH="$stub:$PATH" NIRI_SOCKET=/nonexistent "$SHIM" -r -z -q >"$freeze_out" 2>/dev/null &
freeze_pid=$!
sleep .2
check "stays alive for the caller to kill" \
  "$(kill -0 "$freeze_pid" 2>/dev/null && echo alive)" "alive"
check "-r -z prints nothing" "$(<"$freeze_out")" ""
check "and does not open niri's picker" "$(<"$PICK_LOG")" ""
kill "$freeze_pid" 2>/dev/null
wait "$freeze_pid" 2>/dev/null || true
check "-z on its own still picks" "$(run -z -q)" "#010203"
check "-r -a still picks, because -a asks for a colour" "$(run -r -a -q)" "#010203"

echo
echo "== a cancelled pick is silent and successful, like hyprpicker"
mk_niri 'exit 0'
out=$(run -q)
check "no output" "$out" ""
check "exit 0" "$(run -q >/dev/null 2>&1; echo $?)" "0"

echo
echo "== niri's socket is discovered, not inherited"
# The shim must override a dead NIRI_SOCKET with the live socket in the runtime
# dir, the same rule Niri.qml uses (highest pid). Here a fake one names the
# socket it was given, so the check is about which path reached niri.
cat >"$stub/niri" <<'SH'
#!/bin/bash
printf '%s\n' "$NIRI_SOCKET" >"$SOCK_LOG"
echo "Picked color: rgb(0, 0, 0)"
SH
chmod +x "$stub/niri"
export SOCK_LOG="$work/sock"
runtime="$work/rt"
mkdir -p "$runtime"
: >"$runtime/niri.wayland-1.111.sock"
: >"$runtime/niri.wayland-1.999.sock"
PATH="$stub:$PATH" XDG_RUNTIME_DIR="$runtime" NIRI_SOCKET=/dead.sock \
  "$SHIM" -q >/dev/null 2>&1
check "the highest-pid socket wins" "$(cat "$SOCK_LOG")" "$runtime/niri.wayland-1.999.sock"

echo
echo "checks=$checks failures=$failures"
[[ $failures -eq 0 ]] || exit 1
