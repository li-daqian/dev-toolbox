#!/bin/sh
set -eu

SCRIPT_DIR=$(dirname "$0")
cd "$SCRIPT_DIR"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "Docker is not running, please start Docker first."
    exit 1
fi

# Start Redis service
docker compose up -d

echo "Redis service has been started."
