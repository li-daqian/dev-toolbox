#!/bin/sh
set -eu

DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"

TARGET_DIR="$HOME/Docker/pg"

mkdir -p "$TARGET_DIR"
cp "$DIR/docker-compose.yml" "$TARGET_DIR/"
cp "$DIR/start.sh" "$TARGET_DIR/"
