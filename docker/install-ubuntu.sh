#!/bin/sh
set -eu

DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"

command_exists() {
  command -v "$@" >/dev/null 2>&1
}

# Install Docker
if ! command_exists docker; then
    echo "Docker is not installed. Installing Docker ..."
    # Add Docker's official GPG key:
    sudo apt update
    sudo apt -y install ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Add current user to docker group to avoid using 'sudo' for docker commands
    sudo groupadd docker || true
    sudo usermod -aG docker "$USER"
    newgrp docker
else
    echo "Docker is already installed. Skipping Docker installation."
fi
