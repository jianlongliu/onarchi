#!/bin/sh
# Install the Omarchy greeter system-wide.
#
#   sudo ./install.sh
#
# Copies the shell to /etc/greetd/split-greeter (world readable: the greeter
# user has to read it) and installs /usr/local/bin/split-greeter as greetd's
# session command. It never touches /etc/greetd/config.toml: switching greetd
# over to this greeter is the one step that can lock you out, so it is printed
# at the end for you to do at a TTY.
#
# It also installs the per-account sync path unit. Theme and wallpaper changes
# then reach the login screen as each account, without another sudo.
set -eu

SRC=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEST=/etc/greetd/split-greeter

[ "$(id -u)" -eq 0 ] || {
  echo "run me with sudo" >&2
  exit 1
}

# 1. the shell itself
install -d -m 755 "$DEST" "$DEST/bridge"
for file in shell.qml Greetd.qml Users.qml UserPicker.qml SelfTest.qml niri.kdl; do
  install -m 644 "$SRC/$file" "$DEST/$file"
done

# Face unlock is only offered when a face tool is actually wired into PAM: with no
# howdy, telling the design a face is configured would make Enter a dead key.
if [ ! -e /lib/security/howdy/pam.py ]; then
  sed -i 's/^\( *GREETER_FACE *\)"1"/\1"0"/' "$DEST/niri.kdl"
  echo "install: howdy not found, disabled face unlock (GREETER_FACE 0)"
fi
for dir in designs Commons Ui; do
  install -d -m 755 "$DEST/$dir"
  for file in "$SRC/$dir"/*; do
    install -m 644 "$file" "$DEST/$dir/$(basename "$file")"
  done
done
install -m 755 "$SRC/bridge/greetd-bridge.py" "$DEST/bridge/greetd-bridge.py"
chmod -R a+rX "$DEST"

# 2. greetd's session command for the greeter
cat > /usr/local/bin/split-greeter <<'EOF'
#!/bin/sh
# greetd entry point for the Omarchy greeter: run the greeter's own niri
# instance. Login user, session and wallpaper are the GREETER_* values in
# /etc/greetd/split-greeter/niri.kdl.
#
# greetd gives this process the VT as stdout/stderr, and niri logs to stderr:
# those lines sit in the console buffer while niri owns the screen, then get
# dumped on it the moment the greeter exits -- the text that used to flash up
# between the password and the desktop (docs/lock.md §11.26). Paint the buffer
# black before niri can write to it, then keep our output in the log. Absolute
# path on purpose: the greeter user's HOME is "/".
log=/var/lib/greeter/greeter.log
printf '\033[2J\033[H' >&1 2>/dev/null
if : >>"$log" 2>/dev/null; then
  exec >>"$log" 2>&1
fi
exec niri -c /etc/greetd/split-greeter/niri.kdl
EOF
chmod 755 /usr/local/bin/split-greeter

# 2b. the session command itself (GREETER_SESSION in niri.kdl)
install -m 755 "$SRC/session.sh" "$DEST/session"

# 3. theme sync command
install -m 755 "$SRC/sync.sh" /usr/local/bin/split-greeter-sync

# 3b. the user-level sync trigger. Enabled system-wide; each account runs its
# own copy as itself, so a wallpaper change never needs root.
install -d -m 755 /etc/systemd/user /etc/systemd/user/default.target.wants
install -m 644 "$SRC/systemd/user/split-greeter-sync.path" /etc/systemd/user/
install -m 644 "$SRC/systemd/user/split-greeter-sync.service" /etc/systemd/user/
ln -sfn /etc/systemd/user/split-greeter-sync.path \
  /etc/systemd/user/default.target.wants/split-greeter-sync.path

# 4. the greeter user's state (its HOME is /var/lib/greeter)
install -d -m 755 -o greeter -g greeter /var/lib/greeter/.local/state/split-greeter
install -d -m 755 -o greeter -g greeter /var/lib/greeter/.local/state/omarchy/current/theme
install -d -m 755 -o greeter -g greeter /var/lib/greeter/.config/omarchy
install -d -m 755 -o greeter -g greeter /var/lib/greeter/users

# 4b. Hand each account its artwork directory. The account owns it so its
# user-level sync can update it without root; the greeter only needs to read.
for user in $(getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 { print $1 }'); do
  home=$(getent passwd "$user" | cut -d: -f6)
  [ -d "$home" ] || continue
  group=$(id -gn "$user" 2>/dev/null) || continue
  root="/var/lib/greeter/users/$user"
  if [ -L "$root" ]; then
    echo "install: refusing symlinked greeter artwork directory $root" >&2
    continue
  fi
  install -d -m 755 -o "$user" -g "$group" "$root"
  # Older installs left these files owned by greeter/root; the account must be
  # able to replace them for the user-level sync to work.
  chown -R -h "$user:$group" "$root" 2>/dev/null || true
done

# Start the path unit in the installing account's current session, when there
# is one. The next login picks it up anyway through its default.target link.
target_user=${SUDO_USER:-}
if [ -z "$target_user" ] && [ -n "${PKEXEC_UID:-}" ]; then
  target_user=$(getent passwd "$PKEXEC_UID" | cut -d: -f1 || true)
fi
if [ -n "$target_user" ]; then
  target_uid=$(id -u "$target_user" 2>/dev/null || true)
  if [ -n "$target_uid" ] && [ -d "/run/user/$target_uid" ] && command -v runuser >/dev/null 2>&1; then
    runuser -u "$target_user" -- env XDG_RUNTIME_DIR="/run/user/$target_uid" \
      systemctl --user daemon-reload || true
    runuser -u "$target_user" -- env XDG_RUNTIME_DIR="/run/user/$target_uid" \
      systemctl --user start split-greeter-sync.path || true
  fi
fi

cat <<'EOF'

Installed. What is left is the part that can lock you out of the machine:

  1. Keep a TTY open (Ctrl+Alt+F2) and log in there.
  2. Put this in /etc/greetd/config.toml:

         [default_session]
         command = "/usr/local/bin/split-greeter"
         user = "greeter"

     (dms-greeter may have left the previous value in
     /etc/greetd/config.toml.backup-* — keep it, it is the rollback.)
  3. Log out and log in. If the greeter does not come up, use the TTY and put
     the previous command back.
  4. Give the login screen the current theme and wallpaper once:

         sudo split-greeter-sync

     After that the login screen follows theme and wallpaper changes by
     itself: split-greeter-sync.path runs as each account, with no sudo.

  5. Only once logins work, and only if you want the DMS greeter gone:

         sudo pacman -D --asexplicit quickshell        # so -Rns cannot take quickshell with it
         sudo pacman -Rns greetd-dms-greeter-bin

Test the shell without logging out first:

    ./tests/smoke.sh
EOF
