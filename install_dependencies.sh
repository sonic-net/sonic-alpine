#!/bin/bash
set -e

echo "--- Configuring Apt ---"

# Dynamically set sudo if the script is not being run as root
SUDO=''
if [ "$(id -u)" -ne 0 ]; then
  SUDO='sudo'
fi

# Force IPv4 for apt to prevent hanging on CI runners
echo 'Acquire::ForceIPv4 "true";' | $SUDO tee /etc/apt/apt.conf.d/99force-ipv4 > /dev/null

echo "--- Updating package lists ---"
$SUDO apt-get update

echo "--- Installing build dependencies ---"
# Combined list covering needs for both build-native and build-docker jobs
$SUDO apt-get install -y \
    curl \
    sudo \
    ca-certificates \
    jq \
    dpkg \
    nodejs \
    make \
    build-essential \
    debhelper \
    libnl-3-dev \
    libnl-genl-3-dev \
    golang-any

echo "--- Dependencies installed successfully ---"
