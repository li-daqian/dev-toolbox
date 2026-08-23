# dev-toolbox

用于自动安装和配置个人 Ubuntu 开发环境、命令行工具与桌面软件的脚本集合。

## Ubuntu 一键安装

主安装入口仅支持 Ubuntu，并按顺序执行基础开发环境和 GNOME 桌面配置。执行过程中需要联网和 `sudo` 权限；未配置 Git 身份时，交互式运行会询问 `user.name` 和 `user.email`。

```bash
curl -fsSL "https://raw.githubusercontent.com/li-daqian/dev-toolbox/main/bootstrap.sh?$(date +%s)" | sh
```

### 安装的软件

以下清单覆盖 `bootstrap.sh` 及其调用的子脚本直接声明、下载或安装的全部软件；不展开 APT、SDKMAN、NVM 等包管理器自动解析的 transitive dependencies。

| 分类 | 安装内容 | 安装方式与用途 |
| --- | --- | --- |
| Ubuntu 基础包 | `ca-certificates`、`curl`、`wget`、`git`、`unzip`、`fontconfig`、`software-properties-common`、`gpg` | 通过 Ubuntu APT 安装，为 HTTPS 下载、Git、压缩包、字体缓存、PPA 和软件源签名提供基础能力 |
| GitHub | GitHub CLI (`gh`) | 配置 GitHub 官方 APT 源后安装 |
| 系统监控 | btop | 优先使用 Ubuntu APT；仓库版本低于 1.4.0 时安装脚本指定的 Ubuntu 官方 DEB，并尝试启用 CPU 功耗显示 |
| 系统信息 | neofetch | 通过 Ubuntu APT 安装 |
| Shell | `zsh`、Oh My Zsh、Spaceship Prompt | 安装并将 Zsh 设为默认 Shell，同时写入仓库提供的 `.zshrc` |
| Zsh 插件 | `zsh-autosuggestions`、`zsh-syntax-highlighting`、`zsh-z` | 从各自的 Git 仓库安装到 Oh My Zsh 自定义插件目录 |
| JVM 工具链 | SDKMAN、Java、Maven | 安装 SDKMAN，并通过它安装 Java 和 Maven |
| Node.js 工具链 | NVM、Node.js LTS、pnpm | 安装 NVM 0.39.5，通过 NVM 安装 Node.js LTS，再通过 npm 全局安装 pnpm |
| JavaScript Runtime | Bun | 通过 Bun 官方安装脚本安装 |
| Rust 工具链 | rustup、Rust | 通过 rustup 官方安装脚本安装默认 Rust 工具链 |
| 容器工具 | `docker-ce`、`docker-ce-cli`、`containerd.io`、`docker-buildx-plugin`、`docker-compose-plugin` | 配置 Docker 官方 APT 源后安装 Docker Engine、CLI、containerd、Buildx 和 Compose |
| X11 剪贴板 | xclip | 通过 Ubuntu APT 安装 |
| 剪贴板管理器 | CopyQ | 配置 CopyQ PPA 后安装，设置为开机启动，并绑定 <kbd>Super</kbd>+<kbd>V</kbd> 显示或隐藏主界面 |
| 应用启动器 | Albert、xdotool | 配置 Albert 官方推荐的 openSUSE Build Service APT 源后安装；设置为开机启动，将全局快捷键设为 <kbd>Alt</kbd>+<kbd>Space</kbd>，并默认启用应用、计算器、命令行、日期时间、Emoji、VS Code Projects 和网页搜索等插件；xdotool 为 X11 桌面提供结果粘贴能力 |
| 输入法 | `ibus-rime`、`rime-data-double-pinyin` | 使用 IBus 输入法框架和 Rime（中州韵）引擎；只启用小鹤双拼方案，中文模式默认输出简体字，候选词横向排列 |
| 编程字体 | Input Mono | 从 Input 官网下载完整字体包，将 `InputMono-*.ttf` 安装到当前用户的字体目录 |

除软件外，主脚本还会安装 Codex 与 Claude Code 的全局 Agent 工作约定文件。脚本会跳过大部分已安装的软件，因此可以重复执行；具体是否跳过以各子脚本的检测结果为准。

### 系统与桌面配置

