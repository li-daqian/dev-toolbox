#!/usr/bin/env bash
set -euo pipefail

mode="${1:-area}"

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 127
  fi
}

copy_png_to_clipboard() {
  xclip -selection clipboard -target image/png -i
}

need_cmd import
need_cmd xclip

case "$mode" in
  area)
    # ImageMagick writes PNG bytes to stdout, so no screenshot file is created.
    import png:- | copy_png_to_clipboard
    ;;
  screen)
    import -window root png:- | copy_png_to_clipboard
    ;;
  *)
    printf 'Usage: %s [area|screen]\n' "$0" >&2
    exit 64
    ;;
esac
