# 手动安装（不用脚本）

> **English → [INSTALL.md](INSTALL.md)**

这是供人和 agent 参考的步骤，不保证成功：尚未在其他机器上端到端验证。执行前逐条审阅并按机器调整。可选的 `install.sh` 行为不同：它不放置覆盖层和插件、不安装包、不配置背光或 PAM，也不合并 niri 配置；它安装两个用户单元，repatch 失败只警告。两条路径都可能覆盖已有文件，先备份。

假设：你在 **Arch + niri** 上、以你的用户登录，并且 **Omarchy 已经装在** `~/.local/share/omarchy`（它有自己的安装器）。
你已经克隆了本仓库到某处；把下面的 `REPO` 设为该路径。

```sh
REPO=/path/to/omarchy-on-niri     # <-- 改成你的路径
```

---

## 1. 系统包

```sh
sudo pacman -S --needed \
  git base-devel jq qt6-imageformats inotify-tools wl-clipboard \
  pipewire wireplumber playerctl ghostty
```

- **quickshell**（Omarchy 外壳跑在其上的 QML 引擎）——较新版本在 Arch 官方仓库里，否则走 AUR（`quickshell-git`）。不装它外壳渲染不出来。
- **电源后端 — 二选一：**
  - `sudo pacman -S --needed power-profiles-daemon`（提供 `powerprofilesctl`），**或**
  - `sudo pacman -S --needed tlp tlp-pd`（移植机用的是这个；`powerprofilesctl` 不存在，`port-bin/omarchy-powerprofiles-*` 会回退到 TLP 的 D-Bus 接口）。
- **可选：** `satty`（截图标注）、`swappy`、`grim slurp`（捕获助手）。

`qt6-imageformats` 是关键：没有它 Qt 解不了 `.webp` 壁纸，你会得到一片黑背景。

---

## 2. 把移植胶水放进 `~/bin`

这些是 PATH 最前的覆盖脚本，把跟 Hyprland 耦合的部分翻译到 niri。`~/bin` 必须在 `PATH` **最前面**——那是在 niri 配置的 environment 块里设的（第 3 步）。

```sh
mkdir -p ~/bin
for f in "$REPO"/port-bin/*; do [[ -f $f ]] || continue; install -m 0755 "$f" ~/bin/; done
```

这会装上：`hyprctl`（垫片——**关键**，约 50 个 omarchy 脚本会调它）、`omarchy-niri-system`、
`omarchy-niri-apply-theme`、`omarchy-niri-repatch`、`omarchy-powerprofiles-list`、
`omarchy-powerprofiles-set`，以及 `materal-update`（只有用 matugen 派生主题时才需要，见第 5 步）。

---

## 3. 接线合成器（`~/.config/niri/config.kdl`）

两条路，**不等价**：

- **`niri-config/local/*.kdl`** —— 本机**实际在用**的配置：七份文件、约 910 行
  （`config` + `input/monitor/layout/window-rules/effects/binds`），含磨砂全栈、圆角、gaps、
  窗口规则、去重后的整套按键。先读 `niri-config/README.md`，拷到 `~/.config/niri/`，
  把 `/home/<user>` 换成自己家目录、按自己显示器改 `monitor.kdl`。
- **`niri-config/omarchy.kdl.template`**（下面这条）—— 58 行的**接线片段**：`environment`、
  shell 自启、Omarchy 那几条 bind，合并进你已有的配置里。够把壳跑起来，但**不含合成器侧的调校**。

先备份，再合并。用你的 home 路径替换 `__HOME__`，从模板生成如下行：

```sh
mkdir -p ~/.config/niri ~/.local/state/backups/.config/niri
sed "s|__HOME__|$HOME|g" "$REPO/niri-config/omarchy.kdl.template" > ~/.config/niri/omarchy.kdl
cp ~/.config/niri/config.kdl ~/.local/state/backups/.config/niri/config.kdl.bak 2>/dev/null || true
```

然后编辑 `~/.config/niri/config.kdl`：

1. **顶层** — 添加 `environment { }` 块和 `spawn-sh-at-startup` 行：

   ```kdl
   environment {
       XDG_CURRENT_DESKTOP "niri"
       OMARCHY_PATH "/home/you/.local/share/omarchy"
       PATH "/home/you/bin:/home/you/.local/share/omarchy/bin:/home/you/.local/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"
   }

   spawn-sh-at-startup "omarchy-launch-shell"
   ```

   （用你自己的真实路径，别用 `/home/you`。生成的模板直接启动 `quickshell`；请换成这里的监督启动器，它记录日志并在外壳崩溃后重启。）

