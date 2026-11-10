#!/bin/sh
# Give the greeter the artwork of every human account, so the login screen
# looks like the account that is selected (startup = the last account that
# logged in).
#
#   sudo split-greeter-sync                    # every human account, default = $SUDO_USER
#   sudo split-greeter-sync <主账户> <实验账户> # just these, first one is also the default
#   split-greeter-sync --self                  # this account only, no root (user unit)
#
# Layout under /var/lib/greeter:
#
#   .local/state/omarchy/current/theme/   shared default palette (also the path
#   wallpaper                             Color.qml falls back to)
#   .config/omarchy/shell.toml            machine-level look (fonts, spacing)
#   users/<user>/theme                    that account's palette
#   users/<user>/wallpaper                that account's wallpaper
#
# Accounts that never ran Omarchy get symlinks to the shared default instead.
# The greeter's HOME is /var/lib/greeter and /data is not readable by the
# greeter user, so artwork is copied, not linked, apart from those fallbacks.
#
# What follows the account: colours and wallpaper. What is machine-level and
# comes from the default account: everything else in shell.toml.
set -eu

dest=${SPLIT_GREETER_DEST:-/var/lib/greeter}
shared_theme="$dest/.local/state/omarchy/current/theme"

find_background() { # state dir — echoes the active wallpaper, if any
  for candidate in "$1/background" "$1/theme/backgrounds/background"; do
    if [ -e "$candidate" ]; then
      readlink -f "$candidate"
      return 0
    fi
  done
  return 1
}

copy_file() { # src target — atomic, skips an unchanged file
  src=$1
  target=$2
  if [ -f "$target" ] && cmp -s -- "$src" "$target"; then
    return 0
  fi
  tmp=$(mktemp "$target.XXXXXX") || return 1
  if ! cp -- "$src" "$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi
  chmod 644 "$tmp"
  mv -fT -- "$tmp" "$target"
}

self_sync() {
  user=$(id -un)
  state=${SPLIT_GREETER_STATE_DIR:-$HOME/.local/state/omarchy/current}
  root="$dest/users/$user"

  if [ "$(id -u)" -eq 0 ]; then
    echo "split-greeter-sync --self must run as the account, not root" >&2
    return 1
  fi
  if [ -L "$root" ]; then
    echo "split-greeter-sync: refusing symlinked artwork directory $root" >&2
    return 1
  fi
  if [ ! -d "$root" ]; then
    echo "split-greeter-sync: $root does not exist; run 'sudo split-greeter-sync $user' once" >&2
    return 0
  fi
  if [ "$(stat -c %u -- "$root")" -ne "$(id -u)" ]; then
    echo "split-greeter-sync: $root is not owned by $user; run 'sudo split-greeter-sync $user' once" >&2
    return 0
  fi

  # Keep the temporary copy private until the final chmod/rename.
  umask 027

  theme="$root/theme"
  if [ -d "$state/theme" ]; then
    if [ -L "$theme" ]; then
      rm -f -- "$theme"
    fi
    if [ -e "$theme" ] && [ ! -d "$theme" ]; then
      echo "split-greeter-sync: $theme is not a directory" >&2
      return 1
    fi
    if [ ! -d "$theme" ]; then
      mkdir -m 755 "$theme" || return 1
    fi
    if [ ! -w "$theme" ]; then
      echo "split-greeter-sync: $theme is not writable; run 'sudo split-greeter-sync $user' once" >&2
      return 1
    fi
    for name in colors.toml shell.toml; do
      if [ -f "$state/theme/$name" ] && [ -r "$state/theme/$name" ]; then
        copy_file "$state/theme/$name" "$theme/$name" || return 1
      fi
    done
  fi

  background=$(find_background "$state" || true)
  if [ -n "$background" ]; then
    if [ ! -f "$background" ]; then
      echo "split-greeter-sync: wallpaper is not a regular file: $background" >&2
      return 1
    fi
    copy_file "$background" "$root/wallpaper" || return 1
  else
    echo "split-greeter-sync: no current wallpaper; left the login-screen copy alone" >&2
  fi

  echo "$user: login-screen artwork updated"
}

