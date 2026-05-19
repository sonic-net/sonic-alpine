#!/usr/bin/env bash

export platform=vs

SWSS_VARS_FILE=/usr/share/sonic/templates/swss_vars.j2
SWSS_VARS=$(sonic-cfggen -d -y /etc/sonic/sonic_version.yml -t $SWSS_VARS_FILE) || exit 1

MAC_ADDRESS=$(echo $SWSS_VARS | jq -r '.mac')
if [ "$MAC_ADDRESS" == "None" ] || [ -z "$MAC_ADDRESS" ]; then
    MAC_ADDRESS=$(ip link show eth0 | grep ether | awk '{print $2}')
    logger "Mac address not found in Device Metadata, Falling back to eth0"
fi

mkdir -p /var/log/swss
ORCHAGENT_ARGS="-d /var/log/swss "

# Alpine always uses switch type (not dpu)
ORCHAGENT_ARGS+="-b 8192 "

# Alpine config_db has synchronous_mode=enable and zmq_mode=enable
SYNC_MODE=$(echo $SWSS_VARS | jq -r '.synchronous_mode')
ZMQ_MODE=$(echo $SWSS_VARS | jq -r '.zmq_mode')

if [ "$ZMQ_MODE" == "enable" ]; then
    ORCHAGENT_ARGS+="-z zmq_sync "
elif [ "$SYNC_MODE" == "enable" ]; then
    ORCHAGENT_ARGS+="-s "
fi

ORCHDAEMON_RING_ENABLED=`sonic-db-cli CONFIG_DB hget "DEVICE_METADATA|localhost" "ring_thread_enabled"`
if [[ x"${ORCHDAEMON_RING_ENABLED}" == x"true" ]]; then
    ORCHAGENT_ARGS+="-R "
fi

ORCHAGENT_ARGS+="-m $MAC_ADDRESS"

exec /usr/bin/orchagent ${ORCHAGENT_ARGS}