2. **在你现有的 `binds { }` 块里** — 粘入 Omarchy 绑定。完整列表在 `~/.config/niri/omarchy.kdl`（上面生成的）；重点是这些：

   ```kdl
   Mod+Space         hotkey-overlay-title="Omarchy Menu" { spawn-sh "omarchy-menu toggle"; }
   Mod+K             hotkey-overlay-title="Keybindings"  { spawn-sh "omarchy-menu-keybindings"; }
   Mod+Ctrl+L        hotkey-overlay-title="Lock system"  { spawn-sh "omarchy-system-lock"; }
   Mod+Ctrl+P        hotkey-overlay-title="Power"        { spawn-sh "omarchy-shell shell toggle omarchy.power"; }
   Mod+Return        hotkey-overlay-title="Terminal"     { spawn "ghostty"; }
   XF86AudioRaiseVolume allow-when-locked=true hotkey-overlay-title="Volume up" { spawn-sh "omarchy-audio-output-volume raise"; }
   XF86MonBrightnessUp   allow-when-locked=true hotkey-overlay-title="Brightness up" { spawn-sh "omarchy-brightness-display +5%"; }
   ```

校验：

```sh
niri validate -c ~/.config/niri/config.kdl
```

---

## 4. Omarchy 配置层1（`~/.config/omarchy/shell.json`）

仅当它还不存在时才做（它存你的 bar 布局 / 空闲定时器）：

```sh
mkdir -p ~/.config/omarchy
cp "$REPO/niri-config/shell.json" ~/.config/omarchy/shell.json
```

**4b. 本机 `~/.config` 覆盖层（`local-config/`）** —— 上游默认树之外、上游不给的那几份，漏掉就会
"有窗口装饰、无磨砂"：

```sh
mkdir -p ~/.config/ghostty
cp "$REPO/local-config/ghostty/config" ~/.config/ghostty/config      # 先备份你自己的
mkdir -p ~/.config/systemd/user
cp "$REPO/local-config/systemd/user/materal-recolor."* ~/.config/systemd/user/
systemctl --user enable --now materal-recolor.path                   # 需要 ~/bin/materal-update 在位
ghostty +validate-config                                             # 无输出即通过
```

`ghostty/config` 里三条是移植必需的（`window-decoration = false`、`background-opacity = 0.85`、
**`background-blur-radius = 0`** —— niri 不实现 KDE blur 协议，磨砂要交给 niri 的 `background-effect`）；
配色走 Omarchy 主题（`config-file = ?"~/.local/state/omarchy/current/theme/ghostty.conf"`，上游写法，
`?` 表示文件不在也不报错），不需要任何私有主题文件。字体/键位是个人口味，按需改。
细节见 `local-config/README.md`。

---

## 5. 更新/主题钩子

```sh
mkdir -p ~/.config/omarchy/hooks/post-update.d ~/.config/omarchy/hooks/theme-set.d
install -m 0755 "$REPO"/hooks/post-update.d/* ~/.config/omarchy/hooks/post-update.d/
install -m 0755 "$REPO"/hooks/theme-set.d/*    ~/.config/omarchy/hooks/theme-set.d/
```

`post-update.d/10-niri-repatch` 在每次 `omarchy update` 后重放覆盖层；
`theme-set.d/10-niri-border` 在每次切换 style 时写入 focus-ring 颜色；
`theme-set.d/20-materal` 用 Omarchy 当前选中的壁纸重新推导"带 `matugen.toml` 的主题"的配色（需要
`matugen`；没有该文件的主题不受影响）。另外那对"换壁纸也重新取色"的 systemd 单元
（`materal-recolor.{path,service}`）装法见上面第 4b 步（仓库 `local-config/systemd/user/`）。

---

手动路径还需要状态目录；如需 `install.sh` 安装的两个会话单元，可执行以下命令（先备份已有单元和链接）：

```sh
mkdir -p ~/.local/state/omarchy/toggles/hypr ~/.config/systemd/user/graphical-session.target.wants
for unit in omarchy-picker-warmup.service omarchy-clamshell-watch.service; do
  install -m 0644 "$REPO/default/systemd/user/$unit" ~/.config/systemd/user/
  ln -sfn "$HOME/.config/systemd/user/$unit" "$HOME/.config/systemd/user/graphical-session.target.wants/$unit"
done
systemctl --user daemon-reload
```

链接依赖会话启动 `graphical-session.target`，请在目标机器核实。

## 6. 把移植覆盖层应用到 Omarchy 安装

把覆盖层放到 repatch 期望的位置，然后应用（幂等）：

```sh
mkdir -p ~/.config/omarchy/niri-port
cp "$REPO"/niri-port/niri.patch "$REPO"/niri-port/Niri.qml ~/.config/omarchy/niri-port/
cp -a "$REPO"/niri-port/plugins ~/.config/omarchy/niri-port/
~/bin/omarchy-niri-repatch
```