if [ "${1:-}" = "--self" ]; then
  shift
  [ "$#" -eq 0 ] || {
    echo "Usage: split-greeter-sync --self" >&2
    exit 2
  }
  self_sync
  exit
fi

[ "$(id -u)" -eq 0 ] || exec sudo -- "$0" "$@"

install -d -m 755 -o greeter -g greeter "$shared_theme" "$dest/users" \
  "$dest/.config/omarchy" "$dest/.local/state/split-greeter"

sync_user() { # user — that account's palette + wallpaper
  user=$1
  home=$(getent passwd "$user" | cut -d: -f6)
  [ -n "$home" ] || {
    echo "no such user: $user" >&2
    return 1
  }
  group=$(id -gn "$user")
  state="$home/.local/state/omarchy/current"
  root="$dest/users/$user"
  if [ -L "$root" ]; then
    echo "refusing symlinked artwork directory: $root" >&2
    return 1
  fi
  install -d -m 755 -o "$user" -g "$group" "$root"
  # The account owns this tree so its user-level sync can update it without
  # root. Hand over anything an older install left behind as greeter/root.
  chown -R -h "$user:$group" "$root" 2>/dev/null || true

  what="default artwork only"
  copied=""
  if [ -d "$state/theme" ]; then
    rm -rf "$root/theme"
    install -d -m 755 -o "$user" -g "$group" "$root/theme"
    for name in colors.toml shell.toml; do
      if [ -f "$state/theme/$name" ] && [ -r "$state/theme/$name" ]; then
        install -m 644 "$state/theme/$name" "$root/theme/$name"
        chown "$user:$group" "$root/theme/$name"
        copied=yes
      fi
    done
    [ -n "$copied" ] && what="theme $(cat "$state/theme.name" 2>/dev/null || echo "$(basename "$(readlink -f "$state/theme")")")"
  fi
  [ -d "$root/theme" ] || ln -sfn "$shared_theme" "$root/theme"

  background=$(find_background "$state" || true)
  if [ -n "$background" ] && [ -f "$background" ]; then
    rm -f -- "$root/wallpaper"
    install -m 644 "$background" "$root/wallpaper"
    chown "$user:$group" "$root/wallpaper"
    what="$what + wallpaper"
  else
    ln -sfn "$dest/wallpaper" "$root/wallpaper"
  fi
  chown -h "$user:$group" "$root/theme" "$root/wallpaper" 2>/dev/null || true

  [ -e "$root/wallpaper" ] || what="$what (NO WALLPAPER FOUND)"
  echo "$user: $what"
}

set_default() { # user — what accounts without their own artwork fall back to
  home=$(getent passwd "$1" | cut -d: -f6)
  state="$home/.local/state/omarchy/current"
  for name in colors.toml shell.toml; do
    [ -r "$state/theme/$name" ] && install -m 644 "$state/theme/$name" "$shared_theme/$name"
  done
  background=$(find_background "$state" || true)
  [ -n "$background" ] && [ -f "$background" ] && install -m 644 "$background" "$dest/wallpaper"

  # Report the theme by name, not by the directory everyone calls "theme".
  name=$(cat "$state/theme.name" 2>/dev/null || basename "$(readlink -f "$state/theme")")
  [ -r "$home/.config/omarchy/shell.toml" ] && \
    install -m 644 "$home/.config/omarchy/shell.toml" "$dest/.config/omarchy/shell.toml"
  echo "shared default: $1"
}

if [ "$#" -gt 0 ]; then
  users=$*
  default=$1
else
  users=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 { print $1 }')
  # Who called us: sudo keeps SUDO_USER, pkexec passes PKEXEC_UID.
  default=${SUDO_USER:-}
  [ -z "$default" ] && [ -n "${PKEXEC_UID:-}" ] && \
    default=$(getent passwd "$PKEXEC_UID" | cut -d: -f1)
  [ -z "$default" ] && default=$(echo "$users" | head -1)
fi

for user in $users; do
  sync_user "$user" || true
done

[ -n "$default" ] && set_default "$default"

echo "done — the login screen picks these up on its next start"
