#!/bin/bash
set -euo pipefail

PORT="${LUCIUS_PORT:-50000}"

echo "Starting Lucius on 127.0.01:${PORT}"
exec /usr/bin/lucius --port "${PORT}"
