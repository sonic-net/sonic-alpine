#!/bin/bash -ex

ln -sf /usr/share/sonic/device/$PLATFORM /usr/share/sonic/platform
ln -sf /usr/share/sonic/device/$PLATFORM/$HWSKU /usr/share/sonic/hwsku

SWITCH_TYPE=switch
PLATFORM_CONF=platform.json
export PLATFORM=${PLATFORM:-"x86_64-kvm_x86_64-r0"}

[ -d /etc/sonic ] || mkdir -p /etc/sonic

mkdir -p /var/run/redis/sonic-db
cp /etc/default/sonic-db/database_config.json /var/run/redis/sonic-db/

# Install Alpine SAI profile for lucius
mkdir -p /etc/sai.d/
cp /usr/share/sonic/hwsku/sai.profile /etc/sai.d/sai.profile

SYSTEM_MAC_ADDRESS=$(ip link show eth0 | grep ether | awk '{print $2}')
sonic-cfggen -t /usr/share/sonic/templates/init_cfg.json.j2 -a "{\"system_mac\": \"$SYSTEM_MAC_ADDRESS\", \"switch_type\": \"$SWITCH_TYPE\"}" > /etc/sonic/init_cfg.json

if [[ -f /usr/share/sonic/virtual_chassis/default_config.json ]]; then
    sonic-cfggen -j /etc/sonic/init_cfg.json -j /usr/share/sonic/virtual_chassis/default_config.json --print-data > /tmp/init_cfg.json
    mv /tmp/init_cfg.json /etc/sonic/init_cfg.json
fi

# Sree - new processing of config_db.json
if [ -f /etc/sonic/config_db.json ]; then
    # Merge basic system init properties into config_db.json
    sonic-cfggen -j /etc/sonic/init_cfg.json -j /etc/sonic/config_db.json --print-data > /tmp/config_db.json
    mv /tmp/config_db.json /etc/sonic/config_db.json
    echo "Using existing config_db.json"
else
    echo "ERROR: /etc/sonic/config_db.json is missing! Cannot initialize system."
    exit 1
fi

sonic-cfggen -t /usr/share/sonic/templates/copp_cfg.j2 > /etc/sonic/copp_cfg.json

mkdir -p /etc/swss/config.d/

rm -f /var/run/rsyslogd.pid

supervisorctl start rsyslogd

supervisord_cfg="/etc/supervisor/conf.d/supervisord.conf"
chassisdb_cfg_file="/usr/share/sonic/virtual_chassis/default_config.json"
chassisdb_cfg_file_default="/etc/default/sonic-db/default_chassis_cfg.json"
host_template="/usr/share/sonic/templates/hostname.j2"
db_cfg_file="/var/run/redis/sonic-db/database_config.json"
db_cfg_file_tmp="/var/run/redis/sonic-db/database_config.json.tmp"

if [ -r "$chassisdb_cfg_file" ]; then
   echo $(sonic-cfggen -j $chassisdb_cfg_file -t $host_template) >> /etc/hosts
else
   chassisdb_cfg_file="$chassisdb_cfg_file_default"
   echo "10.8.1.200 redis_chassis.server" >> /etc/hosts
fi

supervisorctl start redis-server

start_chassis_db=`sonic-cfggen -v DEVICE_METADATA.localhost.start_chassis_db -y $chassisdb_cfg_file`
if [[ "$HOSTNAME" == *"supervisor"* ]] || [ "$start_chassis_db" == "1" ]; then
   supervisorctl start redis-chassis
fi

conn_chassis_db=`sonic-cfggen -v DEVICE_METADATA.localhost.connect_to_chassis_db -y $chassisdb_cfg_file`
if [ "$start_chassis_db" != "1" ] && [ "$conn_chassis_db" != "1" ]; then
   cp $db_cfg_file $db_cfg_file_tmp
   update_chassisdb_config -j $db_cfg_file_tmp -d
   cp $db_cfg_file_tmp $db_cfg_file
fi

/usr/bin/configdb-load.sh

supervisorctl start syncd
supervisorctl start portsyncd
supervisorctl start orchagent
supervisorctl start coppmgrd
supervisorctl start neighsyncd
supervisorctl start fdbsyncd
supervisorctl start vlanmgrd
supervisorctl start intfmgrd
supervisorctl start buffermgrd
supervisorctl start vrfmgrd
supervisorctl start portmgrd
supervisorctl start nbrmgrd
supervisorctl start vxlanmgrd
supervisorctl start tunnelmgrd
supervisorctl start fabricmgrd
supervisorctl start rebootbackend
supervisorctl start p4rt
supervisorctl start telemetry
supervisorctl start alpine

VLAN=`sonic-cfggen -d -v 'VLAN.keys() | join(" ") if VLAN'`
if [ "$VLAN" != "" ]; then
    supervisorctl start arp_update
fi