- GNOME 使用深色模式、1.2 倍文本缩放、底部固定 Dock，并关闭动画。
- 配置左右工作区快捷键为 <kbd>Ctrl</kbd>+<kbd>Super</kbd>+方向键。
- 如果已安装 GNOME System Monitor 扩展，则启用 CPU、内存和下载速率显示；脚本本身不会安装该扩展。
- 将电源模式和 CPU governor 设为 `performance`（系统支持相应命令时）。
- 将 `vm.swappiness` 设置为 `10`，并写入 `/etc/sysctl.conf`。
- 为兼容 CopyQ，存在 `/etc/gdm3/custom.conf` 时会禁用 Wayland，并提示是否重启 GDM。重启 GDM 会立即退出当前桌面会话。
- Docker 用户组变更需要重新登录，或执行 `newgrp docker` 后生效。
- 安装 Codex 与 Claude Code 的全局 Agent 工作约定，并清理超过 7 天的现有 systemd journal 日志。

## Cleanup Disk (Ubuntu)

清理 APT 缓存、未使用的 Docker 容器/镜像/网络、旧 Snap revision、systemd journal 和 crash reports。Docker volumes 会始终保留。

```bash
curl -fsSL "https://raw.githubusercontent.com/li-daqian/dev-toolbox/main/ubuntu/cleanup-disk.sh?$(date +%s)" | sh
```

## GitHub CLI (gh, Ubuntu)

```bash
curl -fsSL "https://raw.githubusercontent.com/li-daqian/dev-toolbox/main/ubuntu/install-gh.sh?$(date +%s)" | bash
```

## Albert Launcher (Ubuntu 24.04)

安装 Albert 和用于 X11 粘贴的 xdotool，设置 Albert 登录时自动启动，将全局快捷键设为 <kbd>Alt</kbd>+<kbd>Space</kbd>，并写入常用插件的默认启用配置。

```bash
curl -fsSL "https://raw.githubusercontent.com/li-daqian/dev-toolbox/main/ubuntu/install-albert.sh?$(date +%s)" | bash
```

## Playwright MCP for Codex and Claude Code

```bash
./scripts/install-playwright-mcp.sh
```

## Matt Pocock Skills for Codex

The installer keeps an unmodified checkout of
[`mattpocock/skills`](https://github.com/mattpocock/skills) and exposes skills to
Codex through symlinks. Re-running a command updates the checkout, so local
patches do not need to be maintained.

Install the five curated work skills in the Codex user scope:

```bash
./scripts/install-matt-pocock-skills.sh work
```

The work profile installs `grilling`, `grill-me`, `diagnosing-bugs`,
`domain-modeling`, and `grill-with-docs` into `~/.agents/skills`.

For a personal Git project, make the complete stable upstream set available in
that project:

```bash
./scripts/install-matt-pocock-skills.sh personal --project ~/Code/my-project
```

The personal profile includes skills under the upstream `engineering`,
`productivity`, and `misc` groups, while excluding `in-progress` and
`deprecated`. Skills already present in the user scope are reused instead of
being installed a second time, which avoids duplicate names in Codex's skill
selector.

Enable a weekly user-level systemd timer that updates the five work skills on
Monday at 09:00:

```bash
./scripts/install-matt-pocock-skills.sh auto-update enable
```

Enabling the timer runs one immediate update before scheduling future runs.
Inspect or disable it with:

```bash
./scripts/install-matt-pocock-skills.sh auto-update status
./scripts/install-matt-pocock-skills.sh auto-update disable
```

The updater writes combined output to
`~/.local/state/codex-skill-updater/update.log`. Use `--calendar` to choose a
different systemd calendar expression. The generated service keeps using the
installer's absolute path, so re-enable automatic updates if the repository is
moved.

Run the isolated installer tests with:

```bash
./scripts/test-install-matt-pocock-skills.sh
```

## CPU Thermal Watch (Special Ubuntu Workaround)

For specific Intel laptop cases where Linux is stuck at unusually low CPU package power and the bottleneck is traced to the `processor_thermal` platform thermal chain.

```bash
bash ubuntu/cpu-thermal-watch/install.sh
```

Details:
- [ubuntu/cpu-thermal-watch/README.md](./ubuntu/cpu-thermal-watch/README.md)

## oh-my-zsh

```bash
curl -fsSL  "https://raw.githubusercontent.com/li-daqian/dev-toolbox/main/oh-my-zsh/install.sh?$(date +%s)" | sh
```

## rime (Only for linux)

```bash
curl -fsSL  "https://raw.githubusercontent.com/li-daqian/dev-toolbox/main/rime/install.sh?$(date +%s)" | sh
```
