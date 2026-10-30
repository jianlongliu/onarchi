# Onarchi - Omarchy on niri

> **English → [README.md](README.md)**

把 [basecamp/omarchy](https://github.com/basecamp/omarchy)（`quattro` / `4.0.0.alpha`）从 Hyprland 移植到
[niri](https://github.com/YaLTeR/niri) Wayland 合成器上。

这是供人和 agent 参考的安装资料，不保证安装成功；尚未在其他机器上端到端验证，执行前请逐步审阅并按机器调整。

本仓库包含移植后的 Omarchy 源码，以及让它能在 niri 上跑起来的"胶水"。它**不是独立的安装器**——假设你已经有一个
Arch + niri 登录会话、并且**已经装好 Omarchy**（或者你会先装 Omarchy）。它给你的是：

- 打了 QML/Niri 移植的 Omarchy 源码（`shell/Commons/Niri.qml`、打了 patch 的
  `Bar.qml` / `Workspaces.qml` / `Background.qml`）。
- `port-bin/` — 放进 `PATH` 最前面的覆盖脚本，把跟 Hyprland 耦合的部分翻译到 niri
  （其中 `hyprctl` 垫片是最关键的一个；另有 `uwsm-app`、`omarchy-update`、
  `omarchy-picker-warmup`、`omarchy-display-text-size`）。
- `default/systemd/user/` — 随移植分发的用户单元（选择器预热）。
- `niri-port/` — 幂等的覆盖层 patch（`niri.patch` + `Niri.qml`），能在 `omarchy update` 之后存续。
- `niri-config/local/` — **本机在用的 niri 配置**（七份 kdl：`config` + `input/monitor/layout/window-rules/effects/binds`，家目录参数化为 `/home/<user>`，见该目录 README）。
- `niri-config/omarchy.kdl.template` + `shell.json` — 另一条路的一体式接线（本机**没用**它）。
- `hooks/` — Omarchy update/theme 钩子，负责重放移植覆盖层。
- `install.sh` — 可选的一套便捷包装脚本。**不是推荐的路径**：手动步骤在 `docs/INSTALL.zh.md`，应按它逐条来做。
- `docs/INSTALL.zh.md` — 手动执行安装流程（依赖、文件放位、配置合并、覆盖层、背光）。
- `docs/omarchy-on-niri-port.md` — **主文档**（当前事实：硬性约束、架构、文件清单、niri 配置、
  部署、验证清单、环境信息）+ 模块映射表（**中文**）。
- `docs/visual.md` — 视觉调整卷：磨砂全栈、字号与 DPI、边框环、菜单底色、gaps、overview、
  主题取色、壁纸库、显示器缩放。
- `docs/behavior.md` — 功能调整卷：按键与去重、system 动作、电源与背光、screensaver、输入源、
  菜单行为、选择器性能与预热、耗电专项。
- `docs/plugins.md` — 插件卷：bar 插件层总览、逐插件魔改与运维。
- `docs/shims.md` — 垫片卷：`hyprctl`、`uwsm-app`、`omarchy-update`、`display-text-size`、
  `picker-warmup` 等 PATH-first 覆盖脚本。
- `docs/upstream.md` — 上游跟进卷：覆盖层重放、合并基线、上游小更新、发布流程。
- `docs/migration.md` — 账户迁移卷：实验账户 → 主账户的方案与执行清单（2026-09-19）。
- `docs/local-overrides.md` — 本机改动总账：相对仓库多出/改过的一切与回退方式。
- `docs/lock.md` — 锁屏与登录专卷：Split Greeter、`split-lock`、PAM 门禁、howdy 与头像，
  以及 greetd 只有一格 `configuring` 的陷阱。

各卷**沿用原章节编号**（`§8 第 N 条`、`§8.x`、`§11.x`），主文档里有「原编号 → 卷」的映射表；
文档只有一份正本，就在 `docs/` 里。

## 针对 ThinkPad X1 Carbon Gen 9 的定制与优化

本移植在 **ThinkPad X1 Carbon Gen 9**（Intel）上开发并调优，除通用移植外还带了这批机器专属的改动。

| 面向 | 本机具体做法 | 换机要动什么 |
|---|---|---|
| **红外人脸解锁** | `split-lock/ir-light` 点亮本机 Chicony IR 摄像头（`04f2:b6ea`）：写死 `open("/dev/video2")` + UVC 扩展单元 `unit=13 selector=14` | 改这两处；PAM 里是 `optional`，写错只是灯不亮，不会把人锁在外面 |
| **屏幕** | 五档分辨率/字号档位是按本机面板（ThinkPad `CSO1411`）调的 | 按自己的面板重算档位 |
| **触摸板 / 小红点** | `input.kdl` 开了 **`dwtp`**（用 TrackPoint 时忽略触控板输入）；Fn 触摸板开关改由写 `~/.config/niri/input-toggle-touchpad.kdl` 实现——本机 `thinkpad_acpi` 的 `hotkey_bios_enabled = 0`，Fn 键不发事件，而 niri 不认识 `KEY_TOUCHPAD_TOGGLE` | 没有小红点的机器上 `dwtp` 与这个开关都没意义，按需删掉 |
| **电源 / 电池** | 用 **TLP** 而非 `power-profiles-daemon`（垫片回落到 TLP 的 D-Bus 接口）；`/etc/tlp.conf` 把 `CPU_BOOST_ON_SAV` 改成 1（powersave 也允许睿频）；电源面板新增**充电上限**档位（ThinkPad 保养模式），经窄口径 polkit 规则 `etc/polkit-1/rules.d/49-tlp.rules` 写入 | 非 ThinkPad 固件没有这个充电档位；TLP 与睿频取向按自己口味 |
| **Intel 平台** | `install/hardware/intel/thermald.sh`、`default/systemd/system-sleep/keyboard-backlight`（挂起前后处理键盘背光） | 按平台取舍 |

仓库之外还有一层机器专属改动（`~/.config` 覆盖、`/etc/tlp.conf`、polkit 规则等），逐条清单与回退方式见 `docs/local-overrides.md`。

## 仓库结构

```
onarchi/
├── shell/        <- 移植后的 Omarchy Quickshell 源码（层1）
├── bin/          <- Omarchy 自己的脚本（上游原样，未改）
├── port-bin/     <- 移植胶水：hyprctl 垫片 + uwsm-app 垫片 + omarchy-update/picker-warmup/display-text-size 垫片
│                     + niri 的 system/power/theme/repatch 脚本
│                     install.sh 会把这些拷进 ~/bin（PATH 最前、挺过 `omarchy update`）
├── niri-port/    <- 覆盖层：niri.patch + Niri.qml（每次更新后重放）
│                     + plugin-patches/（第三方 bar 插件的本地魔改补丁，只能手工重放）
├── niri-config/  <- local/*.kdl（本机在用的 niri 配置）+ omarchy.kdl.template（另一条路）
│                     + shell.json 示例（Omarchy 配置层1）
├── local-config/ <- 本机 ~/.config 覆盖层：ghostty（关装饰 + 半透明 + 关自带模糊）
│                     + materal-recolor 单元；配色走 Omarchy 主题
│                     + materal-recolor.{path,service}；拷到 ~/.config/ 用，说明见该目录 README
├── config/       <- **上游 Omarchy 的默认配置树**（未改动，不是本机在用的那份）
├── plugins/      <- 自研插件源码（jianlongliu.arch-logo、jianlongliu.workspaces；split-lock 自成一档）
├── split-greeter/、split-lock/  <- 自研登录器与锁屏，各带 install.sh + tests/
├── default/      <- 本机随仓库走的"上游形状"默认件（systemd 用户单元、omarchy 菜单 jsonc）
├── hooks/        <- post-update.d/10-niri-repatch, theme-set.d/{10-niri-border,20-materal}
├── install.sh    <- 可选便捷包装脚本（推荐按 docs/INSTALL.zh.md 手动来）
├── docs/INSTALL.zh.md   <- 手动执行安装流程
├── docs/omarchy-on-niri-port.md <- 主文档（当前事实 + 模块映射表，中文）
├── docs/{visual,behavior,plugins,shims,upstream,migration,lock,local-overrides}.md <- 各模块卷（中文）
├── scripts/             <- kdl-sync.sh、local-files-sync.sh、check-doc-refs.py、menu-model-render.js
└── README.md / README.zh.md
```

## 依赖 / 前置条件

在目标 Arch 机器上装下面这些。以下全部已在移植机上实测使用（2026-09 / Arch rolling、systemd 261、niri 26.04）；
请在你自己机器上确认包的可得性。

### 必需 —— 外壳引擎
| 包 | 原因 |
|---|---|
| `niri` | 合成器本身。本移植目标是 niri（26.x）。 |
| `quickshell` | 渲染 Omarchy bar/菜单/OSD 的 layer-shell QML 引擎。Omarchy 的 shell 基于 Quickshell。用仓库包或 AUR 装。 |
| `git`, `base-devel` | 克隆/编译/安装 Omarchy（以及本移植）。 |

### 必需 —— Omarchy 运行时依赖
| 包 | 原因 |
|---|---|
| `jq` | 大量 `omarchy-*` 脚本和 `hyprctl` 垫片解析 JSON 用。 |
| `qt6-imageformats` | **关键。**让 Qt Quick 能解码 Omarchy 的 `.webp` 壁纸。没有它会得到一片黑壁纸。 |
| `inotify-tools` | 提供 `inotifywait`，由 Omarchy 插件监视器使用（`~/.config/omarchy/plugins`）。 |
| `wl-clipboard` | 提供 `wl-copy` / `wl-paste`，剪贴板管理器插件用。 |
| `brightnessctl` | 亮度媒体键 / OSD 的背光控制。 |

### 必需 —— 音频/媒体
| 包 | 原因 |
|---|---|
| `pipewire` + `wireplumber`（以及 `pipewire-pulse`） | 音频后端；`wpctl` 驱动音量 OSD。 |
| `playerctl` | 媒体传输键（播放/暂停/上一曲/下一曲）。 |
| `ghostty` | 默认终端（`Mod+Return` / `Mod+T`）。 |

### 电源后端（二选一）
| 包 | 原因 |
|---|---|
| `power-profiles-daemon` | 提供 `powerprofilesctl`。`port-bin/omarchy-powerprofiles-*` 优先用这个。 |
| **或** `tlp` + `tlp-pd` | 移植机用 TLP（无 `powerprofilesctl`）。垫片回退到 TLP 的 `net.hadess.PowerProfiles` D-Bus 接口。 |

### 可选
| 包 | 原因 |
|---|---|
| `satty` | 截图标注。 |
| `swappy` | 另一个截图编辑器。 |
| `grim` / `slurp` | niri 截图 / 区域捕获（niri 自带，但某些捕获助手会调这些）。 |

### 非包前置条件
- `/sys/class/backlight/` 下要有一个**背光设备**（如 `intel_backlight`）。`brightnessctl` 需要 `video` 组 /
  一条匹配的 udev 规则才能在无 root 时写入：
  - `/etc/udev/rules.d/90-backlight.rules`：`SUBSYSTEM=="backlight" GROUP="video" MODE="0664"`
  - `usermod -aG video <user>`
- 一个 **logind 会话**，polkit 的 `org.freedesktop.login1.reboot` / `power-off` 设为 `allow_active=yes`
  （Arch 上 systemd 默认如此），这样电源开关才能免密切换。

## 安装

手动、逐条执行的步骤在 **`docs/INSTALL.zh.md`**（依赖、`~/bin` 胶水、config.kdl 合并、覆盖层、背光、每机检查）。
这是手动参考路径，尚未在其他机器上端到端验证。

可选的 `install.sh` 会把 `port-bin/` 复制进 `~/bin`、把两个 bar 部件装进 `~/.config/omarchy/plugins/`、在没有 shell.json 时写入本移植的模板，并在覆盖层或 root 辅助件需要人工处理时给出提示。它不会改写已有 `config.kdl`、装包或修背光权限，且可能覆盖已有文件；运行前请读 `docs/INSTALL.zh.md`。

简版：

```sh
git clone https://github.com/jianlongliu/onarchi
cd onarchi
# 先装 README "Requirements" 里的包，然后执行：
./install.sh            # 可选；或按 docs/INSTALL.zh.md 逐步来
```

然后按指南合并配置：模板直接启动 Quickshell，推荐改用有监督的 `omarchy-launch-shell`。完成配置后注销再登录。

### 全新安装长什么样

`niri-config/shell.json` 是本移植的模板，默认就是截图里那套，而不是上游的默认样子：

| | 上游默认 | 本移植模板 |
|---|---|---|
| bar 表面 | `"background": "opaque"`，贴边铺满 | `"background": "glassy"` —— 磨砂，浮在壁纸之上 |
| 间隙 | 无 | `"floatGap": 8`，bar 与屏幕边缘脱开 |
| 工作区 | `omarchy.workspaces`（数字） | `jianlongliu.workspaces` —— 每个工作区一个实心点，当前那个拉长成胶囊 |
| 左端 | `omarchy.menu` | `jianlongliu.arch-logo` —— Arch 图标，点开同一个菜单 |

两个非上游部件都在本仓库 `plugins/` 下，`install.sh` 会把它们装进
`~/.config/omarchy/plugins/`。想调整就改 `~/.config/omarchy/shell.json`：磨砂是
`bar.background`（`glassy`、`none` 全透明、`opaque` 不透明），脱开距离是 `bar.floatGap`，
圆角与模糊本身由 `niri.patch` 里的 `shell/plugins/bar/Bar.qml` 提供。

磨砂本身是 `MultiEffect` 模糊，在 **Qt 6.12** 下会失效——bar 和菜单会渲染成不透明的黑卡片。
本机为此把 16 个 Qt 包钉在 6.11.2（见下文「Qt 钉在 6.11.2」）。若你的发行版是 6.12，
铺出来的会是同样的布局，但 bar 是实心而不是磨砂，直到上游修好 `MultiEffect`。

若你已经有 `shell.json`，`install.sh` 不会碰它（里面存着你的主题与字体选择）。要手工套用新外观，
就在它的 `bar` 块里设 `background`、`floatGap`、`id`，并把旧的 `centerAnchor` 迁到上游现在要求的
`centerBegin` / `center` / `centerEnd` 三段式。

## 每机调整（必须检查）

这些是硬件/OS 相关的，**无法可靠地自动检测**：

1. **显示器输出名** — 移植在几处用到 `eDP-1`；跑 `niri msg outputs` 后相应调整。
2. **背光设备** — 移植机上为 `intel_backlight`；查 `/sys/class/backlight/*` 确认你的。
3. **电源后端** — TLP 还是 power-profiles-daemon，会改变 `omarchy-powerprofiles-*` 报告的内容。
4. **niri 版本** — 在 26.04 上测试过；不同版本的键位/总览行为可能有差异。
5. **锁屏认证** — `/etc/pam.d/omarchy-lock-password` 来自 Omarchy 安装器，而本手动路径跳过了安装器。
   缺它时锁屏**完全锁不上**（`omarchy-shell lock status` → `"passwordPam":false`）；跑一次
   `pkexec ~/.local/share/omarchy/bin/omarchy-apply-lock`（INSTALL 第 8 步）。

总览的垫底无需调整：那一层由 niri 自己绘制，移植自带的 `blurwallpaper` 插件会在总览打开时铺一张强模糊壁纸（见移植笔记）。

## 上游同步状态

本移植当前跟到上游 `quattro` 的 **`bc220e70`**（2026-10-27）—— 2026-10-28 从 `60663faf` 快进，
共 846 个提交。当前 `niri.patch` 为 **40 文件 / 131 hunk / 3412 行**，md5 `a9f9e10716bde4ddf16dca5efb377dfc`（未跟踪的覆盖层文件另计）。

上游**仍然没有 niri 支持**：`bc220e70` 上 `grep -ri niri shell/ bin/` 零命中，而 Hyprland 耦合反而
加重（19 文件 54 处 → 26 文件 118 处）。下面每一条都是这个前提的产物。

### 合并后保留的东西

| 领域 | 状态 |
|---|---|
| 浮动 bar（间隙、圆角、霜化） | 接进上游新的 `barStrip`；`exclusiveZone` 现在算上 `floatGap`，窗口与条带之间不再多出一圈死桌面 |
| 显示器分辨率档位滑块 | 完全本地，上游没有对应物；合并零丢失（235 行） |
| 电池充电阈值（sysfs 优先） | 保留，并吸收上游改进：电池路径由 UPower 解析，不再用 `BAT*` 通配 |
| `Niri.qml` 合成器垫片 | 当前 364 行：`monitors`、`monitorFor`、`toplevels`、`refresh*`、`dispatch` |
| `OverlayWindow.qml` | 上游新增文件，所有 overlay 面板（菜单、OSD、剪贴板、图片选择器）都经过它。它读 `Hyprland.monitors`，在 niri 上恒为空 ⇒ `contentReady` 永远为假 ⇒ **每个面板都以 opacity 0 渲染**。已改指 `Niri` |
| 通知霜化 | 上游把通知表面改窄并丢了客户端区域，layer 规则只剩 `xray` ⇒ 完全无霜化。恢复为客户端 `Region` + 规则里 `blur true` |
| Apps 网格霜化 | 上游新增的 `omarchy.dock` 网格铺满屏幕、在 Hyprland 上靠 `ignore_alpha`。补了客户端区域 + `omarchy-dock-apps` 的 layer 规则 |
| bar 图标居中 | `OpticalGlyph` 报的是**旋转前**的墨迹中心，pocket 的标记展开时转 90° ⇒ 按没转的位置摆。另外 `BarIconButton` 新增 `contentOffsetY`，给墨迹远矮于行盒的字形用 |
| 截图 | 退回合并前的 satty 版 —— 见下节 |
| 系统动作（`omarchy-system`） | 上游统一入口的 logout 走 `uwsm stop`，niri 上没有 uwsm：所有窗口先关掉，再报「Logout failed」。现在 logout 改为请求合成器退出（`niri msg action quit --skip-confirmation`），并把 `NIRI_SOCKET`、`XDG_CURRENT_DESKTOP` 传进 detach 出去的 worker —— 缺任何一个，worker 里都选不到 niri 分支 |

### 放弃的东西，以及原因

| 项 | 原因 |
|---|---|
| `Style.qml` 里的 bar 尺寸 token | 上游已原生提供 `icon-font` / `icon-slot` / `icon-canvas` / `status-slot` / `notch-height` / `icon-size`，本地补丁是严格子集 |
| 霜化之外的 bar 装饰（投影、顶边高光、强制 12px 圆角） | 被上游自己的 bar 设计取代。接受覆盖 |
| OSD 的卡片化表面 | 上游把 OSD 迁到 `OverlayWindow`，而后者要求全屏表面；卡片化版本渲染出来是空白 |
| 经 `popupColumn` 的通知霜化 | 该元素上游已不存在，表面现在是窄条带 |
| `omasnap`、`monologue`、`hype`、`signed` | 四个都要 **Qt 6.12**，本机钉在 6.11（见下）。`omasnap` 还硬依赖 `hyprland`。同批只有 `disktree-bin` 能跑 |

### Qt 钉在 6.11.2

`/etc/pacman.conf` 的 `IgnorePkg` 里有 16 个包，全是 Qt 或 Qt 相关。理由就写在旁边：Qt 6.12 下
`MultiEffect` 的模糊变成空操作，bar 和菜单会渲染成不透明黑卡。上游唯一与 6.12 相关的提交
（`b83d3df08`）是 QML palette 语法兼容，**不是**渲染修复；`git log --grep` 也找不到 `MultiEffect`
相关工作。6.11.2 上实测基线：`MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 48 }` 有真实渐变
（150 个采样点里 104 个中间调）。解钉需要 16 个包一起动，换来的是四个都有替代品的工具。

### 未完成项

- **91 条迁移待跑**（共 211 条）。33 条要 root 且是机型专属（N1x / ASUS ProArt / aarch64 / Limine）；
  42 条动 Hyprland 或 uwsm。已跑 6 条面向用户的（bar 布局拆分、壁纸重编号、Fcitx 主题、Chromium
  覆盖滚动条）。其余在 `docs/upstream.md` §8.23 有分类账。
- **niri 上 `GDK_SCALE` 未设**。上游是 `omarchy-hyprland-monitor-scaling` 设的，而那个脚本只在
  Hyprland 下跑。于是 GTK 应用（nautilus）在 2.0 输出上按 1× 渲染。`~/.config/niri/config.kdl`
  的 `environment {}` 里已加 `GDK_SCALE "2"` —— **需要重启会话，reload 无效**，且尚未验证。
  **不要再加 `GDK_DPI_SCALE`**，那会二次放大。
- **WPS 的剪贴板与 DPI 未验证**。WPS 是 XWayland 客户端（`app_id: wpsoffice`），没设
  `QT_QPA_PLATFORM`，继承 `xwayland-satellite` 提供的东西；`Xft.dpi` 读到 192、与 2.0 输出一致，
  但 WPS 是否认它没测过。
- **Omarchy 源对升级的影响**。`[omarchy]` 排在 `[core]` 之前。`omarchy-nvim` 会替换 `neovim`、
  `omarchy-power-profiles-daemon` 会替换 `power-profiles-daemon`——两者目前都没装。

### 测试套件：剩下的都留给上游

`./test/shell` 跑 411 个文件。凡是移植自身造成的失败都已修好；下表是仍然失败的项，**故意不动**，
理由是不该在这个仓库里绕过上游的问题。

| 测试 | 为什么不在这里修 |
|---|---|
| `bar-startup-budget`、`lock-appear-budget`、`menu-open-budget`、`panel-open-budgets` | 它们靠 `hyprctl -j layers` 判断图层，而 niri 只报 namespace / level / output，不报 pid 和尺寸。`require_hyprland_layers` 在 niri 上跳过，Hyprland 上照跑 |
| `nvidia-kms-migration` | 模拟移植不涉及的 NVIDIA 硬件。其夹具从不写 `00-omarchy-hooks.conf`，条件判断读到空 `HOOKS`，于是在混合显卡机器上误判要重建 |
| `hardware-quirks` | 上游安装编排问题：`install/hardware/input-group.sh` 在 `bc220e70` 上没有任何脚本调用 |
| `background-intro-lifecycle` | `BackgroundIntro.qml` 与上游逐字节一致，是夹具自己的 retint 断言不过 |
| `agents-default-migration` | 期望的 bar 布局早于上游新增 `omarchy.keyboard-layout` |
| `fontconfig-cjk` | 依赖本机装的字体 |
| `remote-session-service` | 需要夹具造不出来的 SSH peer |

`sudoers` 失败是因为本机加了 `/etc/sudoers.d/omarchy-asdcontrol`，而该测试要求每个 drop-in 都必须登记。
这条授权是本机私有的，登记到上游测试表是错的，所以让它失败而不是静默掉。

`agent-account`、`monitor-modeless`、`passwordless-sudo-indicator`、`i18n-startup` 只在并行跑时失败，
单跑都过——文件级争用，不是真故障。`manifest-entrypoints` 同理，只是症状不同：断言全过，仅在清理阶段
撞上并发写入时非零退出（`rm: cannot remove ... Directory not empty`），单跑约四次复现一次。

`runtime-smoke` 的透明 bar 采样壁纸那条失败。我 `git stash` 清掉全部工作树改动后在 `HEAD` 上仍然失败，
所以不是移植改动造成的；根因尚未确定。

## 为什么它不是"一键保证"

本移植复用 Omarchy 自己的安装，只是通过 `hyprctl` 垫片和 `Niri.qml` Quickshell 模型把 Hyprland 换成 niri。
由于 `hyprctl` 光在 `bin/` 的 66 个命令里就出现约 200 次，`shell/` 下另有 11 个文件引用，垫片必须在
`PATH` 上外壳才能工作。`~/.local/share/omarchy` 里的文件是在
工作树里打 patch 并**保持未提交**，这样 `niri.patch` 覆盖层才能在每次 `omarchy update` 后重放——**不要**在
`~/.local/share/omarchy` 里面提交，否则快进更新会断。

完整的决策日志见 `docs/omarchy-on-niri-port.md`（中文）。
