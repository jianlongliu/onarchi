# 这个 bar 是什么

`omarchy.bar`（本目录）现在是**浮空圆角 bar**：上游 omarchy 官方 bar 的骨架 +
`Charlieras262/omarchy-floating-bar` 的浮空实现 + 本机改动，全部并成一份、放在
shell 树里，由 `niri-port/niri.patch` 在每次 `omarchy update` 后重放。

- 浮空实现来源：`https://github.com/Charlieras262/omarchy-floating-bar`
  本地克隆 commit `5e7dc23`（2026-08-28），版本 1.6.0，MIT（见同目录 `LICENSE`，
  版权 Charlieras262）。
- 合并基线：本机 shell 树 checkout `basecamp/omarchy` 的 `60663faf`
  （2026-09-19）。原版这个目录的内容可用
  `git -C ~/.local/share/omarchy show 60663faf:shell/plugins/bar/Bar.qml` 取回。
- 合并后 `manifest.json` 用官方的（`id: omarchy.bar`），`shell.json` 的
  `bar.id` 因此是 `omarchy.bar`——宿主按“内置 bar”路径加载它（会直接注入
  `omarchyPath` / `barWidgetRegistry`，见 `shell.qml` 的 `configureBar()`）。
- 上游 omarchy 对 `shell/plugins/bar/` 改动很频繁（100 提交窗口内 86 次），
  所以**不再自动跟上游**：需要时手工把这些改动并进来（按需人工合并）。
- 浮空会外溢到邻层：`shell/plugins/notifications/Service.qml`、
  `shell/Ui/KeyboardPanel.qml` 里的 gap 让步也是这套的一部分，同在本补丁里。
