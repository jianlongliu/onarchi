# Onarchi - Omarchy on niri

> **简体中文 → [README.zh.md](README.zh.md)**

Port of [basecamp/omarchy](https://github.com/basecamp/omarchy) (`quattro` / `4.0.0.alpha`) to the
[niri](https://github.com/YaLTeR/niri) Wayland compositor, instead of Hyprland.

This is an installation reference for people and agents, not a success guarantee. It has not been end-to-end tested on another machine; inspect and adapt each step before running it.

This repo contains the ported Omarchy source plus the glue that makes it run on niri. It is **not a
standalone installer** — it assumes a working Arch + niri login session and an existing Omarchy install
(or that you install Omarchy first). What it gives you is:

- The Omarchy source with the QML/Niri port applied (`shell/Commons/Niri.qml`, patched
  `Bar.qml` / `Workspaces.qml` / `Background.qml`).
- `port-bin/` — the PATH-first override scripts that translate the Hyprland-coupled bits to niri
  (the `hyprctl` shim is the critical one; `uwsm-app` rescues every `uwsm-app -- <cmd>` call site
  in Omarchy's `bin/`, which is a uwsm-session facility a niri session does not have; `omarchy-update`
  replaces the upstream updater, which assumes the Omarchy package repo is configured; plus the
  picker warm-up and the display text-size shim).
- `niri-port/` — the idempotent overlay patch (`niri.patch` + `Niri.qml`) that survives `omarchy update`,
  plus `plugin-patches/` (local edits to third-party bar plugins, applied by hand — nothing replays them).
- `niri-config/local/` — the niri config this machine actually runs (seven `*.kdl` files: `config` plus
  `input/monitor/layout/window-rules/effects/binds`; the home directory is a `/home/<user>` placeholder —
  see the README in that directory).
- `niri-config/omarchy.kdl.template` + `shell.json` — the other route: one merged file rendered by
  `install.sh` (this machine never used it).
- `hooks/` — Omarchy update/theme hooks that reapply the port.
- `default/systemd/user/omarchy-picker-warmup.service` — the session-scoped picker warm-up unit
  (`install.sh` installs and enables it; disable with `toggles/picker-warmup-off`).
- `install.sh` — optional convenience wrapper. The manual steps are in
  `docs/INSTALL.md` and should be followed by hand.
- `docs/INSTALL.md` — the hand-run install procedure (deps, file placement, config merge, overlay, backlight).
- `docs/omarchy-on-niri-port.md` — the main volume (current facts: constraints, architecture, file
  inventory, niri config, deployment, verification, environment) plus the module map.
- `docs/visual.md` — visual adjustments volume (frosted blur stack, text size/DPI, focus ring
  gradient, menu backdrop, gaps, overview, theming, wallpaper library, scaling).
- `docs/behavior.md` — behavior volume (keys and dedup, system actions, power/backlight,
  screensaver, input sources, menu behavior, picker performance and warm-up, battery work).
- `docs/plugins.md` — the plugin volume (bar plugin layer, per-plugin local patches and ops).
- `docs/shims.md` — the shim volume (`hyprctl`, `uwsm-app`, `omarchy-update`, `display-text-size`,
  `picker-warmup`, … the PATH-first overrides).
- `docs/upstream.md` — keeping up with upstream (overlay replay, merge baselines, release flow).
- `docs/migration.md` — the account migration volume (experiment account → main account, 2026-09-19).
- `docs/local-overrides.md` — what this machine has beyond the repo, and how to roll it back.
- `docs/lock.md` — the lock screen and login volume: the Split Greeter, `split-lock`, the PAM gate,
  howdy and avatars, and greetd's single `configuring` slot.

The volumes keep the original section numbering (`§8 第 N 条`, `§8.x`, `§11.x`); the main volume
holds a map from every moved section to its volume. The volumes have exactly one home: `docs/` itself.

## Hardware notes — ThinkPad X1 Carbon Gen 9

This port was developed on and tuned for a **ThinkPad X1 Carbon Gen 9** (Intel). On top of the generic
port, the repo carries machine-specific customisations:

| Area | What it does here | What to change on other hardware |
|---|---|---|
| **IR face unlock** | `split-lock/ir-light` lights this machine's Chicony IR camera (`04f2:b6ea`): it hardcodes `open("/dev/video2")` and the UVC extension unit `unit=13 selector=14` | Those two values. The PAM hook is `optional`, so a wrong device only means the light never comes on |
| **Display** | The five resolution / text-size tiers are tuned for this panel (ThinkPad `CSO1411`) | Recompute the tiers for your own panel |
| **Touchpad / TrackPoint** | `input.kdl` enables **`dwtp`** (disable-while-trackpointing); the Fn touchpad toggle is implemented by writing `~/.config/niri/input-toggle-touchpad.kdl`, because this machine's `thinkpad_acpi` reports `hotkey_bios_enabled = 0` (no Fn event) and niri has no `KEY_TOUCHPAD_TOGGLE` | `dwtp` and that toggle are meaningless without a TrackPoint — drop them |
| **Power / battery** | TLP instead of `power-profiles-daemon` (the shims fall back to TLP's D-Bus interface); `/etc/tlp.conf` sets `CPU_BOOST_ON_SAV = 1` (turbo allowed in powersave too); the power panel gains a **charge-limit** tier (ThinkPad conservation mode), written through the narrow polkit rule `etc/polkit-1/rules.d/49-tlp.rules` | No charge-limit tier without ThinkPad firmware support; TLP and boost settings per taste |
| **Intel platform** | `install/hardware/intel/thermald.sh`; `default/systemd/system-sleep/keyboard-backlight` (keyboard backlight across suspend) | Pick per platform |

Beyond the repo there is a layer of machine-only changes (`~/.config` overrides, `/etc/tlp.conf`, polkit
rules, …): `docs/local-overrides.md` lists them item by item with the rollback for each.

## Repository layout

```
onarchi/
├── shell/        <- ported Omarchy Quickshell source (Layer 1)
├── bin/          <- Omarchy's own scripts (unchanged upstream)
├── port-bin/     <- port glue: hyprctl shim + niri system/power/theme/repatch scripts
│                     install.sh copies these into ~/bin (PATH-first, survives `omarchy update`)
├── niri-port/    <- overlay: niri.patch + Niri.qml (reapplied after each update)
├── niri-config/  <- local/*.kdl (what this machine runs) + omarchy.kdl.template (the other route)
│                     + shell.json template (floating frosted bar, capsule dots)
├── local-config/ <- the machine's ~/.config layer: ghostty (decorations off, opacity, blur off)
│                     + the materal-recolor units; colours come from the Omarchy theme
│                     + materal-recolor.service/.path; copy over your own, see its README
├── config/       <- upstream Omarchy's default config tree, untouched (NOT this machine's)
├── plugins/      <- self-written plugin sources (jianlongliu.arch-logo, jianlongliu.workspaces;
│                     split-lock has its own dir)
├── split-greeter/, split-lock/  <- self-written greeter and lock screen, each with install.sh + tests
├── default/      <- upstream-shaped defaults this machine ships (systemd/user units, omarchy menu jsonc)
├── hooks/        <- post-update.d/10-niri-repatch, theme-set.d/{10-niri-border,20-materal}
├── install.sh    <- optional convenience wrapper (prefer the manual steps in docs/INSTALL.md)
├── docs/INSTALL.md  <- hand-run install procedure
├── docs/omarchy-on-niri-port.md <- main volume: current facts + module map
├── docs/{visual,behavior,plugins,shims,upstream,migration,lock,local-overrides}.md <- module volumes
├── scripts/     <- kdl-sync.sh, local-files-sync.sh, check-doc-refs.py, menu-model-render.js
└── README.md
```

## Requirements / dependencies

Install these on the target Arch machine. Everything below was verified in use on the porting machine
(September 2026 / Arch rolling, systemd 261, niri 26.04); verify package availability on your box.

### Required — the shell engine
| Package | Why |
|---|---|
| `niri` | The compositor itself. This port targets niri (26.x). |
| `quickshell` | The layer-shell QML engine that renders the Omarchy bar/menus/OSD. Omarchy's shell is Quickshell-based. Install via repo/AUR as appropriate. |
| `git`, `base-devel` | To clone/build/install Omarchy (and this port). |

### Required — Omarchy runtime helpers
| Package | Why |
|---|---|
| `jq` | Used by many `omarchy-*` scripts and the `hyprctl` shim to parse JSON. |
| `qt6-imageformats` | **Critical.** Lets Qt Quick decode the `.webp` Omarchy wallpapers. Without it you get a black wallpaper. |
| `inotify-tools` | Provides `inotifywait`, used by the Omarchy plugin watcher (`~/.config/omarchy/plugins`). |
| `wl-clipboard` | Provides `wl-copy` / `wl-paste`, used by the clipboard manager plugin. |
| `brightnessctl` | Backlight control for the brightness media keys / OSD. |

### Required — audio/media
| Package | Why |
|---|---|
| `pipewire` + `wireplumber` (and `pipewire-pulse`) | Audio backend; `wpctl` drives the volume OSD. |
| `playerctl` | Media transport keys (play/pause/next/prev). |
| `ghostty` | The default terminal (`Mod+Return` / `Mod+T`). |

### Power backend (one of these)
| Package | Why |
|---|---|
| `power-profiles-daemon` | Provides `powerprofilesctl`. `port-bin/omarchy-powerprofiles-*` prefers this. |
| **or** `tlp` + `tlp-pd` | The porting machine uses TLP (`powerprofilesctl` absent). The shim falls back to TLP's `net.hadess.PowerProfiles` D-Bus interface. |

### Optional
| Package | Why |
|---|---|
| `satty` | Screenshot annotation. |
| `swappy` | Alternate screenshot editor. |
| `grim` / `slurp` | Niri screenshots / region capture (niri provides its own, but some capture helpers call these). |

### Non-package prerequisites
- A **backlight device** under `/sys/class/backlight/` (e.g. `intel_backlight`). `brightnessctl` needs the
  `video` group / a matching udev rule to write without root:
  - `/etc/udev/rules.d/90-backlight.rules`: `SUBSYSTEM=="backlight" GROUP="video" MODE="0664"`
  - `usermod -aG video <user>`
- A **logind session** with polkit `org.freedesktop.login1.reboot` / `power-off` set to `allow_active=yes`
  (systemd defaults to this on Arch) so the system switch works passwordless.

## Install

The manual, hand-run procedure is in **`docs/INSTALL.md`** (deps, `~/bin` glue, config.kdl merge, overlay,
backlight, per-machine checks). It is a manual reference, not a tested installation guarantee.

There is also an optional `install.sh` bootstrap. It copies `port-bin/` into `~/bin`, installs the two bar
widgets under `~/.config/omarchy/plugins/`, writes the port's shell.json template when you have none, and
warns when the overlay or a root helper needs a hand. It does not rewrite an existing `config.kdl`, install
packages or fix backlight permissions, and it can overwrite files; consult `docs/INSTALL.md` before running it.

Short version:

```sh
git clone https://github.com/jianlongliu/onarchi
cd onarchi
# install the packages in README "Requirements", then run:
./install.sh            # optional; or follow docs/INSTALL.md step by step
```

Then merge the config as described in the guide; the template starts bare Quickshell, whereas the recommended `omarchy-launch-shell` supervises it. Log out and back in after completing the setup.

### What a fresh install looks like

`niri-config/shell.json` is the port's template, and it ships the look in the
screenshots rather than upstream's default:

| | Upstream default | This port's template |
|---|---|---|
| Bar surface | `"background": "opaque"`, edge to edge | `"background": "glassy"` — frosted, floating over the wallpaper |
| Gap | none | `"floatGap": 8`, so the bar detaches from the screen edge |
| Workspaces | `omarchy.workspaces` (numbers) | `jianlongliu.workspaces` — one dot per workspace, the focused one stretched into a capsule |
| Left end | `omarchy.menu` | `jianlongliu.arch-logo` — Arch mark that opens the same menu |

Both non-upstream widgets live in `plugins/` here, and `install.sh` copies them
into `~/.config/omarchy/plugins/`. To change any of it, edit
`~/.config/omarchy/shell.json`: the frosted look is `bar.background` (`glassy`,
`none` for fully clear, `opaque`), the detach is `bar.floatGap`, and the round
corners plus the blur itself ride in `niri.patch`'s `shell/plugins/bar/Bar.qml`.

If you already have a `shell.json`, `install.sh` leaves it alone — it holds your
theme and font choices. To adopt the new look by hand, set `background`,
`floatGap` and `id` in its `bar` block, and move any old `centerAnchor` into the
`centerBegin` / `center` / `centerEnd` split upstream now expects.

## Per-machine adjustments (must check)

These are hardware/OS specific and **cannot be auto-detected reliably**:

1. **Monitor output name** — port uses `eDP-1` in a few places; run `niri msg outputs` and adjust.
2. **Backlight device** — `intel_backlight` on the porting box; check `/sys/class/backlight/*`.
3. **Power backend** — TLP vs power-profiles-daemon changes what `omarchy-powerprofiles-*` reports.
4. **niri version** — tested on 26.04; keybind/overview behavior may differ across releases.
5. **Lock screen auth** — `/etc/pam.d/omarchy-lock-password` comes from the Omarchy installer, which this
   manual path skips. Without it the lock screen refuses to lock at all (`omarchy-shell lock status` →
   `"passwordPam":false`); run `pkexec ~/.local/share/omarchy/bin/omarchy-apply-lock` once (INSTALL step 8).

The overview backdrop needs no adjustment: niri draws that layer itself, so the ported `blurwallpaper` shell plugin paints a blurred wallpaper while the overview is open (see the port notes).

## Upstream sync status

The port currently tracks upstream `quattro` at **`bc220e70`** (2026-10-27), fast-forwarded from
`60663faf` on 2026-10-28 — 846 commits. The current `niri.patch` has **40 files / 131 hunks / 3412
lines**, md5 `a9f9e10716bde4ddf16dca5efb377dfc` (untracked overlay files are separate).

Upstream still has **no niri support**: `grep -ri niri shell/ bin/` returns nothing at `bc220e70`,
while Hyprland coupling grew (19 files / 54 sites → 26 files / 118 sites). Everything below exists
because of that.

### Carried through the merge

| Area | State |
|---|---|
| Floating bar (float gap, rounded corners, frosted blur) | Grafted onto upstream's new `barStrip`. `exclusiveZone` now includes `floatGap`, so windows no longer sit a band of dead desktop below the strip |
| Monitor resolution tier slider | Entirely local; upstream has no equivalent. Merged without loss (235 lines) |
| Battery charge threshold (sysfs-first) | Kept, plus upstream's improvement: it resolves the battery through UPower instead of a `BAT*` glob |
| `Niri.qml` compositor shim | Currently 364 lines: `monitors`, `monitorFor`, `toplevels`, `refresh*`, `dispatch` |
| `OverlayWindow.qml` | New upstream file, all overlay panels (menu, OSD, clipboard, image picker) go through it. It read `Hyprland.monitors`, which is always empty on niri, so `contentReady` never became true and every panel rendered at opacity 0 — patched to `Niri` |
| Toast frost | Upstream narrowed the notification surface and dropped the client blur region; the layer rule carried only `xray`, so nothing was frosted. Restored as a client-side `Region` + `blur true` in the rule |
| Apps grid frost | Upstream's new `omarchy.dock` grid spans the screen and relies on Hyprland's `ignore_alpha`. Given a client region plus an `omarchy-dock-apps` layer rule |
| Bar icon centring | `OpticalGlyph` reported the ink centre before rotation, so the pocket's mark (which turns 90° when it opens) was placed as if it had not. `BarIconButton` also gained `contentOffsetY` for glyphs whose ink is far shorter than their line box |
| Screenshot | Reverted to the pre-merge satty version — see "Dropped" |
| System actions (`omarchy-system`) | Upstream's unified entry ran `uwsm stop` for logout, which does not exist on niri: every window closed and then the menu reported "Logout failed". `logout` now asks the compositor to quit (`niri msg action quit --skip-confirmation`), and the detached worker is given `NIRI_SOCKET` and `XDG_CURRENT_DESKTOP` — without both it cannot pick the niri branch |

### Dropped, and why

| Thing | Reason |
|---|---|
| Bar size tokens in `Style.qml` | Upstream now ships `icon-font` / `icon-slot` / `icon-canvas` / `status-slot` / `notch-height` / `icon-size` natively; the local patch was a strict subset |
| Bar decoration beyond frost (shadow, top highlight, forced 12 px radius) | Superseded by upstream's own bar design. Accepted the overwrite |
| OSD card surface | Upstream moved OSD onto `OverlayWindow`, which requires a full-screen surface; the card-sized variant rendered nothing |
| Notification blur via `popupColumn` | That element no longer exists upstream; the surface is a narrow strip now |
| `omasnap`, `monologue`, `hype`, `signed` | All four need **Qt 6.12**; this machine pins Qt 6.11 (see below). `omasnap` additionally hard-depends on `hyprland`. Only `disktree-bin` from that batch runs |

### Test suite: what is left to upstream

`./test/shell` runs 411 files. Everything that failed because of the port itself is fixed; the
open failures below are upstream's, and are left alone deliberately rather than patched around here.

| Test | Why it is not fixed here |
|---|---|
| `bar-startup-budget`, `lock-appear-budget`, `menu-open-budget`, `panel-open-budgets` | They judge a layer surface through `hyprctl -j layers`, and niri reports a layer's namespace, level and output but not its pid or geometry. `require_hyprland_layers` skips them on niri; they still run under Hyprland |
| `nvidia-kms-migration` | Simulates NVIDIA hardware the port does not touch. Its fixture never writes `00-omarchy-hooks.conf`, so the conditional reads an empty `HOOKS` and decides to rebuild on a hybrid machine |
| `hardware-quirks` | Upstream's install orchestration: `install/hardware/input-group.sh` is dispatched by nothing, at `bc220e70` |
| `background-intro-lifecycle` | `BackgroundIntro.qml` is byte-identical to upstream and the fixture's own retint assertion fails |
| `agents-default-migration` | The expected bar layout predates upstream shipping `omarchy.keyboard-layout` |
| `fontconfig-cjk` | Depends on the fonts installed on the machine |
| `remote-session-service` | Needs an SSH peer the fixture cannot manufacture |

`sudoers` fails because this machine adds `/etc/sudoers.d/omarchy-asdcontrol`, which that test
requires every drop-in to register. The grant is machine-local, so registering it upstream would be
wrong; it is left failing rather than silenced.

`agent-account`, `monitor-modeless`, `passwordless-sudo-indicator` and `i18n-startup` fail only
under the parallel runner and pass on their own — file-level contention, not a real failure.
`manifest-entrypoints` does the same, though its symptom is different: its assertions all pass and
the file exits non-zero only when its cleanup races a concurrent write (`rm: cannot remove ...
Directory not empty`). That reproduces roughly once in four standalone runs, so it is the same
contention rather than a distinct defect.

`runtime-smoke` fails its transparent-bar wallpaper sample. It fails at `HEAD` with all working-tree
changes stashed, so it is not caused by port work, and the root cause is not yet known.

### Qt stays pinned at 6.11.2

`/etc/pacman.conf` holds 16 packages in `IgnorePkg`, all of them Qt or Qt-linked. The reason is
recorded there: under Qt 6.12, `MultiEffect` blur becomes a no-op, so the bar and menu render as
opaque black cards. Upstream's only 6.12-related commit (`b83d3df08`) is a QML palette-syntax fix,
not a rendering repair, and `git log --grep` finds no `MultiEffect` work. Verified on 6.11.2 as a
baseline: `MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 48 }` produces a real gradient
(104 of 150 sampled points mid-tone). Lifting the pin needs all 16 packages moved together; the
payoff is four tools that all have working substitutes.

### Open items

- **91 migrations pending** out of 211. 33 need root and are machine-specific (N1x / ASUS ProArt /
  aarch64 / Limine); 42 touch Hyprland or uwsm. Six user-facing ones have been run (bar layout split,
  wallpaper renumbering, Fcitx theming, Chromium overlay scrollbars). The rest are tracked in
  `docs/upstream.md` §8.23.
- **`GDK_SCALE` is unset on niri.** `omarchy-hyprland-monitor-scaling` is what sets it upstream, and
  that script only runs under Hyprland. GTK apps (nautilus) therefore render at 1× against a 2.0
  output. `~/.config/niri/config.kdl` now carries `GDK_SCALE "2"` in its `environment {}` block —
  **this requires a session restart, not a reload**, and has not been verified yet. Do not also set
  `GDK_DPI_SCALE`; that would scale twice.
- **WPS clipboard and DPI** are unverified. WPS is an XWayland client (`app_id: wpsoffice`) with no
  `QT_QPA_PLATFORM` set, so it inherits whatever `xwayland-satellite` provides; `Xft.dpi` reads 192,
  matching the 2.0 output, but whether WPS honours it is untested.
- **Effect of the Omarchy repo on upgrades.** `[omarchy]` sits ahead of `[core]` in `pacman.conf`.
  `omarchy-nvim` will replace `neovim` and `omarchy-power-profiles-daemon` will replace
  `power-profiles-daemon` if those are ever installed; neither is present today.

## Why it's not a single-click guarantee

The port reuses Omarchy's own install but swaps Hyprland for niri via the `hyprctl` shim and a
`Niri.qml` Quickshell model. Because `hyprctl` appears about 200 times across 66 commands in `bin/` alone, plus 11 files under
`shell/`, the shim must be on `PATH` for the shell to function at all. Files in `~/.local/share/omarchy` are patched in the working tree and
kept **uncommitted** so the `niri.patch` overlay can be reapplied after each `omarchy update` — do not
commit inside `~/.local/share/omarchy` or the fast-forward update will break.

See `docs/omarchy-on-niri-port.md` for the full decision log.
