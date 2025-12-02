#!/bin/sh
set -e

SCRIPT_DIR=$(dirname "$0")
cd "$SCRIPT_DIR"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "Docker is not running, please start Docker first."
    exit 1
fi

# Start PostgreSQL service
docker-compose up -d

echo "PostgreSQL service has been started."
