#!/bin/bash -e
# Script to setup docker-sonic-alpinevs on init

# docker-sonic-alpinevs uses the config staged into the image and the HWSKU
# passed through the container environment rather than the sonic-alpine
# configfolder mount path.
platform="${HWSKU:-alpinevs}"

# Google Alpine platform custom daemon control.
if [ -f "/usr/share/sonic/device/x86_64-kvm_x86_64-r0/${platform}/pmon_daemon_control.json" ]; then
    rm -f /usr/share/sonic/device/x86_64-kvm_x86_64-r0/pmon_daemon_control.json
    cp "/usr/share/sonic/device/x86_64-kvm_x86_64-r0/${platform}/pmon_daemon_control.json" \
       "/usr/share/sonic/device/x86_64-kvm_x86_64-r0/pmon_daemon_control.json"
fi

exit 0