repatch 在 `XDG_CURRENT_DESKTOP` 不是 `niri` 或 Omarchy 没有 `.git` 目录时跳过（均返回 0），要检查输出；覆盖层缺失返回 1，补丁冲突返回 2。冲突检查前它已复制 `Niri.qml` 和插件，因此冲突时这些文件也可能已改变，先备份。插件副本包含 `blurwallpaper`；第三方 `plugin-patches/` 独立存放，不自动重放。

**重要：** 保持 `~/.local/share/omarchy` 里的文件改动**未提交**；提交它们可能阻碍上游快进更新。
上游 post-update 钩子可以重放 `niri.patch`，但移植的 `~/bin/omarchy-update` 不会触发该钩子。更新改变 Omarchy 源码树后应检查结果，必要时手动运行 `~/bin/omarchy-niri-repatch`。

---

## 7. 背光权限（udev + video 组）

让 `brightnessctl` 无需 root 就能写入：

```sh
echo 'SUBSYSTEM=="backlight" GROUP="video" MODE="0664"' | sudo tee /etc/udev/rules.d/90-backlight.rules
sudo usermod -aG video "$USER"
sudo udevadm control --reload-rules && sudo udevadm trigger

# udev trigger 只会发 'change'，不会对已存在的节点重新应用 group/mode，
# 所以现在做个兜底（下次开机才正确生效）：
node=$(echo /sys/class/backlight/*/brightness); sudo chgrp video "$node"; sudo chmod 0664 "$node"
```

---

## 8. 锁屏认证（必做，需要 root）

`/etc/pam.d/omarchy-lock-password` 不存在时，外壳**会拒绝锁屏**：锁屏 IPC 直接返回 `missing-pam`，屏幕
根本不会锁。这是刻意的设计——会话锁一旦锁上而 PAM 又不可用，就没有任何回退路径。该文件由 **Omarchy
安装器**写入（`install/config/lockscreen-pam.sh` → `omarchy-apply-lock`），而本手动安装路径跳过了安装器，
所以要自己跑一次：

```sh
pkexec ~/.local/share/omarchy/bin/omarchy-apply-lock     # 或者：sudo omarchy-apply-lock
omarchy-shell lock status | grep passwordPam             # 期望 "passwordPam":true
```

它是**全机共享**的，一台机器跑一次就覆盖所有账户。另外上游探测指纹时用 `grep` 在 `fprintd-list` 输出里
找 `finger`，而"未注册"时的输出 `no finger**s** enrolled` 同样命中，于是可能写出一条无用的
`/etc/pam.d/omarchy-lock-fingerprint`；若 `fprintd-list "$USER"` 显示没有注册指纹，就 `sudo rm` 掉它。
（完整分析——含"为什么与 dms-greeter 无关"——见 `docs/lock.md` §8.18。）

---

## 9. 每机检查（必须手动核对）

这些无法自动检测，每台机器都不同：

1. **显示器输出名** — 移植/节点配置在几处引用 `eDP-1`；跑 `niri msg outputs` 改成你的输出名。
2. **背光设备** — 移植机上是 `intel_backlight`；对照你 `/sys/class/backlight/*` 里的确认。
3. **电源后端** — power-profiles-daemon（`powerprofilesctl`）还是 TLP（`tlp + tlp-pd`）；这会改变 `omarchy-powerprofiles-*` 报告的内容和 Power 菜单显示什么。
4. **niri 版本** — 在 26.04 上测试过；不同版本的键位/总览行为可能有差异。
5. **锁屏认证** — `omarchy-shell lock status` 必须报 `"passwordPam":true`（第 8 步），否则 `Mod+Ctrl+L` 完全没反应。

---

## 10. 启动并验证

注销再登录——`spawn-sh-at-startup` 会拉起 QuickShell 外壳。然后检查：

```sh
niri msg layers                       # 检查 Omarchy 图层
omarchy-shell shell ping              # 外壳 IPC 有响应吗？
omarchy-menu toggle                   # 菜单能开吗？
~/bin/omarchy-niri-system bogus       # 输出用法并返回 2
```

系统动作接线需要另行检查：当前 `bin/omarchy-system` 没有调用 `omarchy-niri-system`。核实已安装的入口并做好准备前，不要测试注销、重启或关机。

bar 应渲染出工作区/时钟/键盘布局；`Mod+Space` 打开菜单；媒体键显示 OSD；Power 菜单显示 注销 / 重启 / 关机。

完整的移植笔记见 `omarchy-on-niri-port.md`（中文），依赖取舍见 `README.zh.md`。
