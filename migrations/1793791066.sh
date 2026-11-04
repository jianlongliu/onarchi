echo "Retire the asdcontrol sudoers grant"

# /etc/sudoers.d/omarchy-asdcontrol shipped a passwordless grant for asdcontrol
# that upstream withdrew (df819a6f9, "Close three paths from an unprivileged
# session to root"). Omarchy no longer ships the file, so nothing removes it:
# removing the `--overwrite` that used to preserve it only stops recreating it.
# A machine that once had it keeps a `(ALL)` passwordless grant with no
# argument list — sudoers reads that as "any arguments" — until it is deleted.
#
# Only that grant is retired. A grant the user wrote themselves is left alone,
# as is a machine whose sudoers cannot be read without a password here (the
# login-time run and the next `omarchy update` retry it).
grant=/etc/sudoers.d/omarchy-asdcontrol
retired=$'%wheel ALL=(ALL) NOPASSWD: /usr/bin/asdcontrol'

[[ -e $grant ]] || exit 0

if [[ $(sudo cat "$grant" 2>/dev/null) != "$retired" ]]; then
  echo "$grant is not the grant Omarchy shipped; leaving it alone."
  exit 0
fi

sudo rm -f "$grant"

# visudo parses the whole set, not just this file: a drop-in with the wrong
# owner or mode would make every later sudo fail. A broken set was already
# broken, so say so instead of hiding it.
if ! sudo visudo -c >/dev/null 2>&1; then
  echo "WARNING: sudoers is invalid after removing $grant. Run 'sudo visudo -c' and fix it before your next sudo." >&2
fi
