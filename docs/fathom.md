# Fathom Alt-Tab（实验）

基于深度的窗口切换器，键位 `Alt+Tab`。取自 [Fathom](https://github.com/mtolhuys/fathom)（MIT）的深度布局与"按时间换算深度"的算法，其余为 niri 重写。

**实验特性**：不理想时回退只需两步，见文末「回退」。

## 与 niri 内置切换器的取舍

niri 自带的 `recent-windows` 切换器用 `mapped.render_normal` 在合成器内部重画窗口的渲染元素（`src/ui/mru.rs:451`），同一渲染 pass 内完成，零额外开销，且支持"松开修饰键即切换"。

该接口是合成器内部的 Rust 调用，Wayland 客户端不可达。客户端能用的只有：

| 能力 | 协议 / 接口 | 本实现 |
|---|---|---|
| 窗口列表 | `niri msg -j windows` | 使用 |
| 单窗口离屏渲染 | `niri msg action screenshot-window --id N` | 使用（约 200 ms/窗口） |
| 焦点变化通知 | `niri msg -j event-stream` | 使用 |
| 松开 Alt 提交 | 无 | **不可实现**，改按 `Enter` |

## 架构

```
Fathom.qml          控制器：窗口列表、事件流、缓存抓图、键位、IPC
├─ FieldView.qml    布局：背景、深度堆叠、时间轴、caption、工作区图
│  ├─ Card.qml          单张卡片（缩略图 + 图标 + 标题 + 年龄）
│  ├─ SoundingLine.qml  左侧深度标尺（"测深线"）
│  └─ WorkspaceMap.qml  底部工作区图
├─ AppIcon.qml      应用图标，无图标时退化为字母方块
├─ Appearance.qml   读取 shell.toml 的 [fathom] 段
├─ Recency.js       窗口排序、深度换算、工作区分组（纯函数，node 可测）
├─ Layout.js        深度堆叠与时间轴的几何（纯函数）
└─ Palette.js       主题色推导（纯函数）
```

控制器的关键属性：

| 属性 | 含义 |
|---|---|
| `field` | 按新旧排序的窗口数组，`[0]` 最新 |
| `selectedIndex` | 当前选中项，`-1` 为未打开 |
| `openStep` | 打开时落在哪一项（`0` = 当前焦点，`1` = 上一个） |
| `previews` | `窗口 id → { stamp }`，标记已有缩略图 |
| `captureStamp` | 批次计数，改变时 Qt 重新解码同一路径 |

## 数据模型

深度按 Fathom 的公式，单位"fathom"：

```
depth = log2(1 + 距上次聚焦的秒数 / 30)，上限 8
```

分界：30 秒 = 1 fathom，2 分钟 ≈ 2.3，1 小时 ≈ 7，2 小时以上 = 8。

时间戳来自 niri 的 `focus_timestamp`，是**单调时钟**（开机起算），不是墙钟。因此年龄计算为「窗口时间戳与最新时间戳之差」，不能和 `Date.now()` 相减。

fathom 由 `focus_timestamp.secs/nanos` 换算；缺失时间戳的窗口（niri 自身 MRU 去抖导致）落在最深处，显示 `earlier`。

## 缩略图

### 抓取

`niri msg action screenshot-window --id N -d true --path <file>` 将单个窗口离屏渲染成 PNG，**跨 workspace 有效**（不受可见性限制），实测 3160×1864 RGBA，约 550 KB。

该命令有两个副作用：

1. 同时把图像写入剪贴板。批量抓取前用 `wl-paste` 保存到 `$XDG_RUNTIME_DIR/omarchy-fathom-clip`，抓完用 `wl-copy` 还原。
2. 命令返回时 PNG 可能尚未写完（niri 在工作线程落盘）。抓取后轮询文件大小直到连续两次一致，再交给 Qt 解码。

### 后台预抓

打开时才抓一批的成本是 **902 ms**，不可接受。改为后台预热：

- 监听 `event-stream` 的 `WindowFocusChanged`、`WindowsChanged`、`WindowOpenedOrChanged`、`WindowClosed`、`WorkspaceActivated`
- 事件触发后防抖 400 ms，避免快速切窗时连发批次
- 浮层打开期间跳过（已在展示，无需重抓）
- 启动时预热一次，保证首次 `Alt+Tab` 也有图

打开浮层只读取磁盘上的缓存文件，实测延迟降到 **66–79 ms**。

### 存储

| 项 | 值 |
|---|---|
| 位置 | `$XDG_RUNTIME_DIR/omarchy-fathom/`（tmpfs，不落盘） |
| 命名 | `<窗口 id>.png`，跨批次复用 |
| 单张 | 约 550 KB |
| 上限 | `previewLimit = 24` 张，约 13 MB |
| 清理 | 每次批次结束后删除已关闭窗口的文件 |

Qt 按 `Card.qml` 的 `sourceSize` 解码到卡片尺寸，不加载 3200px 原图，避免解码卡顿与显存浪费。

### 缓存失效

本地文件 URL 不支持 query string（`60.png?v=1` 会被当成文件名）。改用 URL fragment 携带批次戳（`60.png#2`），Qt 会剥离 fragment 但视其为不同 URL，从而重新解码。

## 磨砂

背景由 niri 磨砂，浮层自己不画背景图：卡片之外的区域透出模糊后的真实窗口。

实现分两处：

```kdl
// ~/.config/niri/effects.kdl
layer-rule {
    match namespace="^omarchy-fathom$"
    background-effect {
        blur true
        xray false
    }
}
```

QML 侧**不设置** `BackgroundEffect.blurRegion`。客户端区域方案实测会在卡片缩略图解码完成后失效（niri 重算区域时算成空，磨砂只维持一两秒），改用规则里的 `blur true` 后由 niri 自己按表面形状模糊，不再依赖区域同步。

前提是表面必须半透明，否则完全遮住背景效果：

| 层 | alpha | 说明 |
|---|---|---|
| veil | 0.15–0.25 | `Palette.js` 的 `DARK_VEIL`，极轻的压暗；再高就与 bar / 菜单的观感不一致 |
| 卡片填充 | 0.82 | `Card.qml` 的 `fillOpacity`，够实以保住标题可读 |

壁纸层已移除。Fathom 原版在 veil 下画当前壁纸，那层会盖住 niri 的磨砂，使背景完全不可见。

> `grim` 截图看不到磨砂：niri 的背景效果在合成阶段绘制，不在 `wlr-screencopy` 路径里。截图里背景呈纯黑，只能靠肉眼验证。

## 交互

| 键 | 动作 |
|---|---|
| `Alt+Tab` | 打开浮层并落上一个窗口 |
| `Alt+Shift+Tab` | 反向 |
| `Tab` / `↓` / `→` | 下一项 |
| `Shift+Tab` / `↑` / `←` | 上一项 |
| `Enter` | 聚焦选中窗口并关闭 |
| `Esc` | 关闭不切换 |

**松开 Alt 不提交。** 修饰键在浮层抢占键盘**之前**按下时，niri 不把其松开事件转发给浮层——已用真实 uinput 键盘在 niri 26.04 上验证：按下的键能收到，松开收不到。

替代保护：15 秒无输入自动关闭（`watchdog`），避免浮层卡住并持续占用键盘。

## 键位

```kdl
// ~/.config/niri/binds.kdl
Alt+Tab hotkey-overlay-title="Switch windows" { spawn-sh "omarchy-shell omarchy.fathom next"; }
Alt+Shift+Tab hotkey-overlay-title="Switch windows (back)" { spawn-sh "omarchy-shell omarchy.fathom previous"; }
```

niri 自带的 `recent-windows` 块中的 `Alt+Tab` / `Alt+Shift+Tab` 需删除，否则重复绑定；`Alt+grave` 按应用切换保留。

## IPC

```sh
omarchy-shell omarchy.fathom next        # 打开并落上一个窗口
omarchy-shell omarchy.fathom previous    # 打开并落在最旧一个
omarchy-shell omarchy.fathom open        # 打开且停在当前窗口
omarchy-shell omarchy.fathom commit      # 聚焦并关闭
omarchy-shell omarchy.fathom cancel      # 关闭
omarchy-shell omarchy.fathom state       # opened/windows/selected/workspaces/previewsDone
omarchy-shell omarchy.fathom field       # 每个窗口的 app/title/age/depth/预览 URL
```

## 测试

```sh
bash test/shell.d/fathom-test.sh
```

覆盖 `Recency.js`（排序、深度、选中回绕、工作区分组）与 `Layout.js`（深度堆叠几何）。两者都是纯函数，node 直接加载。

## 已知限制

- **缩略图非实时**：只在焦点变化时刷新，窗口内容自身变化（视频播放、页面滚动）不会更新
- **无松手提交**：见上文，需 `Enter`
- **深处卡片**：`Layout.VISIBLE_STEPS = 5` 之后淡出；实际超过 4 个窗口时后几张卡片缩略图可能未解码
- 浮动窗口与平铺窗口一视同仁，没有特殊标记

## 现状：暂停（2026-11-04）

工程中止，等 niri 发布自带窗口级捕获协议的稳定版本后继续。

### 为什么要停

缩略图目前走 `niri msg action screenshot-window`。这条路径有三个无法在下游解决的问题：

- **每次焦点变化重抓全部窗口**，一次切换约 1 秒；
- niri **无条件把每张截图写入剪贴板**，`-d` 只控制是否落盘，没有跳过剪贴板的开关；
- niri 每写一张截图就发一条 `Screenshot captured` 通知（`src/utils/mod.rs` 的 `show_screenshot_notification`），抓 5 个窗口弹 5 条，且没有配置项可关。

拦截 D-Bus 通知会连带吞掉用户自己截图的提示，不可接受。

### 正确的替代路径

标准协议链：

```
ext-foreign-toplevel-list
  → ext-foreign-toplevel-image-capture-source   ← niri 缺
  → ext-image-copy-capture                       ← niri 26.04 缺
  → Quickshell 接收
  → Fathom Card
```

核实结果：

| 端 | 状态 |
|---|---|
| niri 26.04（已装） | 只有 `zwlr-screencopy`（整屏），无 `ext-image-copy-capture` |
| niri 上游 PR #4599 | 未合并，改动 6 文件 / +536 −217，Cargo 依赖零变动 |
| Quickshell 0.3.1（已装） | 有 `ext-image-copy-capture` 与 output 级 source，缺 toplevel 级 source |

PR #4599 建立在 `main` 已有的 `src/handlers/image_copy_capture.rs` 上，而 26.04 没有该文件，因此无法直接套用，需要连带移植整套 handler。

### 继续时的起手式

1. 确认 niri 是否已合并 PR #4599 并发布；
2. 升级 niri，确认 `ext_image_copy_capture` 与 `ext_foreign_toplevel_image_capture_source_manager` 出现在 `strings /usr/bin/niri`；
3. 补 Quickshell 客户端一半；
4. 用独立客户端验证「跨工作区可捕获、不碰剪贴板、不弹通知、关闭窗口释放资源」，再动 Fathom；
5. 替换捕获后端后，删除全部截图与剪贴板相关代码。

**不要**用调低截图频率、屏蔽通知、调整 opacity 之类的方式"继续优化"——这些都是在错误的数据通道上打补丁。

### 当前代码状态

截图后端在 `experiment/fathom-alttab` 分支，包含未验证的增量捕获逻辑。卡片预览跨开关缓存已实测有效。其余部分（布局、动画、磨砂、图标、键位）工作正常，可独立使用。

## 回退

全部改动只在分支 `experiment/fathom-alttab` 上，主分支 `quattro` 不含任何 fathom 文件。

```sh
# 1. 键位交还 niri：删掉 binds.kdl 里那两行 Alt+Tab，并恢复 config.kdl 的
#    recent-windows 块（把 Alt+Tab / Alt+Shift+Tab 放回去）：
#        Alt+Tab         { next-window scope="output"; }
#        Alt+Shift+Tab   { previous-window scope="output"; }
#    两份正本都在 niri-config/local/ 下，与 ~/.config/niri/ 保持同步。

# 2. 卸掉装到运行树的插件（它不在 git 里，git switch 不会替你删）
rm -rf ~/.local/share/omarchy/shell/plugins/fathom
rm -rf "$XDG_RUNTIME_DIR/omarchy-fathom" "$XDG_RUNTIME_DIR/omarchy-fathom-clip"
omarchy-restart-shell

# 3. 切换分支
cd ~/Projects/onarchi && git switch quattro
```

只做第 1、2 步而不切分支也可以：插件目录一删，`omarchy.fathom` 的 IPC target 就消失，浮层不再可能打开；这两个键位届时指向不存在的 target，`omarchy-shell` 静默失败（`-q` 语义），等于没有绑定。但要让 `Alt+Tab` 真正可用，仍须恢复 `recent-windows` 块。

`~/.local/share/omarchy` 是独立的工作树（不是本仓库的检出），`omarchy-niri-repatch` 会按 `niri-port/niri.patch` 重放 `shell/` 下的改动；fathom 不在该补丁中，所以上游更新不会把它重新装回来。
