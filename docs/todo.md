# 待办 — Omarchy on niri 卷（todo）

> **本次合并的优先级与状态校正**：见 [移植与合并进度报告](port-merge-status.md)。优先补齐统一 system 入口和内置工作区适配，再核对迁移；下表保留历史事项，官方源与工具依赖状态以进度报告为准。

> 文档只有一份：本文件（`docs/todo.md`）。本卷 2026-09-24 立，只记**还没做 / 等拍板**的事。
> **本卷不占全局编号**（`§N`、`§8 第 N 条` 那套号段），所以目录条目故意不带号 ——
> 免得污染"编号全局唯一、永不改号"的约定（脚本 `scripts/check-doc-refs.py` 会把 `- 33. xxx`
> 这类目录条目登记成"本卷定义了这个号"）。
> 做完一条就把结论落到对应卷、把这里那行删掉；**已完成的事不在这里留档**（查
> `docs/behavior.md` 覆盖账的 A / D 表与各卷正文）。
> 跨卷编号找不到在哪一卷时，查主文档 `docs/omarchy-on-niri-port.md` 的 §0 文档地图与 §8 映射表。

## 本卷目录

- 等用户拍板
- 2026-10-28 上游 FF 之后新增
- 本机卫生项

## 等用户拍板

| # | 事 | 要动什么 | 备注 |
|---|---|---|---|
| 1 | **合盖不挂起**（合盖 + 外屏时继续在外屏干活） | root：`/etc/systemd/logind.conf.d/lid-suspend.conf` 里 `HandleLidSwitchDocked=suspend` → `ignore`，再 `systemctl reload systemd-logind` | 备份路径与回退步骤见 `docs/shims.md` §4 的 clamshell 小节；**本机没外屏 ⇒ 改完也验不了真行为**，所以一直没动 |
| 2 | **窗口缝隙垫片的 niri 侧待重验** | `~/.config/niri/layout.kdl`（仓库副本 `niri-config/local/layout.kdl`）那条 `include optional=true "layout-no-gaps.kdl"` 从**尾部挪到顶部**，再量窗边像素 | 不挪大概率一直是空转（niri 同名键只认第一次定义）；**壳层那半是真的**（`getoption` 是垫片写死的映射）；依据与两份反证见 `docs/shims.md` §4 的「更正」 |
| 3 | **弹窗让位浮栏**（toast / 面板被浮动 bar 压住 `floatGap` 8） | 进 `niri.patch` 改 `shell/plugins/notifications/Delivery.js` 的 `barThickness`（只返回 bar 高度，**不含 `floatGap`**，而 `deckMargins` 只拿它 + `Style.gapsOut` 算边距）；`shell/Ui/KeyboardPanel.qml` 的 `gap` 同理 | **2026-10-30 复校**：`barClearance` 这个字段上游重构后已不存在，落点换成 `barThickness`/`deckMargins`，问题依旧成立（浮栏浮起时通知会盖住那 8px）。**做不成垫片**（`readonly` 计算值，外部无从覆盖）；按插件 README 用 root 手改会在 `omarchy update` 后静默丢掉 |
| 4 | **单窗口方形比例** | niri **没有 aspect 约束**，最近的是列宽（`default-column-width` / window-rule 定宽）⇒ 效果是"定宽" | 动手前先定口径：要**正方**，还是只要"别太宽" |
| 5 | **夜灯 / 色温的歧义** | 手动色温做不做（`wlsunset` **已在 `/usr/bin`**、全树无引用；`gammastep` 未装） | 现在的记法是"日落自动夜灯不做、**手动**色温以后再说"；若用户的意思是"色温整个不要"，把 `docs/behavior.md` A 表最后一行划掉。**做的话怎么落**：照 `docs/shims.md` 的垫片标准写——`wlsunset` 是唯一现成的 niri 可用件，`hyprsunset` 是 Hyprland 专有 |
| 6 | **浮动工具窗底色提亮**（`Ctrl+Shift+Esc` / `Mod+Y` / `Mod+E` 太黑） | 三选一：① 全局 —— `~/.config/ghostty/config` 在 include 之后写一行 `background`（取主题亮档 `#282a2f`，**连 Mod+Return 一起变亮**）+ nautilus 跟主题的 `~/.config/gtk-4.0/gtk.css`；② 只这两个键 —— 加 `XDG_CONFIG_HOME` 垫片指到另一份 ghostty 配置（btop 子进程会继承该变量）；③ 不动 | 漏项已补：三键 + nautilus 都补了 `opacity`（2026-09-25）。**alpha 实测对浮动窗只有 2–3/255 的效果**，主因是底色；机制与全套实测数据见 `docs/visual.md` §8.8 第 37 条（用户 2026-09-25「晚上看看文档」） |

