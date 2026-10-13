#!/bin/bash -e

CURRENT_HOSTNAME=$(hostname)
HOSTNAME=$(sonic-db-cli CONFIG_DB HGET 'DEVICE_METADATA|localhost' hostname)

if [ -z "$HOSTNAME" ] ; then
       echo "Missing hostname in the config file, setting to default 'sonic'"
       HOSTNAME='sonic'
fi

echo "$HOSTNAME" > /etc/hostname
hostname -F /etc/hostname

# Don't update /etc/hosts if hostname is not changed
# This is to prevent intermittent redis_chassis.server reachability issue
if [ "$CURRENT_HOSTNAME" = "$HOSTNAME" ] ; then
    return 0 2>/dev/null || exit 0
fi

# Remove the old hostname entry from /etc/hosts in-place (if not localhost)
if [ "$CURRENT_HOSTNAME" != "localhost" ] ; then
    UPDATED_HOSTS=$(sed "/\s${CURRENT_HOSTNAME}$/d" /etc/hosts)
    echo "$UPDATED_HOSTS" > /etc/hosts
fi

# Append the new hostname entry directly
echo "127.0.0.1 $HOSTNAME" >> /etc/hosts
