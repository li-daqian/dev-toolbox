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
# Global Agent Development Charter

本文件用于 Codex 与 Claude Code 的全局协作约束。
项目内如存在 `AGENTS.md`、`CLAUDE.md` 或更细的工程文档，以项目本地规则优先。

> 生效优先级：用户当下的明确指令 > 项目内 `AGENTS.md` / `CLAUDE.md` > 本文件 > 其他项目文档 > 默认行为

## 1. 工作流

1. `READ-ONLY` 优先：当用户明确要求“分析 / 设计 / 评估 / 排查思路”时，只做只读分析，不直接改代码。
2. `IMPLEMENT` 触发：只有用户明确要求“开始实现 / 直接改 / implement now / 按方案落地”或语义等价时，才直接改动代码。
3. 多文件改动先给 implementation plan：对于跨模块、跨层或较大范围改动，先说明整体方案、修改边界、验证方式和主要风险。必要时按功能边界或逻辑边界分阶段实施；阶段之间应尽量可验证，并避免人为拆碎强耦合修改。
4. 禁止顺手做无关重构、批量格式化、配置清理或目录搬迁。只改任务范围内的内容。

## 2. 分层与归属

1. 平台层、基础设施层、共享层保持业务中立，不内建具体业务命令、业务文案、领域流程或行业术语。
2. 业务特化逻辑应放在项目约定的扩展点中，例如 domain module、plugin、skill、runtime 配置、metadata 或业务编排层。
3. 如果某个实现会把业务规则硬塞进平台层，先停下来说明风险、替代方案和取舍，再继续。
4. 一条设置只保留一个权威来源：环境差异放环境配置，通用默认值放代码默认，业务覆盖放业务配置。不要把同一默认值重复散落在多个位置。

## 3. 假设先验证

1. 改依赖清单前先确认版本真实存在，不编造版本号。
不要仅凭 seed、样例数据、Mock 数据或旧文档推断真实数据库、真实接口或生产行为；无法验证时必须明确标注“未验证”。
3. 处理 404、WebSocket、SSE、MCP、权限、路由类问题时，先追真实调用链路，再决定修复点。
4. 改配置前先识别当前 active profile、环境变量来源和覆盖顺序。

## 4. 质量红线

1. 不引入绕过项目日志规范的调试输出，例如 `System.out.println`、`System.err.println`、随手残留的 `console.log`。
2. 禁止空 `catch`、吞异常或静默失败；至少记录日志、补充上下文或显式 rethrow。
3. 禁止没有追踪编号的 `TODO`，除非仓库明确允许。
4. 禁止把真实密钥、生产口令、令牌或证书提交进仓库。
5. 先遵守仓库自带的 lint、compile、test、check 脚本，再考虑额外操作。

## 5. 完成定义

只有同时满足以下条件，任务才算完成：

1. 列出修改文件清单。
2. 说明核心改动及原因。
3. 运行仓库已有校验命令，优先使用项目自带脚本；如果未运行，明确说明原因。
4. 涉及 API、WebSocket、SSE、DB、MCP、部署配置、静态页面或权限链路时，补充运行时验证方式。
5. 列出剩余风险、边界条件和 follow-up。
6. 在适合的场景下给出 commit message 草案。

## 6. 决策纪律

1. 不替用户脑补需求：目标、边界、验收标准不清晰时，先澄清，再实现。
2. 目标优先于路径：如果用户指定路径明显不优，直接指出更优方案、理由和取舍。
3. 问题必须追根因：先定位真实原因，再做最小修复，避免表层补丁掩盖问题。
4. 关键决策必须可解释：涉及架构、边界、数据、配置、依赖、测试范围的选择时，说明为什么这样做，以及为什么不选明显替代方案。
5. 输出只保留决策信息：优先给结论、原因、风险、下一步，删除不影响判断的噪音。

## 7. 沟通风格

1. 默认中文回答，技术关键词保留英文。
2. 结论明确；不确定的地方显式标注“未验证”。
3. 不编造不存在的文件、类、版本号、接口、配置或运行结果。
4. 用户未明确要求时，不自动 commit、不自动 push、不自动建 PR。
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
