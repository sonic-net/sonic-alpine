#!/bin/bash -ex

/usr/bin/alpinevs-init.sh

# Wait for Redis to be responsive
echo "Waiting for Redis to start..."
MAX_RETRIES=30
COUNT=0
while ! redis-cli ping > /dev/null 2>&1; do
    sleep 1
    COUNT=$((COUNT + 1))
    if [ $COUNT -ge $MAX_RETRIES ]; then
        echo "Redis failed to start in $MAX_RETRIES seconds. Exiting."
        exit 1
    fi
done
echo "Redis is up. Proceeding with configuration."

exec /usr/bin/alpinevs-config.sh
