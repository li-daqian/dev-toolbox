#!/usr/bin/env bash

instruction_path_for_agent() {
  case "$1" in
    codex) printf '%s\n' "$CODEX_INSTRUCTIONS_PATH" ;;
    claude) printf '%s\n' "$CLAUDE_INSTRUCTIONS_PATH" ;;
    *) fail "unknown Agent: $1" ;;
  esac
}

preflight_instruction_target() {
  local agent="$1"
  local target_path

  target_path="$(instruction_path_for_agent "$agent")"
  if [[ -L "$target_path" ]]; then
    fail "instruction target is a symlink; refusing to follow it: ${target_path}"
  fi
  if [[ -e "$target_path" && ! -f "$target_path" ]]; then
    fail "instruction target is not a regular file: ${target_path}"
  fi
}

preflight_instructions() {
  [[ -f "$INSTRUCTIONS_TEMPLATE" ]] || fail "missing instruction template: ${INSTRUCTIONS_TEMPLATE}"
  if target_includes_agent codex; then
    preflight_instruction_target codex
  fi
  if target_includes_agent claude; then
    preflight_instruction_target claude
  fi
}

install_instruction_for_agent() {
  local agent="$1"
  local target_path
  local target_dir
  local backup_path
  local temp_path

  target_path="$(instruction_path_for_agent "$agent")"
  if [[ -f "$target_path" ]] && cmp -s "$INSTRUCTIONS_TEMPLATE" "$target_path"; then
    log "Instructions already current: ${target_path}"
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    if [[ -f "$target_path" ]]; then
      log "Would back up and update instructions: ${target_path}"
    else
      log "Would install instructions: ${target_path}"
    fi
    return
  fi

  target_dir="$(dirname "$target_path")"
  mkdir -p "$target_dir"
  if [[ -f "$target_path" ]]; then
    backup_path="${target_path}.bak.$(make_unique_timestamp)"
    cp "$target_path" "$backup_path"
    log "Backed up existing instructions to ${backup_path}"
  fi

  temp_path="$(mktemp "${target_path}.tmp.XXXXXX")"
  cp "$INSTRUCTIONS_TEMPLATE" "$temp_path"
  mv "$temp_path" "$target_path"
  log "Installed instructions: ${target_path}"
}

warn_if_codex_override_masks_instructions() {
  local override_path="$(dirname "$CODEX_INSTRUCTIONS_PATH")/AGENTS.override.md"
  if target_includes_agent codex && [[ -s "$override_path" ]]; then
    warn "${override_path} is non-empty and masks ${CODEX_INSTRUCTIONS_PATH}"
  fi
}

apply_instructions() {
  if target_includes_agent codex; then
    install_instruction_for_agent codex
  fi
  if target_includes_agent claude; then
    install_instruction_for_agent claude
  fi
  warn_if_codex_override_masks_instructions
}

install_instructions() {
  preflight_instructions
  apply_instructions
}
