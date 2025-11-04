#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source ../.env
: "${OTG_API:?Missing OTG_API in .env}"
: "${OTG_LOCATION_P1:=eth1}"
: "${OTG_LOCATION_P2:=eth2}"
: "${OTG_LOCATION_P3:=eth3}"
: "${OTG_LOCATION_P4:=eth4}"
# 1) Apply & send traffic for a finite count
otgen create flow -n sanity \
  -s 1.1.1.1 -d 2.2.2.2 --size 512 -r 5000 -c 20000 \
  --tx p1 --rx p2 --txl "$OTG_LOCATION_P1" --rxl "$OTG_LOCATION_P2" \
| otgen run -k -a "$OTG_API" -y -m port \
| otgen transform -m port \
| env TERM=dumb timeout 6s env TERM=dumb timeout 6s otgen display --mode table


otgen create flow -n sanity \
  -s 1.1.1.1 -d 2.2.2.2 --size 512 -r 5000 -c 20000 \
  --tx p3 --rx p4 --txl "$OTG_LOCATION_P3" --rxl "$OTG_LOCATION_P4" \
| otgen run -k -a "$OTG_API" -y -m port \
| otgen transform -m port \
| env TERM=dumb timeout 6s env TERM=dumb timeout 6s otgen display --mode table
