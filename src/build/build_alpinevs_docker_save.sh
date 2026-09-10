#!/bin/bash
set -eo pipefail

IMAGE_FILE="target/sonic-alpinevs.img.gz"
VM_DIR="platform/alpinevs/src/deploy/kne/vm"
MAX_RETRIES=3
RETRY_DELAY=5

# 1. Check if input image exists before proceeding
if [ ! -f "$IMAGE_FILE" ]; then
    echo "ERROR: File '$IMAGE_FILE' not found. Please run the build to produce sonic-alpinevs.img.gz first." >&2
    exit 1
fi

# 2. Decompress input image
mkdir -p "$VM_DIR"
gzip -d -c "$IMAGE_FILE" > "$VM_DIR/vm.img"

# 3. Ensure Docker service is running
sudo service docker status > /dev/null 2>&1 || (sudo service docker start > /dev/null 2>&1 && ./scripts/wait_for_docker.sh 60)

# 4. Docker build with retry logic for network/package retrieval failures
build_passed=0
for ((i=1; i<=MAX_RETRIES; i++)); do
    echo "Building docker image 'alpine-vs:latest' (Attempt $i/$MAX_RETRIES)..."
    if DOCKER_BUILDKIT=0 docker build "$VM_DIR" -t alpine-vs:latest; then
        build_passed=1
        echo "Docker build succeeded."
        break
    else
        echo "WARNING: Docker build failed on attempt $i." >&2
        if [ $i -lt $MAX_RETRIES ]; then
            echo "Retrying in ${RETRY_DELAY} seconds..." >&2
            sleep $RETRY_DELAY
        fi
    fi
done

if [ $build_passed -ne 1 ]; then
    echo "ERROR: Docker build failed after $MAX_RETRIES attempts." >&2
    exit 1
fi

# 5. Save the final image tarball
mkdir -p target
docker save alpine-vs:latest | gzip -c > target/sonic-alpinevs-docker.tar.gz

echo "Successfully built and exported target/sonic-alpinevs-docker.tar.gz"