| 7 | **把三条自定义时序塞进注入 EDID**（让它们成为内核原生模式，少依赖自定义 modeline） | 改 `/usr/lib/firmware/edid/CSO1411.bin`（先备份）→ `pkexec mkinitcpio -P` → 重启；试件已备好（`~/.local/state/omarchy/edid-trial/trial-2.bin` = 合法重排 + 三条 CTA DTD，本地校验通过） | 起因：用户以为"四档分辨率就在注入件里"，2026-09-26 复核**不成立**（件里只有 DTD1 4K + 一条被内核丢弃的 DTD2）。**收益有限** —— 档位靠 modeline 注入已经能上屏；且 EDID 是承重墙、验证必须走重启。`debugfs edid_override` 热验**不通**（eDP 不重探测，试完）。见 `local-overrides.md` §5 第 16 条 |
| 8 | **要不要真启用上游的"临时免密 sudo"**（`omarchy-sudo-passwordless [MINUTES]`，默认 15、上限 1440：往 `/etc/sudoers.d/99-omarchy-nopasswd-<uid>` 发布一条带 `NOTAFTER` 截止的规则，配 `systemd-run` 日历定时器到期自撤） | 启用需三样 **root 拥有、路径链不可被普通用户写** 的东西：`/etc/tmpfiles.d/omarchy-nopasswd-sudo.conf`（开机清残留授权）、`/usr/share/libalpm/hooks/05-omarchy-passwordless-revoke.hook`（内容要逐字节等于模板）、**真实文件**（非符号链接）`/usr/bin/omarchy-sudo-passwordless` | 代码 2026-09-27 已随上游合入工作树（见 `docs/upstream.md` §8.20），**机制未启用**。2026-10-30：`/usr/bin/omarchy-sudo-passwordless` 已按第三条前提装好（root 属主真实文件，`install.sh` 步骤 8 与 `omarchy-niri-repatch` 的漂移提示共同保活）——**这不是启用机制**，只是让 bar 指示器的 `--active` 轮询不再因文件缺失而每次记一条 "a password is required"。另外两项前提（tmpfiles 规则、libalpm hook）仍未安装，启用与否照旧待决。dev-link 形态与上游三条前提正面冲突（`omarchy_security_require_source_root` 只认 `$OMARCHY_PATH/bin/<cmd>` 或 `/usr/share/omarchy` + `/usr/bin/<cmd>`；`verify_root_path` 拒绝符号链接、逐级查 root 属主）。**别为了绕过而在用户可写路径放入口再配 pkexec 免密**：那等于把"无密码 root"送给任何能写该目录的进程 |

## 2026-10-28 上游 FF 之后新增

| # | 事 | 要动什么 | 备注 |
|---|---|---|---|
| 9 | **验证 `GDK_SCALE` 是否修好 GTK 应用的 DPI** | 已写入 `~/.config/niri/config.kdl` 的 `environment {}`：`GDK_SCALE "2"`。**必须重启会话**（reload 不生效） | 判据：nautilus 的字体与控件尺寸应与 bar 的 `base-size 14` 视觉一致。**不要加 `GDK_DPI_SCALE`**，会二次放大。若无效，下一步查 GTK4 是否走 `gdctl`/portal 而非环境变量 |
| 10 | **WPS 的剪贴板与 DPI** | 待定：给 WPS 强制 `QT_QPA_PLATFORM=wayland`，或维持 XWayland 另找缩放办法 | 现状：`app_id: wpsoffice`（XWayland），未设 `QT_QPA_PLATFORM`，`Xft.dpi` 是 192 与输出 2.0 一致，但 WPS 是否认它未测。剪贴板问题大概率出在 XWayland 中转 |
| 11 | **等 Qt 6.12 修好再回头拿那四个工具** | `omasnap` / `monologue` / `hype` / `signed` | 全部硬依赖 Qt 6.12；上游 `b83d3df08` 只修了 palette 语法，没有 `MultiEffect` 修复 ⇒ 解钉前先实测 6.12 的模糊是否仍失效。**`omasnap` 例外：它硬依赖 `hyprland`，在 niri 上解钉也用不了——用户 2026-10-30 已明确不做 `omasnap for niri`，截图走 grim + satty（见 `local-overrides.md` §8.1）** |

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
