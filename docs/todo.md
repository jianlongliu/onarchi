# 待办 — Omarchy on niri 卷（todo）

> **本次合并的优先级与状态校正**：见 [已知问题](known-issues.md) 与 [README](../README.md)。优先补齐统一 system 入口和内置工作区适配，再核对迁移；下表保留历史事项。
> 当前仍成立的问题汇总见 [已知问题](known-issues.md)。

> 文档只有一份：本文件（`docs/todo.md`）。本卷 2026-09-24 立，只记**还没做 / 等拍板**的事。
> **本卷不占全局编号**（`§N`、`§8 第 N 条` 那套号段），所以目录条目故意不带号 ——
> 免得污染"编号全局唯一、永不改号"的约定（脚本 `scripts/check-doc-refs.py` 会把 `- 33. xxx`
> 这类目录条目登记成"本卷定义了这个号"）。
> 做完一条就把结论落到对应卷、把这里那行删掉；**已完成的事不在这里留档**（查
> `docs/behavior.md` 覆盖账的 A / D 表与各卷正文）。
> 跨卷编号找不到在哪一卷时，查主文档 `docs/omarchy-on-niri-port.md` 的 §0 文档地图与 §8 映射表。

> **体裁**：待办（读者：维护者）。**核对**：2026-11-19（删去已完成的临时免密 sudo、合盖 docked 与已拍板的浮动窗；夜灯改为等 niri；其余条目未逐项复测）。

## 本卷目录

- 等用户拍板
- 2026-10-28 上游 FF 之后新增
- 本机卫生项

## 等用户拍板

| # | 事 | 要动什么 | 备注 |
|---|---|---|---|
| 2 | **窗口缝隙垫片的 niri 侧待重验** | `~/.config/niri/layout.kdl`（仓库副本 `niri-config/local/layout.kdl`）那条 `include optional=true "layout-no-gaps.kdl"` 从**尾部挪到顶部**，再量窗边像素 | 不挪大概率一直是空转（niri 同名键只认第一次定义）；**壳层那半是真的**（`getoption` 是垫片写死的映射）；依据与两份反证见 `docs/shims.md` §4 的「更正」 |
| 4 | **单窗口方形比例** | niri **没有 aspect 约束**，最近的是列宽（`default-column-width` / window-rule 定宽）⇒ 效果是"定宽" | 动手前先定口径：要**正方**，还是只要"别太宽" |
| 5 | **夜灯 / 色温：等 niri 修 gamma** | 等 niri 上游支持可用的 `zwlr_gamma_control_v1` 实现；本地不做软件暖色遮罩 | **2026-11-19 实测**：niri 26.04 的 gamma-control 在 eDP-1 上直接 `failed()`；`wlsunset -t 4000 -T 4001` 起得来但报 `gamma control of output eDP-1 failed`，不生效。`gammastep` 未装；拍板等 niri 修 gamma，软件遮罩会污染截图且不是真色温 |
| 7 | **把三条自定义时序塞进注入 EDID**（让它们成为内核原生模式，少依赖自定义 modeline） | 改 `/usr/lib/firmware/edid/CSO1411.bin`（先备份）→ `pkexec mkinitcpio -P` → 重启；试件已备好（`~/.local/state/omarchy/edid-trial/trial-2.bin` = 合法重排 + 三条 CTA DTD，本地校验通过） | 起因：用户以为"四档分辨率就在注入件里"，2026-09-26 复核**不成立**（件里只有 DTD1 4K + 一条被内核丢弃的 DTD2）。**收益有限** —— 档位靠 modeline 注入已经能上屏；且 EDID 是承重墙、验证必须走重启。`debugfs edid_override` 热验**不通**（eDP 不重探测，试完）。见 `local-overrides.md` §5 第 16 条 |

## 2026-10-28 上游 FF 之后新增

