# 已知问题与限制

> **体裁**：现状索引（读者：使用者 / 维护者）。**核对**：2026-11-27（更新运行树基线与待处理 migration 数，其余未逐项复测）。
> 只列当前仍成立或尚未验收的限制；已修项见各卷与 [README](../README.md)。
> 细节以「权威记录」为准，本文不重复推导过程。

## 影响日常使用

| 问题 | 影响 | 现状 / 绕过 | 权威记录 |
|---|---|---|---|
| `GDK_SCALE` 未验收 | GTK 应用（nautilus 等）可能仍按 1× 渲染 | `~/.config/niri/config.kdl` 已设 `GDK_SCALE "2"`，必须重启会话；效果未验收，别再加 `GDK_DPI_SCALE` | [README Open items](../README.md) · [todo](todo.md) #9 |
| WPS 缩放与剪贴板未验收 | XWayland 下 DPI 与跨端剪贴板可能异常 | WPS 未设 `QT_QPA_PLATFORM`；`Xft.dpi` 读 192，但 WPS 是否认它未测 | [README Open items](../README.md) · [todo](todo.md) #10 |
| 通知 / 面板被浮栏压住 8px | toast 与键盘面板和浮动 bar 重叠 | 需改 `niri.patch` 里的 `barThickness` / `deckMargins`，做不成垫片 | [todo](todo.md) #3 · [behavior 覆盖账](behavior.md) |
| quickshell DPR 崩溃（通知带图触发） | 缩放 / 全屏时 `physicalDpiChanged` 递归踩已释放 item，壳层 SIGABRT/SIGSEGV | 已临时绕过：`Toast.qml` 的 `layer.enabled` 去掉 `visible &&`（上游 PR #17015，修 #16937）；只削通知带图链，全屏等其它 layer teardown 仍可能触发 | [upstream §8.27](upstream.md) |
| 内置 `omarchy.workspaces` 不可通用 | 内置部件的点击 / 滚轮不发 niri action，工作区事件仍走 Hyprland 模型 | 当前桌面用 `jianlongliu.workspaces`；「看起来能用」不代表内置部件可用 | [README](../README.md) |
| 单窗口方形比例 | 只能定宽，做不到 1:1 | niri 没有 aspect 约束；要先定口径 | [todo](todo.md) #4 · [behavior 覆盖账](behavior.md) |
| 手动色温 / 夜灯 | 没有可用入口 | 2026-11-19 实测 niri 26.04 的 gamma-control 在 eDP-1 上失败（`wlsunset` 起得来但 `gamma control ... failed`）；拍板等 niri 修 gamma，不做软件暖色遮罩 | [todo](todo.md) #5 · [behavior 覆盖账](behavior.md) |
| 浮动工具窗底色偏黑 | `Ctrl+Shift+Esc` / `Mod+Y` / `Mod+E` 太黑 | 2026-11-19 拍板先不动；alpha 只值 2–3/255，主因是主题 ghostty 底色 `#19120c` | [visual](visual.md) §8.8 第 37 条 |

## 交付与验收边界

| 问题 | 影响 | 现状 / 绕过 | 权威记录 |
|---|---|---|---|
| 仓库源码快照未同步 | 仓库 `bin/`、`shell/`、`default/` 仍是 `bc220e70`，运行树已到 `2ebf5971a`（4.6.0-rc1 线） | 不要把「运行树已同步」读成「仓库源码已同步」；源码同步是独立动作 | [README](../README.md) |
| 226 个 migration 待处理 | 部分上游功能与修复未落地 | 4.6 合并后 `omarchy-migrate --pending` = 226；33 条需 root 且机型专属、42 条涉 Hyprland / uwsm 的旧分类尚未按新列表重算，逐条分类未收口 | [README Open items](../README.md) · [upstream](upstream.md) |
| 多屏 / 旋转 / 热插拔未验收 | 双屏同号工作区、输出旋转行为未知 | 单屏已验收；双屏与旋转需夹具或真机 | [README](../README.md) |
| 登录 / 锁屏 / 挂起 / 重启未复验 | 本轮源码同步后没有端到端证据 | 历史验收不能替代本次验收 | [README](../README.md) |
| 初次安装 / 覆盖层自动检查未闭环 | 干净机器安装可能缺步骤 | 正反向 `git apply --check` 已过，但缺完整安装路径闸门 | [README](../README.md) |
| 本机与仓库 2 份 systemd 单元差异 | 换机不可复现 | `omarchy-crash-watch.service`、`omarchy-picker-warmup.service` 本机有、仓库无 | [todo](todo.md) 本机卫生项 |
| 测试套件仍有上游遗留失败 / 跳过 | CI 与验收噪声 | 见 README 的「Test suite: what is left to upstream」 | [README](../README.md) |

## 维护项

| 问题 | 影响 | 现状 / 绕过 | 权威记录 |
|---|---|---|---|
| `omarchy-monitor-state` 面板每 5s 轮询 | 面板开着时约 8.9% 单核持续占用 | 面板不常开；改刷新间隔要同步重导 `niri.patch` | [todo](todo.md) 本机卫生项 |
| agents 900s 轮询常开 | 不开面板也跑，每轮 1.5–2.4s / 25 个 collector | 去掉会影响 bar 的 `alarming` 提示，取舍未定 | [todo](todo.md) 本机卫生项 |
| `shell/plugins/bar/Bar.qml:72-95` 是死代码 | 无运行时成本，但读代码的人会误以为它在跑 | 删之前确认没人准备接上 | [todo](todo.md) 本机卫生项 |

## 已澄清 / 不再成立

| 项 | 结论 | 记录 |
|---|---|---|
| 合盖 + 外屏仍会挂起 | 2026-11-19 已把 `HandleLidSwitchDocked` 改为 `ignore` 并 reload logind；普通合盖/外接电源仍 suspend。本机无外屏，真行为未验 | [behavior 覆盖账](behavior.md) · [shims §4](shims.md) |
| Qt 6.12 磨砂变黑 | 受控测试未复现；按原因不明的偶发放置，不再当作 6.12 的属性 | [README](../README.md) |
| `vtk` 导入失败 | Arch 打包缺可选依赖，非本移植引入；Omarchy 不用 vtk | — |
| Fathom Alt-Tab | 已退役，别再提议恢复 | [behavior 覆盖账](behavior.md) |

修好一项就从表里删掉，并把结论落到对应卷；已完成的事不留在这里。
