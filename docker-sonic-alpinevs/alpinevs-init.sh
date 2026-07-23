#!/bin/bash -e
# Script to setup docker-sonic-alpinevs on init

platform="${HWSKU:-alpinevs}"

# Alpine platform custom daemon control.
if [ -f "/usr/share/sonic/device/x86_64-kvm_x86_64-r0/${platform}/pmon_daemon_control.json" ]; then
    rm -f /usr/share/sonic/device/x86_64-kvm_x86_64-r0/pmon_daemon_control.json
    cp "/usr/share/sonic/device/x86_64-kvm_x86_64-r0/${platform}/pmon_daemon_control.json" \
       "/usr/share/sonic/device/x86_64-kvm_x86_64-r0/pmon_daemon_control.json"
fi

exit 0
