#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/image_utils.sh"

download_official_artifact_archive \
    "sonic-buildimage.alpinevs-{build_id}.zip"
