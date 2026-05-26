#!/bin/bash -e
# Script to setup AlpineVS switch on init

# Copy the config_db.json
mkdir -p /mnt/config
mount -t 9p configfolder /mnt/config && {

    # If config_db.json is passed, then copy it to the right destination
    # and also remove alpinevs_ports.json which should not be used with
    # external config
    if [ -f /mnt/config/config_db.json ]; then
        platform=$(grep -oP '"hwsku": "([^"]*)"' /mnt/config/config_db.json | cut -d'"' -f 4)
        if [[ ! "${platform}" =~ "alpine" ]]; then
            echo "Ignore the passed config because it is not a Google Alpine platform!";
            umount /mnt/config
            exit 0
        fi
        rm -f /etc/sonic/alpinevs_ports.json
        # On init, copy config passed in topology to config_db.json.
        # Any changes in config_db.json should persist through subsequent reboots.
        if [ ! -f /etc/sonic/config_db.json ]; then
            cp /mnt/config/config_db.json /etc/sonic/config_db.json
        fi
        sed -i 's/^.*$/'"${platform}"'/g' /usr/share/sonic/device/x86_64-kvm_x86_64-r0/default_sku
    fi
    umount /mnt/config
}

# If pkt handler is present, install it
if [ -f /usr/bin/lucius-pkthandler_latest.deb ]; then
    dpkg -i /usr/bin/lucius-pkthandler_latest.deb
fi

# Google Alpine platform custom daemon control.
if [ -f "/usr/share/sonic/device/x86_64-kvm_x86_64-r0/${platform}/pmon_daemon_control.json" ]; then
    rm -f /usr/share/sonic/device/x86_64-kvm_x86_64-r0/pmon_daemon_control.json
    cp "/usr/share/sonic/device/x86_64-kvm_x86_64-r0/${platform}/pmon_daemon_control.json" "/usr/share/sonic/device/x86_64-kvm_x86_64-r0/pmon_daemon_control.json"
fi

# Create symlink for config CLI

ln -sf /usr/local/bin/config /usr/bin/config
