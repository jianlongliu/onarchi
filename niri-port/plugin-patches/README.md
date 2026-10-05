# Plugin patches

Local edits to third-party Omarchy bar plugins, as `git diff` output against each plugin's own
upstream checkout. `~/.config/omarchy/plugins/<id>/` **is** a git clone of the plugin, so a patch
here is generated in place:

```sh
cd ~/.config/omarchy/plugins/<id>
git diff > ~/.config/omarchy/niri-port/plugin-patches/<id>.patch
git apply --reverse --check ~/.config/omarchy/niri-port/plugin-patches/<id>.patch   # must pass
```

| Patch | What it changes |
|---|---|
| `ronald.input-sources.patch` | `badgeOverrides` (Model.js) + `startupSource`/`applyStartupSource` (Panel.qml) so the first input source after a shell start is rime |
| `meviusisback.ai-subs.patch` | Font size from `caption` to `font.body` (five places), plus a leading pad and spacing so the chip lines up with the built-in widgets |
| `jianlongliu.workspaces.patch` | Dynamic workspace pill count (`1..N` by occupancy, never below 2) |

**`charlieras262.floating-bar.patch` retired 2026-10-04** — it used to carry the floating bar's niri
adaptation (rounded `blurRegion`, boot reveal, frost inset by 2px). The bar is no longer a plugin: those
files now live in `$OMARCHY_PATH/shell/plugins/bar/`, loaded as the built-in `omarchy.bar`, and the whole
change rides in `niri-port/niri.patch` (33 files / 106 hunks / 3098 lines, md5 `f6ef5a467795e2bd6f1ccf14161b185e`) —
`omarchy-niri-repatch` replays it, so no hand `git apply` is needed. The retired patch and the old plugin
directory are in `~/.local/state/backups/.config/omarchy/niri-port-plugin-patches-charlieras262.floating-bar.patch.bak-20261004-barmrege`
and `~/.local/state/backups/.config/omarchy/plugins/charlieras262.floating-bar.bak-20261004-barmrege`;
source, merge baseline and rollback: `docs/plugins.md` §5.4.

**Nothing replays these automatically.** `omarchy-niri-repatch` only covers `$OVL/niri.patch`,
`$OVL/Niri.qml` and whole-plugin copies under `$OVL/plugins/`; a plugin overwritten by
`omarchy plugin update` has to be patched by hand:

```sh
cd ~/.config/omarchy/plugins/<id>
git apply ~/Projects/omarchy-on-niri/niri-port/plugin-patches/<id>.patch
```

`jianlongliu.arch-logo`, `jianlongliu.workspaces` and `jianlongliu.split-lock` are ours, have no `.git`, and
`omarchy plugin update` does not touch them; their patches are made with
`diff -u --label a/<file> --label b/<file>` instead.

Machine-local history for these patches lives in the shared backup root
(`~/.local/state/backups/.config/omarchy/niri-port/plugin-patches/`, see `docs/local-overrides.md` §0.1)
and is deliberately not tracked here.
