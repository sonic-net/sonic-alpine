#!/bin/bash
set -euo pipefail

TARGET="${SOC_TARGET_SERVER:-127.0.0.1:50000}"
HOST="${TARGET%:*}"
PORT="${TARGET##*:}"

for _ in $(seq 1 30); do
    if timeout 1 bash -c "</dev/tcp/${HOST}/${PORT}" 2>/dev/null; then
        exit 0
    fi
    sleep 1
done

echo "Lucius did not become ready at ${TARGET}" >&2
exit 1


