#!/bin/bash -ex

# This script now calls pkt-handler at the end and blocks. Because of this,
# alpinevs-healthcheck.sh expects the script to be always running.
# If pkt-handler is made to run in the background and this script terminates
# modify the health script, perhaps handling this as a special case.

/usr/bin/alpinevs-init.sh
/usr/bin/alpinevs-config.sh
