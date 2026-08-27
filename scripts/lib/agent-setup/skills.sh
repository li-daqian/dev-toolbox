#!/usr/bin/env bash

load_profile_manifest() {
  local line
  local relative_path
  local skill_name
  local existing_name

  PROFILE_MANIFEST="${MANIFEST_ROOT}/mattpocock-${PROFILE}.txt"
  [[ -f "$PROFILE_MANIFEST" ]] || fail "missing profile manifest: ${PROFILE_MANIFEST}"

  SELECTED_RELATIVE_PATHS=()
  SELECTED_NAMES=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    case "$line" in ''|'#'*) continue ;; esac
    relative_path="$line"
    case "$relative_path" in
      skills/engineering/*|skills/productivity/*|skills/misc/*) ;;
      *) fail "invalid skill path in ${PROFILE_MANIFEST}: ${relative_path}" ;;
    esac
    case "$relative_path" in *'..'*|*' '*) fail "unsafe skill path in ${PROFILE_MANIFEST}: ${relative_path}" ;; esac

    skill_name="$(basename "$relative_path")"
    # Bash 3.2 with nounset treats an empty array expansion as unbound.
    for existing_name in ${SELECTED_NAMES[@]+"${SELECTED_NAMES[@]}"}; do
      [[ "$existing_name" != "$skill_name" ]] || fail "duplicate skill name in manifest: ${skill_name}"
    done
    SELECTED_RELATIVE_PATHS+=("$relative_path")
    SELECTED_NAMES+=("$skill_name")
  done < "$PROFILE_MANIFEST"

  [[ ${#SELECTED_NAMES[@]} -gt 0 ]] || fail "profile manifest is empty: ${PROFILE_MANIFEST}"
}

prepare_skill_source() {
  SOURCE_AVAILABLE="false"

  if [[ -n "$EXTERNAL_SOURCE_DIR" ]]; then
    [[ -d "$EXTERNAL_SOURCE_DIR" ]] || fail "source directory does not exist: ${EXTERNAL_SOURCE_DIR}"
    SOURCE_DIR="$(canonical_dir "$EXTERNAL_SOURCE_DIR")"
    SOURCE_AVAILABLE="true"
    log "Using existing upstream checkout: ${SOURCE_DIR}"
    return
  fi

  SOURCE_DIR="$MANAGED_SOURCE_DIR"
  if [[ "$DRY_RUN" == "true" ]]; then
    if [[ -d "$SOURCE_DIR" ]]; then
      [[ -d "$SOURCE_DIR/.git" ]] || fail "managed source exists but is not a Git checkout: ${SOURCE_DIR}"
      SOURCE_DIR="$(canonical_dir "$SOURCE_DIR")"
      SOURCE_AVAILABLE="true"
      log "Dry run uses existing source without fetching: ${SOURCE_DIR}"
    else
      log "Would clone ${UPSTREAM_REPO} at ${UPSTREAM_REF} into ${SOURCE_DIR}"
      warn "source is absent; dry run cannot validate upstream skill contents or managed destinations"
    fi
    return
  fi

  require_command git
  if [[ -e "$SOURCE_DIR" && ! -d "$SOURCE_DIR/.git" ]]; then
    fail "managed source exists but is not a Git checkout: ${SOURCE_DIR}"
  fi

  if [[ ! -d "$SOURCE_DIR/.git" ]]; then
    [[ "$OFFLINE" == "false" ]] || fail "offline mode requires an existing checkout: ${SOURCE_DIR}"
    mkdir -p "$(dirname "$SOURCE_DIR")"
    log "Cloning ${UPSTREAM_REPO} into ${SOURCE_DIR}"
    git clone --depth 1 "$UPSTREAM_REPO" "$SOURCE_DIR"
  fi

  if [[ -n "$(git -C "$SOURCE_DIR" status --porcelain --untracked-files=all)" ]]; then
    fail "managed upstream checkout has local changes; refusing to update it: ${SOURCE_DIR}"
  fi

  if [[ "$OFFLINE" == "false" ]]; then
    log "Updating upstream source to ${UPSTREAM_REF}"
    git -C "$SOURCE_DIR" fetch --depth 1 origin "$UPSTREAM_REF"
    git -C "$SOURCE_DIR" checkout --detach FETCH_HEAD >/dev/null
  else
    log "Offline mode uses existing source without fetching: ${SOURCE_DIR}"
  fi
  SOURCE_DIR="$(canonical_dir "$SOURCE_DIR")"
  SOURCE_AVAILABLE="true"
}

validate_selected_sources() {
  local index
  local source_skill

  [[ "$SOURCE_AVAILABLE" == "true" ]] || return 0
  for index in "${!SELECTED_RELATIVE_PATHS[@]}"; do
    source_skill="${SOURCE_DIR}/${SELECTED_RELATIVE_PATHS[$index]}"
    [[ -f "$source_skill/SKILL.md" ]] || fail "missing SKILL.md in selected skill: ${source_skill}"
  done
}

copy_marker_path() {
  printf '%s\n' "$1/.dev-toolbox-agent-setup"
}

managed_copy_matches() {
  local destination="$1"
  local relative_path="$2"
  local marker

  marker="$(copy_marker_path "$destination")"
  [[ -f "$marker" ]] || return 1
  grep -Fqx 'provider=mattpocock' "$marker" &&
    grep -Fqx "skill=${relative_path}" "$marker"
}

is_managed_copy() {
  local destination="$1"
  local marker
  local skill_line

  marker="$(copy_marker_path "$destination")"
  [[ -f "$marker" ]] || return 1
  grep -Fqx 'provider=mattpocock' "$marker" || return 1
  skill_line="$(grep -E '^skill=' "$marker" | head -n 1)"
  [[ -n "$skill_line" ]] || return 1
  [[ "$(basename "${skill_line#skill=}")" == "$(basename "$destination")" ]]
}

managed_symlink_target() {
  local destination="$1"
  local resolved

  resolved="$(portable_link_target "$destination" 2>/dev/null || true)"
  [[ -n "$resolved" ]] || return 1
  path_is_within "$resolved" "$SOURCE_DIR" || return 1
  printf '%s\n' "$resolved"
}

managed_symlink_matches() {
  local destination="$1"
  local expected_source="$2"
  local resolved

  resolved="$(managed_symlink_target "$destination" 2>/dev/null || true)"
  [[ -n "$resolved" && "$resolved" == "$expected_source" ]]
}

is_managed_destination() {
  local destination="$1"
  if [[ -L "$destination" ]]; then
    managed_symlink_target "$destination" >/dev/null
    return
  fi
  [[ -d "$destination" ]] && is_managed_copy "$destination"
}

user_scope_reuses_skill() {
  local agent="$1"
  local relative_path="$2"
  local skill_name="$3"
  local user_destination
  local expected_source

  [[ "$SCOPE" == "project" ]] || return 1
  user_destination="$(agent_user_skills_dir "$agent")/${skill_name}"
  expected_source="${SOURCE_DIR}/${relative_path}"

  if managed_symlink_matches "$user_destination" "$expected_source" ||
    managed_copy_matches "$user_destination" "$relative_path"; then
    return 0
  fi

  if [[ -e "$user_destination" || -L "$user_destination" ]]; then
    fail "project skill conflicts with a different user-scope skill: ${user_destination}"
  fi
  return 1
}

preflight_skills_root() {
  local destination_root="$1"
  if [[ -e "$destination_root" || -L "$destination_root" ]]; then
    [[ -d "$destination_root" ]] || fail "skills root is not a directory: ${destination_root}"
  fi
}

preflight_skill_target() {
  local agent="$1"
  local destination_root
  local index
  local relative_path
  local skill_name
  local source_skill
  local destination

  destination_root="$(agent_skills_dir "$agent")"
  preflight_skills_root "$destination_root"

  if [[ "$SOURCE_AVAILABLE" != "true" ]]; then
    for skill_name in "${SELECTED_NAMES[@]}"; do
      log "Would install ${skill_name} for ${agent} at ${destination_root}/${skill_name} (source unverified)"
    done
    return
  fi

  for index in "${!SELECTED_RELATIVE_PATHS[@]}"; do
    relative_path="${SELECTED_RELATIVE_PATHS[$index]}"
    skill_name="${SELECTED_NAMES[$index]}"
    source_skill="$(canonical_dir "${SOURCE_DIR}/${relative_path}")"
    if user_scope_reuses_skill "$agent" "$relative_path" "$skill_name"; then
      log "Will reuse user-scope skill for project ${agent}: ${skill_name}"
      continue
    fi

    destination="${destination_root}/${skill_name}"
    if [[ ! -e "$destination" && ! -L "$destination" ]]; then
      continue
    fi
    if managed_symlink_matches "$destination" "$source_skill" ||
      managed_copy_matches "$destination" "$relative_path" ||
      is_managed_destination "$destination"; then
      continue
    fi
    fail "skill destination exists and is not managed by this installer: ${destination}"
  done
}

preflight_skills() {
  load_profile_manifest
  resolve_project_root
  prepare_skill_source
  validate_selected_sources
  if target_includes_agent codex; then
    preflight_skill_target codex
  fi
  if target_includes_agent claude; then
    preflight_skill_target claude
  fi
}

write_copy_marker() {
  local destination="$1"
  local relative_path="$2"
  {
    printf '%s\n' 'provider=mattpocock'
    printf 'skill=%s\n' "$relative_path"
  } > "$(copy_marker_path "$destination")"
}

remove_managed_destination() {
  local destination="$1"
  if [[ -L "$destination" ]]; then
    unlink "$destination"
  else
    rm -rf -- "$destination"
  fi
}

install_skill_destination() {
  local agent="$1"
  local relative_path="$2"
  local skill_name="$3"
  local destination_root
  local destination
  local source_skill
  local temp_destination

  destination_root="$(agent_skills_dir "$agent")"
  destination="${destination_root}/${skill_name}"
  source_skill="$(canonical_dir "${SOURCE_DIR}/${relative_path}")"

  if user_scope_reuses_skill "$agent" "$relative_path" "$skill_name"; then
    log "Reused user-scope skill for project ${agent}: ${skill_name}"
    return
  fi

  if is_copy_platform; then
    if [[ "$DRY_RUN" == "true" ]]; then
      if managed_copy_matches "$destination" "$relative_path"; then
        log "Would refresh managed copy: ${destination}"
      elif [[ -e "$destination" || -L "$destination" ]]; then
        log "Would replace managed skill with a copy: ${destination}"
      else
        log "Would copy ${skill_name} for ${agent} to ${destination}"
      fi
      return
    fi

    mkdir -p "$destination_root"
    temp_destination="${destination}.tmp.$$"
    rm -rf -- "$temp_destination"
    mkdir -p "$temp_destination"
    cp -R "${source_skill}/." "$temp_destination/"
    write_copy_marker "$temp_destination" "$relative_path"
    if [[ -e "$destination" || -L "$destination" ]]; then
      is_managed_destination "$destination" || fail "skill destination changed after preflight: ${destination}"
      remove_managed_destination "$destination"
    fi
    mv "$temp_destination" "$destination"
    log "Installed managed copy for ${agent}: ${skill_name}"
    return
  fi

  if managed_symlink_matches "$destination" "$source_skill"; then
    log "Skill already current for ${agent}: ${skill_name}"
    return
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    log "Would link ${skill_name} for ${agent}: ${destination} -> ${source_skill}"
    return
  fi
  if [[ -e "$destination" || -L "$destination" ]]; then
    remove_managed_destination "$destination"
  fi
  mkdir -p "$destination_root"
  ln -s "$source_skill" "$destination"
  log "Installed skill for ${agent}: ${skill_name} -> ${source_skill}"
}

selected_name_exists() {
  local candidate="$1"
  local selected
  for selected in "${SELECTED_NAMES[@]}"; do
    [[ "$selected" != "$candidate" ]] || return 0
  done
  return 1
}

prune_managed_skills() {
  local agent="$1"
  local destination_root
  local destination
  local skill_name

  destination_root="$(agent_skills_dir "$agent")"
  [[ -d "$destination_root" ]] || return 0

  shopt -s nullglob
  for destination in "$destination_root"/*; do
    skill_name="$(basename "$destination")"
    selected_name_exists "$skill_name" && continue
    is_managed_destination "$destination" || continue
    if [[ "$DRY_RUN" == "true" ]]; then
      log "Would remove managed skill outside profile '${PROFILE}': ${destination}"
    else
      remove_managed_destination "$destination"
      log "Removed managed skill outside profile '${PROFILE}': ${destination}"
    fi
  done
  shopt -u nullglob
}

apply_skills_for_agent() {
  local agent="$1"
  local index

  prune_managed_skills "$agent"
  for index in "${!SELECTED_RELATIVE_PATHS[@]}"; do
    install_skill_destination "$agent" "${SELECTED_RELATIVE_PATHS[$index]}" "${SELECTED_NAMES[$index]}"
  done
}

skill_source_revision() {
  if [[ "$SOURCE_AVAILABLE" != "true" ]]; then
    printf '%s\n' 'unverified source'
  elif [[ -d "$SOURCE_DIR/.git" ]]; then
    git -C "$SOURCE_DIR" rev-parse --short HEAD 2>/dev/null || printf '%s\n' 'unknown revision'
  else
    printf '%s\n' 'external checkout'
  fi
}

apply_skills() {
  if [[ "$SOURCE_AVAILABLE" == "true" ]]; then
    if target_includes_agent codex; then
      apply_skills_for_agent codex
    fi
    if target_includes_agent claude; then
      apply_skills_for_agent claude
    fi
  fi
  log "Skill profile '${PROFILE}' (${SCOPE}, ${AGENT_TARGET}) is ready from $(skill_source_revision)."
  if [[ "$SCOPE" == "user" ]] && command -v warn_if_timer_configuration_differs >/dev/null 2>&1; then
    warn_if_timer_configuration_differs
  fi
}

install_skills() {
  preflight_skills
  apply_skills
}
