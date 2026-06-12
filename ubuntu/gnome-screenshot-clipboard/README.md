# GNOME Screenshot Clipboard

把 Ubuntu GNOME 的 `Print Screen` 改成“截图后直接复制到剪贴板”，不把截图默认保存到 `Pictures/Screenshots`。

## 当前适用范围

- Ubuntu GNOME / GNOME Shell 46
- X11 session
- 已安装 ImageMagick `import` 和 `xclip`

## 安装

```bash
bash ubuntu/gnome-screenshot-clipboard/install.sh install
```

安装脚本会做三件事：

- 禁用 GNOME Shell 内置 `Print` 截图 UI 绑定：`org.gnome.shell.keybindings show-screenshot-ui`
- 新增自定义快捷键：`Print -> screenshot-to-clipboard.sh area`
- 使用 `import png:- | xclip -selection clipboard -target image/png -i`，PNG 只进入剪贴板，不创建截图文件

## 验证

```bash
bash ubuntu/gnome-screenshot-clipboard/install.sh status
bash ubuntu/gnome-screenshot-clipboard/install.sh test
```

`test` 会截取当前全屏到剪贴板，并打印 clipboard 支持的 target，其中应包含 `image/png`。

## 卸载

```bash
bash ubuntu/gnome-screenshot-clipboard/install.sh uninstall
```

卸载会删除自定义快捷键，并把 GNOME Shell 内置截图 UI 恢复到 `Print`。
