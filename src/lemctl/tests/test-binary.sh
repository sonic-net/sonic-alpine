#!/bin/bash
set -euo pipefail

binary=${1:?Usage: test-binary.sh /path/to/lemctl}
output=$(mktemp)
trap 'rm -f "$output"' EXIT

reject() {
    expected=$1
    shift
    status=0
    timeout 10 "$binary" lucius "$@" >"$output" 2>&1 || status=$?
    if [ "$status" -ne 1 ]; then
        cat "$output" >&2
        echo "Expected policy rejection with exit 1, got $status: $*" >&2
        exit 1
    fi
    if ! grep '^Error:' "$output" | grep -F "$expected"; then
        cat "$output" >&2
        echo "Missing expected rejection: $expected" >&2
        exit 1
    fi
}

for command in info sai; do
    if [ "$command" = info ]; then
        args=(info list)
    else
        args=(sai get-attr switch 1 cpu_port)
    fi
    reject "no longer supported" --tls_skip_verify "${args[@]}"
    reject "literal loopback" --insecure --address 192.0.2.1:50000 "${args[@]}"
    reject "literal loopback" --insecure --address dns:///127.0.0.1:50000 "${args[@]}"
done
