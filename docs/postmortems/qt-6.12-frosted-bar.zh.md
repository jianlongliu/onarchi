# Qt 6.12 与磨砂 bar — 复盘

> **体裁**：复盘（2026-10 至 2026-11）。结论：旧报告「6.12 下 MultiEffect 模糊失效」在受控测试中未复现，按原因不明的偶发处理，而不是 Qt 6.12 的性质。
> 现状：Qt 6.12 已解钉并在真实会话验收。本文件保留测量、升级影响与回滚，不作为当前配置指南。

## 当时的结论

本机自 2026-11-11 起跟 Qt 6.12 走。按住 6.11.2 的 `IgnorePkg` 已删除。删之前这一节写的是「`MultiEffect` 的模糊在 6.12 下变成空操作，bar、菜单、面板会画成精确 `(0,0,0)` 的不透明黑」——**这条复现不出来。**

## 测量

在 6.12.0（`qt6-base 6.12.0-4`、`qt6-declarative 6.12.0-4`）上实测。测试时包解到临时树里、用 `qml6` 跑，系统本身仍是 6.11.2：

| 探针 | 6.11.2 | 6.12.0 |
|---|---|---|
| `blurMax: 32` 下的 8 px 棋盘（stddev，开 / 关模糊） | 9.4 / 127.5 | 9.4 / 127.5 |
| `blur: 0.6` 下的硬边（中间调采样数，开 / 关） | 64 / 0 | 64 / 0 |
| 同一场景，6.11.2 与 6.12.0 逐像素比 | — | **最大差异 0** |

`--no-blur` 对照组里模糊确实是空操作（stddev 127.5），所以探针有分辨力。`opengl` 和 `vulkan` 两种 RHI 后端结果一样。`QML_IMPORT_TRACE` 确认 `QtQuick.Effects` 解析到 6.12 自己的插件、不是系统那份，`Qt.application.version` 报 `6.12.0`。

旧结论错在哪，目前**不清楚**：缓存里 2026-10-10 当时装的 6.12.0-2 / declarative-1，渲染结果和现在这版逐像素相同。那次黑 bar 从来没在受控条件下复现过，所以应当当作一次原因不明的偶发，而不是 Qt 6.12 的性质。

## 真实会话验收

升级后在真实会话里复核过：bar 是磨砂的（沿 bar 采样有真实渐变，没有 `(0,0,0)` 色块）、总览背景有真模糊、菜单面板能透出背后的壁纸。`omarchy-shell shell ping` 返回 `ok`。

## 升级影响

解钉不是一次只管 Qt 的事务：一共动了 121 个包，包括 `linux` 7.2.14→7.2.15、`systemd` 262.1→262.2、`pacman` 和 `openssl` 3.6.5→4.1.0。风险大的是 openssl 的 soname 跳变——本机原有 74 个二进制链接 `libcrypto.so.3`，现在这个库由兼容包 `openssl-3` 提供。判据是 `python3 -c "import cv2"`（opencv 撑着人脸解锁；`cv2` 坏了的表现是锁屏报 `Error while authenticating: "System error" (code 4)`），外加 `node`、`git`、`rsync`、`paru`、`cargo` 各跑一次。

`vtk` 仍然 import 不了：Arch 编译它时链了 42 个并未声明为依赖的可选库（`libopenxr_loader`、`libgdal`、`libonnxruntime`，以及 OCCT 和 viskores 那两套）。旧版 9.6.2-7 是 40 个，所以这是本来就存在的打包缺口，不是本次升级引入的。Omarchy 里没有任何东西用 `vtk`，它只是被 `python-opencv` 连带装上的。

## 回滚

`pkexec snapper -c root undochange 2702..2708` 回到升级前快照，旧包也都还在 `/var/cache/pacman/pkg` 里。
