# Qt 6.12 and the frosted bar — postmortem

> **Genre**: postmortem (2026-10 to 2026-11). Conclusion: the earlier black-bar report did not reproduce under controlled tests; treat it as an unexplained one-off, not a property of Qt 6.12.
> Current state: Qt 6.12 is un-pinned and verified live. This file keeps the measurements, upgrade impact and rollback; it is not a current setup guide.

## Claim

This machine tracks Qt 6.12 as of 2026-11-11. The `IgnorePkg` that held it at 6.11.2 is removed. The earlier report claimed that `MultiEffect`'s blur became a no-op on 6.12, painting the bar, menu and panels as exactly `(0,0,0)` opaque black. **That does not reproduce.**

## Measurement

Measured on 6.12.0 (`qt6-base 6.12.0-4`, `qt6-declarative 6.12.0-4`), unpacked to a scratch tree and run with `qml6` so the live system stayed on 6.11.2 during the test:

| Probe | 6.11.2 | 6.12.0 |
|---|---|---|
| 8 px checkerboard under `blurMax: 32` (stddev, blur on / off) | 9.4 / 127.5 | 9.4 / 127.5 |
| Hard edge under `blur: 0.6` (mid-tone samples, on / off) | 64 / 0 | 64 / 0 |
| Same scene, 6.11.2 vs 6.12.0, pixel for pixel | — | **max diff 0** |

Blur is a no-op in the `--no-blur` controls (stddev 127.5), so the probes do discriminate. Both `opengl` and `vulkan` RHI backends behave the same. `QML_IMPORT_TRACE` confirms `QtQuick.Effects` resolves to the 6.12 plugin, not the system one, and `Qt.application.version` reports `6.12.0`.

Why the earlier conclusion was wrong is still unknown: the cached 6.12.0-2 / declarative-1 builds that were installed on 2026-10-10 render identically to the current ones. The 6.10 black-bar report was never reproduced under controlled conditions, so treat it as an unexplained one-off rather than a property of Qt 6.12.

## Live verification

Verified on the live session after upgrading: the bar is frosted (pixel samples across the strip show real gradients, no `(0,0,0)` block), the overview backdrop is blurred, and the menu panel shows the wallpaper through it. `omarchy-shell shell ping` answers `ok`.

## Upgrade impact

Lifting the pin was not a Qt-only transaction: 121 packages moved, including `linux` 7.2.14→7.2.15, `systemd` 262.1→262.2, `pacman` and `openssl` 3.6.5→4.1.0. The openssl soname bump is the risky part — 74 installed binaries linked `libcrypto.so.3`, which is now provided by the `openssl-3` compatibility package. Which binaries keep working is checked with `python3 -c "import cv2"` (opencv drives face unlock; a broken `cv2` shows up as a lock screen reporting `Error while authenticating: "System error" (code 4)`), plus smoke runs of `node`, `git`, `rsync`, `paru` and `cargo`.

`vtk` still fails to import: Arch builds it against 42 optional libraries it does not depend on (`libopenxr_loader`, `libgdal`, `libonnxruntime`, the OCCT and viskores sets). That count was 40 on the old 9.6.2-7 build, so it is a pre-existing packaging gap, not something this upgrade introduced. Nothing in Omarchy uses `vtk`; it is only there because `python-opencv` pulls it.

## Rollback

`pkexec snapper -c root undochange 2702..2708` restores the pre-upgrade snapshot, and the previous packages are still in `/var/cache/pacman/pkg`.