| # | 事 | 要动什么 | 备注 |
|---|---|---|---|
| 9 | **验证 `GDK_SCALE` 是否修好 GTK 应用的 DPI** | 已写入 `~/.config/niri/config.kdl` 的 `environment {}`：`GDK_SCALE "2"`。**必须重启会话**（reload 不生效） | 判据：nautilus 的字体与控件尺寸应与 bar 的 `base-size 14` 视觉一致。**不要加 `GDK_DPI_SCALE`**，会二次放大。若无效，下一步查 GTK4 是否走 `gdctl`/portal 而非环境变量 |
| 10 | **WPS 的剪贴板与 DPI** | 待定：给 WPS 强制 `QT_QPA_PLATFORM=wayland`，或维持 XWayland 另找缩放办法 | 现状：`app_id: wpsoffice`（XWayland），未设 `QT_QPA_PLATFORM`，`Xft.dpi` 是 192 与输出 2.0 一致，但 WPS 是否认它未测。剪贴板问题大概率出在 XWayland 中转 |
| 11 | **重测 `monologue` / `hype` / `signed`** | 三件均未安装，重测需先装；`omasnap` 已明确不做 niri 版（硬依赖 `hyprland`，截图走 grim + satty） | Qt 6.12 已于 2026-11-11 解钉并真机验收（`997a5e2`），旧的 `Qt_6.12` 符号缺失前提已消失（见 `local-overrides.md` §8.1 末尾）；本轮未重装/未重测 |

## 本机卫生项

- **机器 ↔ 仓库剩下的 2 份差异**（2026-10-30 复核：`~/bin/omarchy-update` 与
  `omarchy-sleep-lock.service` 已收口一致）：`~/.config/systemd/user/` 下的
  `omarchy-crash-watch.service`、`omarchy-picker-warmup.service` 本机有、仓库里没有对应副本。
  要不要收进 `local-config/systemd/user/` 由用户定；收之前别当成仓库 bug 去"修"。

### 2026-11-04 工程审核遗留（已修的见各卷，下面只留未决）

- **`/etc/sudoers.d/` 与 `/etc/polkit-1/rules.d/` 无法非特权核对**：两个目录 root-only，`sudo -n` 要密码。
  所以 `omarchy-asdcontrol` 那条授权**是否真装在本机**仍未确认（仓库侧已删、`--overwrite` 已摘、
  迁移 `1793791066` 会删掉那条原样的授权）。要定论得跑一次 `pkexec ls -l /etc/sudoers.d /etc/polkit-1/rules.d`。
  ⚠ 顺带记一条**这次踩过的坑**：`pacman --overwrite` 只决定解包冲突怎么处理，**不删文件** ——
  「摘掉 `--overwrite` 就等于清理」是错的，清理得靠 migration（先例：`1791769486.sh` 清 USB/雷电授权）。
  同理 `49-tlp.rules` 是否在位、`omarchy-sudo-passwordless` 有无永久授权残留，都只是文档自述。
- **`omarchy-monitor-state` 面板开着时每 5 s 烧 443 ms CPU**（实测 user+sys，约 8.9% 单核持续）。
  拆开看：`hyprctl monitors all -j` 走 python 垫片 108 ms + `omarchy-brightness-display` 143 ms +
  `omarchy-hyprland-monitor-scaling` 131 ms。**这两个脚本都在 `niri.patch` 路径表里**，改它们必须同步
  重导出补丁（规程见 `docs/upstream.md` §8.7），所以没擅自动。可选方向：把 5 s 拉到 15–30 s，或让面板
  只在 `!stateProc.running` 时刷新（现状已有守卫，纯粹的固定开销）。
- **agents 的 900 s 轮询常开**：`shell/plugins/agents/Main.qml:148` 的 `running: true`，不开面板也跑，
  实测 `omarchy-agent-usage-update` 1.5–2.4 s / 25 个 collector。延后它有真实取舍 —— bar 图标靠
  `Panel.qml:212` 的 `alarming` 变红，而 `alarming` 由这些记录算出来；完全不跑会让提示失准。
  manifest 里的 `"activation": "on-demand"` 在 QML 侧没有实现（全树 grep 无命中），想做就照
  `shell/Ui/KeyboardPanel.qml` 的 `content` + `Loader.active` 那套改。
- **`shell/plugins/bar/Bar.qml:72-95` 是死代码**：`refreshGapsOut()` 全仓无调用者，`gapsOutProbe`
  也没有 `running` 绑定 ⇒ 零成本，但读代码的人会以为它在跑。删之前确认没人打算接上它。
- **`test/shell.d/nvidia-kms-hook-test.sh` 与 `nvidia-kms-migration-test.sh` 是两件事**：
  后者 2026-11-04 已补 `00-omarchy-hooks.conf` 夹具并转绿；前者测的是 drop-in 本身，没动过。
- **并行池里的偶发失败**：`preinstalls`、`agent-account` 在 `./test/all` 的 24 路并行下偶发失败，
  单独跑全绿（`preinstalls` 单跑 3/3）。属文件间竞争，不是缺陷；`agent-account-exec` 单跑也失败，
  已在 README 的已知失败里。
