#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/image_utils.sh"

download_official_image_file \
    "target/docker-sonic-alpinevs.gz" \
    "docker-sonic-alpinevs-{build_id}.gz"
