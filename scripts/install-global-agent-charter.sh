#!/usr/bin/env bash
set -euo pipefail

TARGET="both"
APPLY="false"
STDOUT_ONLY="false"
CODEX_HOME_DIR="${CODEX_HOME:-${HOME}/.codex}"
CODEX_PATH="${CODEX_HOME_DIR}/AGENTS.md"
CLAUDE_PATH="${HOME}/.claude/CLAUDE.md"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/install-global-agent-charter.sh [options]

Options:
  --target <codex|claude|both>  Target global instruction file(s). Default: both
  --apply                       Actually write files instead of previewing
  --stdout                      Print the generated charter only
  --codex-path <path>           Override Codex target path (default: $CODEX_HOME/AGENTS.md or ~/.codex/AGENTS.md)
  --claude-path <path>          Override Claude Code target path
  --help                        Show this help

Examples:
  ./scripts/install-global-agent-charter.sh
  ./scripts/install-global-agent-charter.sh --target codex --apply
  ./scripts/install-global-agent-charter.sh --apply \
    --codex-path /tmp/codex-AGENTS.md \
    --claude-path /tmp/claude-CLAUDE.md
EOF
}

render_charter() {
  cat <<'EOF'
# Global Agent Working Agreements

## 1. 范围与授权

1. 分析、设计、评估、review 和诊断请求默认只读；修复、实现、修改类请求才授权在任务范围内编辑文件。
2. 不做无关重构、批量格式化、配置清理或目录迁移。
3. 未经明确要求，不 commit、不 push、不创建 PR。
4. 跨模块、高风险或存在重大方案选择时，先给简短 implementation plan；普通局部修改直接完成。

## 2. 决策与验证

1. 低风险、可逆且不改变目标的细节可以作合理假设并继续；只有选择会显著改变结果、范围或风险时才询问。
2. 修改依赖、配置、路由、协议或权限逻辑前，先验证实际版本、调用链、active profile 和覆盖顺序。
3. 不根据 seed、Mock、样例或旧文档推断生产行为；重大事实无法验证时标注“未验证”。
4. 除非确认存在已发布版本、生产数据或外部调用方，否则不新增兼容层；不兼容风险重大且无法验证时再询问。
5. 优先解决根因并控制改动范围，只说明影响结果的关键取舍。

## 3. 实现默认值

1. 已知 schema 或跨模块、public boundary 优先使用命名类型；动态容器仅用于真正动态的数据，并在边界校验。
2. 不遗留调试输出，不提交密钥，不无说明地吞异常。
3. 注释解释非显而易见的 `why`、约束和风险；不强制为自解释的方法、参数或字段补注释。
4. 遵循仓库已有的日志、类型、lint、compile、test 和 check 规范。

## 4. 实现交付

实现任务完成时：

1. 列出修改文件和核心原因。
2. 说明已运行的验证命令及结果；未运行时说明原因。
3. 涉及 API、DB、MCP、WebSocket/SSE、权限或部署配置时，说明必要的运行时验证方式。
4. 仅在确有剩余风险或边界条件时列出它们。

## 5. 沟通方式

1. 默认使用中文，技术关键词保留英文。
2. 输出优先包含结论、原因、风险和下一步，避免固定模板和无关过程信息。
3. 核心架构、调用链或数据流确需图示时，优先使用 boxed ASCII 图。
EOF
}

log() {
  printf '%s\n' "$*"
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

backup_if_exists() {
  local target_path="$1"
  if [[ -f "$target_path" ]]; then
    local backup_path="${target_path}.bak.${TIMESTAMP}"
    cp "$target_path" "$backup_path"
    log "Backed up existing file to ${backup_path}"
  fi
}

write_target() {
  local target_path="$1"
  mkdir -p "$(dirname "$target_path")"
  backup_if_exists "$target_path"
  render_charter > "$target_path"
  log "Wrote ${target_path}"
}

preview_target() {
  local label="$1"
  local target_path="$2"
  log "===== ${label}: ${target_path} ====="
  render_charter
  printf '\n'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      [[ $# -ge 2 ]] || fail "--target requires a value"
      TARGET="$2"
      shift 2
      ;;
    --apply)
      APPLY="true"
      shift
      ;;
    --stdout)
      STDOUT_ONLY="true"
      shift
      ;;
    --codex-path)
      [[ $# -ge 2 ]] || fail "--codex-path requires a value"
      CODEX_PATH="$2"
      shift 2
      ;;
    --claude-path)
      [[ $# -ge 2 ]] || fail "--claude-path requires a value"
      CLAUDE_PATH="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

case "$TARGET" in
  codex|claude|both)
    ;;
  *)
    fail "target must be one of: codex, claude, both"
    ;;
esac

if [[ "$STDOUT_ONLY" == "true" ]]; then
  render_charter
  exit 0
fi

if [[ "$APPLY" == "true" ]]; then
  case "$TARGET" in
    codex)
      write_target "$CODEX_PATH"
      ;;
    claude)
      write_target "$CLAUDE_PATH"
      ;;
    both)
      write_target "$CODEX_PATH"
      write_target "$CLAUDE_PATH"
      ;;
  esac
  exit 0
fi

log "Preview mode only. Re-run with --apply to write files."
case "$TARGET" in
  codex)
    preview_target "Codex" "$CODEX_PATH"
    ;;
  claude)
    preview_target "Claude Code" "$CLAUDE_PATH"
    ;;
  both)
    preview_target "Codex" "$CODEX_PATH"
    preview_target "Claude Code" "$CLAUDE_PATH"
    ;;
esac
