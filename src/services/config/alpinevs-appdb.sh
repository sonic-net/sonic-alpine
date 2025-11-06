#!/bin/bash -e
# Creates PORT_TABLE:CPU in APPL_STATE_DB.

redis-cli -n 14 hmset "PORT_TABLE:CPU" "NULL" "NULL"