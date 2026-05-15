#!/bin/sh
set -eu

RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/li-daqian/dev-toolbox/main}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || pwd)"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

run_repo_script() {
  script_path="$1"
  runner="$2"
  local_path="$SCRIPT_DIR/$script_path"

  if ! command_exists "$runner"; then
    echo "$runner is required to run $script_path."
    exit 1
  fi

  if [ -f "$local_path" ]; then
    exec "$runner" "$local_path"
  fi

  if ! command_exists curl; then
    echo "curl is required to download $script_path."
    exit 1
  fi

  curl -fsSL "$RAW_BASE/$script_path?$(date +%s)" | "$runner"
}

detect_os() {
  if [ "$(uname -s)" != "Linux" ]; then
    echo "unsupported"
    return
  fi

  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release

    case "${ID:-}" in
      ubuntu)
        echo "ubuntu"
        return
        ;;
    esac

    case " ${ID_LIKE:-} " in
      *" ubuntu "*)
        echo "ubuntu"
        return
        ;;
    esac
  fi

  echo "unsupported"
}

case "$(detect_os)" in
  ubuntu)
    run_repo_script "ubuntu/bootstrap.sh" bash
    ;;
  *)
    echo "Unsupported OS. Only Ubuntu is supported."
    exit 1
    ;;
esac
