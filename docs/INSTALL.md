# Manual install (no script)

> **简体中文 → [INSTALL.zh.md](INSTALL.zh.md)**

This is a reference for people and agents, not a guarantee: it has not been end-to-end tested on another machine. Review and adapt each step. The optional `install.sh` differs: it does not stage the overlay or plugins, install packages, configure backlight or PAM, or merge the niri config. It installs two user units and warns rather than failing if repatch fails. Both paths can overwrite existing files; back them up first.

Assumptions: you are on **Arch + niri**, logged in as your user, and **Omarchy is already installed** at
`~/.local/share/omarchy` (it has its own installer). You have this repo cloned somewhere; set `REPO`
below to that path.

```sh
REPO=/path/to/omarchy-on-niri     # <-- change me
```

---

## 1. System packages

```sh
sudo pacman -S --needed \
  git base-devel jq qt6-imageformats inotify-tools wl-clipboard \
  pipewire wireplumber playerctl ghostty
```

- **quickshell** (the QML engine the Omarchy shell runs on) — in the Arch repos on newer versions, else
  via AUR (`quickshell-git`). Install it or the shell won't render.
- **Power backend — pick one:**
  - `sudo pacman -S --needed power-profiles-daemon` (provides `powerprofilesctl`), **or**
  - `sudo pacman -S --needed tlp tlp-pd` (the porting machine uses this; `powerprofilesctl` is absent and
    `port-bin/omarchy-powerprofiles-*` falls back to TLP's D-Bus interface).
- **Optional:** `satty` (screenshot annotate), `swappy`, `grim slurp` (capture helpers).

`qt6-imageformats` is critical: without it Qt can't decode the `.webp` wallpapers and you get a black
background.

---

## 2. Put the port glue in `~/bin`

These are PATH-first overrides that translate the Hyprland-coupled pieces to niri. `~/bin` must come
**first** in `PATH` — that's set in the niri config env block (step 3).

```sh
mkdir -p ~/bin
for f in "$REPO"/port-bin/*; do [[ -f $f ]] || continue; install -m 0755 "$f" ~/bin/; done
```

This installs `hyprctl` (the shim — **critical**, ~50 omarchy scripts call it), `omarchy-niri-system`,
`omarchy-niri-apply-theme`, `omarchy-niri-repatch`, `omarchy-powerprofiles-list`,
`omarchy-powerprofiles-set`, and `materal-update` (only needed for a matugen-derived theme — see step 5).

---

## 3. Wire the compositor (`~/.config/niri/config.kdl`)

There are two ways in, and they are not equivalent:

- **`niri-config/local/*.kdl`** — the config this machine actually runs: seven files, ~910 lines
  (`config` + `input/monitor/layout/window-rules/effects/binds`), including the blur stack, the
  rounded corners, gaps, window rules and the deduplicated bind set. Read `niri-config/README.md`,
  copy them to `~/.config/niri/`, replace `/home/<user>` and fix the monitor block.
- **`niri-config/omarchy.kdl.template`** (below) — a 58-line *wiring snippet*: environment, the
  shell autostart and the Omarchy binds, meant to be merged into a config you already have. Enough
  to get the shell up; it does not carry the compositor-side tuning.

Back up first, then merge. Copy the relevant lines from generating the template by substituting your home
path in place of `__HOME__`:

```sh
mkdir -p ~/.config/niri ~/.local/state/backups/.config/niri
sed "s|__HOME__|$HOME|g" "$REPO/niri-config/omarchy.kdl.template" > ~/.config/niri/omarchy.kdl
cp ~/.config/niri/config.kdl ~/.local/state/backups/.config/niri/config.kdl.bak 2>/dev/null || true
```

Then edit `~/.config/niri/config.kdl`:

1. **Top level** — add the `environment { }` block and the `spawn-sh-at-startup` line:

   ```kdl
   environment {
       XDG_CURRENT_DESKTOP "niri"
       OMARCHY_PATH "/home/you/.local/share/omarchy"
       PATH "/home/you/bin:/home/you/.local/share/omarchy/bin:/home/you/.local/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"
   }

   spawn-sh-at-startup "omarchy-launch-shell"
   ```

   (Use your real path, not `/home/you`. The generated template launches bare `quickshell`; replace that line with the supervised launcher shown here, which logs and restarts the shell after a crash.)

2. **Inside your existing `binds { }` block** — paste the Omarchy bindings. The full list is in
   `~/.config/niri/omarchy.kdl` (generated above); the important ones:

   ```kdl
   Mod+Space         hotkey-overlay-title="Omarchy Menu" { spawn-sh "omarchy-menu toggle"; }
   Mod+K             hotkey-overlay-title="Keybindings"  { spawn-sh "omarchy-menu-keybindings"; }
   Mod+Ctrl+L        hotkey-overlay-title="Lock system"  { spawn-sh "omarchy-system-lock"; }
   Mod+Ctrl+P        hotkey-overlay-title="Power"        { spawn-sh "omarchy-shell shell toggle omarchy.power"; }
   Mod+Return        hotkey-overlay-title="Terminal"     { spawn "ghostty"; }
   XF86AudioRaiseVolume allow-when-locked=true hotkey-overlay-title="Volume up" { spawn-sh "omarchy-audio-output-volume raise"; }
   XF86MonBrightnessUp   allow-when-locked=true hotkey-overlay-title="Brightness up" { spawn-sh "omarchy-brightness-display +5%"; }
   ```

Validate:

```sh
niri validate -c ~/.config/niri/config.kdl
```

---

## 4. Omarchy config layer 1 (`~/.config/omarchy/shell.json`)

Only if it doesn't already exist (it holds your bar layout / idle timers):

```sh
mkdir -p ~/.config/omarchy
cp "$REPO/niri-config/shell.json" ~/.config/omarchy/shell.json
```

That file is **upstream's stock layout** (a neutral starting point). The porting machine's actual bar is
a different, opinionated one — `bar.id = omarchy.bar` (the floating implementation lives in
`shell/plugins/bar/` and ships with `niri.patch`, not as a plugin) plus four third-party widgets — and
lives in `local-config/omarchy/{shell.json,shell.toml,extensions/omarchy-menu.jsonc}`. Use that set only
if you are also installing those four plugins from the Omarchy plugin store; `shell.toml` (font size,
frosting alphas) is worth copying either way.

**4b. The machine's `~/.config` layer (`local-config/`)** — what this machine runs on top of the upstream
default tree, which upstream does not ship. Skip it and you get window decorations and no frosting:

```sh
mkdir -p ~/.config/ghostty
cp "$REPO/local-config/ghostty/config" ~/.config/ghostty/config      # back up yours first
mkdir -p ~/.config/systemd/user
cp "$REPO/local-config/systemd/user/materal-recolor."* ~/.config/systemd/user/
systemctl --user enable --now materal-recolor.path                   # needs ~/bin/materal-update
ghostty +validate-config                                             # silent means it parsed
mkdir -p ~/.config/omarchy
cp "$REPO/local-config/omarchy/shell.toml" ~/.config/omarchy/        # font size + frosting alphas
```

Three lines in `ghostty/config` are required by the port (`window-decoration = false`,
`background-opacity = 0.85`, **`background-blur-radius = 0`** — niri implements no KDE blur protocol, so the
frosting has to come from niri's own `background-effect`); colours come from the Omarchy theme
(`config-file = ?"~/.local/state/omarchy/current/theme/ghostty.conf"`, upstream's own line — the `?` means a
missing file is not an error), so no private theme file is involved. Fonts and keybindings are taste. Details
in `local-config/README.md`.

---

## 5. Update / theme hooks

```sh
mkdir -p ~/.config/omarchy/hooks/post-update.d ~/.config/omarchy/hooks/theme-set.d
install -m 0755 "$REPO"/hooks/post-update.d/* ~/.config/omarchy/hooks/post-update.d/
install -m 0755 "$REPO"/hooks/theme-set.d/*    ~/.config/omarchy/hooks/theme-set.d/
```

`post-update.d/10-niri-repatch` reapplies the overlay after each `omarchy update`;
`theme-set.d/10-niri-border` writes the focus-ring color on each style switch;
`theme-set.d/20-materal` re-derives the palette of a theme that carries a `matugen.toml` from the wallpaper
Omarchy currently has selected (needs `matugen`; themes without that file are untouched). The systemd pair
that also re-colours when the wallpaper changes (`materal-recolor.{path,service}`) is installed in step 4b
above (repo copy: `local-config/systemd/user/`).

---

The manual path also needs the state directory and, if wanted, the two session units installed by `install.sh` (back up existing units and links first):

```sh
mkdir -p ~/.local/state/omarchy/toggles/hypr ~/.config/systemd/user/graphical-session.target.wants
for unit in omarchy-picker-warmup.service omarchy-clamshell-watch.service; do
  install -m 0644 "$REPO/default/systemd/user/$unit" ~/.config/systemd/user/
  ln -sfn "$HOME/.config/systemd/user/$unit" "$HOME/.config/systemd/user/graphical-session.target.wants/$unit"
done
systemctl --user daemon-reload
```

These links depend on `graphical-session.target` being started by the session; verify that on the target machine.

## 6. Apply the port overlay to the Omarchy install

Put the overlay where repatch expects it, then apply (idempotent):

```sh
mkdir -p ~/.config/omarchy/niri-port
cp "$REPO"/niri-port/niri.patch "$REPO"/niri-port/Niri.qml ~/.config/omarchy/niri-port/
cp -a "$REPO"/niri-port/plugins ~/.config/omarchy/niri-port/
~/bin/omarchy-niri-repatch
```

Repatch skips outside `XDG_CURRENT_DESKTOP=niri` or without an Omarchy `.git` directory (both exit 0); inspect its output. Missing overlay exits 1; a patch conflict exits 2. It copies `Niri.qml` and plugins before checking for conflicts, so a conflict can leave those files changed. Back up existing files first. The plugin copy includes `blurwallpaper`; third-party `plugin-patches/` are separate and are not replayed automatically.

**Important:** keep the file changes in `~/.local/share/omarchy` **uncommitted**; committing them can prevent upstream fast-forward updates.
The upstream post-update hook can reapply `niri.patch`, but the port's `~/bin/omarchy-update` does not run that hook. After an update that changes the Omarchy tree, inspect the result and run `~/bin/omarchy-niri-repatch` manually if needed.

---

## 7. Backlight permissions (udev + video group)

So `brightnessctl` can write without root:

```sh
echo 'SUBSYSTEM=="backlight" GROUP="video" MODE="0664"' | sudo tee /etc/udev/rules.d/90-backlight.rules
sudo usermod -aG video "$USER"
sudo udevadm control --reload-rules && sudo udevadm trigger

# udev trigger only sends 'change' and won't reapply group/mode to the existing node,
# so backstop it now (applied properly at next boot):
node=$(echo /sys/class/backlight/*/brightness); sudo chgrp video "$node"; sudo chmod 0664 "$node"
```

---

## 8. Lock screen authentication (required, needs root)

The shell **refuses to lock** when `/etc/pam.d/omarchy-lock-password` is missing: the lock IPC answers
`missing-pam` and the screen stays unlocked. That is deliberate — a locked session with no working PAM has
no way back. The file comes from the **Omarchy installer** (`install/config/lockscreen-pam.sh` →
`omarchy-apply-lock`), which this manual install path skips, so run it yourself once:

```sh
pkexec ~/.local/share/omarchy/bin/omarchy-apply-lock     # or: sudo omarchy-apply-lock
omarchy-shell lock status | grep passwordPam             # want: "passwordPam":true
```

It is machine-wide, so one run covers every account on the box. Upstream's fingerprint probe greps
`fprintd-list` output for `finger`, which also matches "no fingers enrolled" — so it may write a useless
`/etc/pam.d/omarchy-lock-fingerprint`. If `fprintd-list "$USER"` reports no enrolled finger, `sudo rm` that
file. (`docs/lock.md` §8.18 has the full analysis, including why dms-greeter is not involved.)

---

## 9. Per-machine checks (must verify by hand)

These can't be auto-detected and will differ per box:

1. **Monitor output name** — the port/node config references `eDP-1` in places; run `niri msg outputs` and
   adjust to your output name.
2. **Backlight device** — `intel_backlight` on the porting box; confirm yours under `/sys/class/backlight/*`.
3. **Power backend** — power-profiles-daemon (`powerprofilesctl`) vs TLP (`tlp + tlp-pd`); this changes what
   `omarchy-powerprofiles-*` reports and what the Power menu shows.
4. **niri version** — tested on 26.04; keybind/overview behavior can differ across releases.
5. **Lock screen auth** — `omarchy-shell lock status` must report `"passwordPam":true` (step 8), else `Mod+Ctrl+L`
   does nothing at all.

---

## 10. Start and verify

Log out and back in — `spawn-sh-at-startup` starts the Quickshell shell. Then check:

```sh
niri msg layers                       # inspect Omarchy layers
omarchy-shell shell ping              # shell IPC responds?
omarchy-menu toggle                  # menu opens?
~/bin/omarchy-niri-system bogus      # usage, exit 2
```

System action wiring needs separate review: this snapshot's `bin/omarchy-system` does not call `omarchy-niri-system`. Do not test logout, reboot or shutdown until you have verified the installed entry point and are ready for the action.

Bar should render workspaces/clock/keyboard layout; `Mod+Space` opens the menu; media keys show an OSD;
the Power menu shows log out / reboot / shutdown.

See `omarchy-on-niri-port.md` for the full port notes and `README.md` for the dependency rationale.
