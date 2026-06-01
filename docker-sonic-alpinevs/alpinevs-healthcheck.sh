#!/bin/bash

set -u

FAILURES=0
WARNINGS=0

info() {
    echo "INFO: $*"
}

pass() {
    echo "PASS: $*"
}

warn() {
    echo "WARN: $*"
    WARNINGS=$((WARNINGS + 1))
}

fail() {
    echo "FAIL: $*"
    FAILURES=$((FAILURES + 1))
}

check_file() {
    local path="$1"

    if [ -e "$path" ]; then
        pass "found $path"
    else
        fail "missing $path"
    fi
}

check_executable() {
    local path="$1"

    if [ -x "$path" ]; then
        pass "found executable $path"
    elif [ -e "$path" ]; then
        fail "$path exists but is not executable"
    else
        fail "missing executable $path"
    fi
}

supervisor_has_program() {
    local program="$1"

    supervisorctl status "$program" >/dev/null 2>&1
}

check_supervisor_running() {
    local program="$1"
    local status

    if ! status=$(supervisorctl status "$program" 2>/dev/null); then
        fail "supervisor program $program is not defined"
        return
    fi

    if echo "$status" | grep -q "RUNNING"; then
        pass "supervisor program $program is running"
    else
        fail "supervisor program $program is not running: $status"
    fi
}

trim_supervisor_status() {
    local program="$1"
    local status="$2"

    echo "$status" | sed -E "s/^$program[[:space:]]+//"
}

check_supervisor_running_or_exited() {
    local program="$1"
    local status

    status=$(supervisorctl status "$program" 2>/dev/null || true)

    if [ -z "$status" ]; then
        fail "supervisor program $program is not defined"
    elif echo "$status" | grep -Eq "RUNNING|EXITED"; then
        status=$(trim_supervisor_status "$program" "$status")
        pass "supervisor program $program is healthy. Status: $status"
    else
        fail "supervisor program $program is not healthy: $status"
    fi
}

check_supervisor_defined() {
    local program="$1"
    local status

    status=$(supervisorctl status "$program" 2>/dev/null || true)
    if [ -n "$status" ]; then
        status=$(trim_supervisor_status "$program" "$status")
        pass "supervisor program $program is defined. Status: $status"
    else
        fail "supervisor program $program is not defined"
    fi
}

check_supervisor_any_running() {
    local label="$1"
    shift
    local program
    local status

    for program in "$@"; do
        if status=$(supervisorctl status "$program" 2>/dev/null); then
            if echo "$status" | grep -q "RUNNING"; then
                pass "supervisor program $label is running as $program"
                return
            fi
        fi
    done

    for program in "$@"; do
        if supervisor_has_program "$program"; then
            status=$(supervisorctl status "$program" 2>/dev/null || true)
            fail "supervisor program $label is defined but not running: $status"
            return
        fi
    done

    fail "none of the supervisor programs for $label are defined: $*"
}

check_process() {
    local label="$1"
    local pattern="$2"

    if ps -ef | grep -E "$pattern" | grep -v grep >/dev/null 2>&1; then
        pass "process $label is present"
    else
        fail "process $label is missing"
    fi
}

check_process_any() {
    local label="$1"
    shift
    local pattern

    for pattern in "$@"; do
        if ps -ef | grep -E "$pattern" | grep -v grep >/dev/null 2>&1; then
            pass "process $label is present"
            return
        fi
    done

    fail "process $label is missing"
}

check_json() {
    local path="$1"

    if [ ! -f "$path" ]; then
        fail "cannot parse missing JSON file $path"
        return
    fi

    if command -v python3 >/dev/null 2>&1; then
        if python3 -m json.tool "$path" >/dev/null 2>&1; then
            pass "valid JSON $path"
        else
            fail "invalid JSON $path"
        fi
    elif command -v jq >/dev/null 2>&1; then
        if jq empty "$path" >/dev/null 2>&1; then
            pass "valid JSON $path"
        else
            fail "invalid JSON $path"
        fi
    else
        warn "skipping JSON validation for $path; python3 and jq are unavailable"
    fi
}

check_syslog() {
    local path="/var/log/syslog"
    local pattern="(segmentation fault|abrt|segv|traceback|panic|fatal|critical|cannot initialize system|supervisor:.*ERROR)"

    if [ ! -f "$path" ]; then
        warn "$path is not present; skipping syslog scan"
        return
    fi

    if tail -n 300 "$path" | grep -Ei "$pattern" >/dev/null 2>&1; then
        fail "recent syslog contains startup error patterns"
        tail -n 300 "$path" | grep -Ei "$pattern" | tail -n 20
    else
        pass "no recent critical startup patterns found in $path"
    fi
}

info "checking required AlpineVS files"
check_executable /usr/bin/start.sh
check_executable /usr/bin/alpinevs-script.sh
check_executable /usr/bin/alpinevs-init.sh
check_executable /usr/bin/alpinevs-config.sh
check_executable /usr/bin/pkt-handler
check_file /etc/sonic/config_db.json
check_file /etc/sonic/copp_cfg.json
check_file /etc/default/sonic-db/database_config.json
check_file /var/run/redis/sonic-db/database_config.json
check_file /etc/sai.d/sai.profile
check_file /usr/share/sonic/platform
check_file /usr/share/sonic/hwsku

info "checking JSON configuration"
check_json /etc/sonic/config_db.json
check_json /etc/sonic/copp_cfg.json
check_json /etc/default/sonic-db/database_config.json
check_json /var/run/redis/sonic-db/database_config.json

info "checking supervisor programs"
check_supervisor_running_or_exited start.sh
check_supervisor_running rsyslogd
check_supervisor_running redis-server
check_supervisor_running syncd
check_supervisor_running portsyncd
check_supervisor_running orchagent
check_supervisor_running coppmgrd
check_supervisor_running neighsyncd
check_supervisor_running fdbsyncd
check_supervisor_running vlanmgrd
check_supervisor_running intfmgrd
check_supervisor_running buffermgrd
check_supervisor_running vrfmgrd
check_supervisor_running portmgrd
check_supervisor_running nbrmgrd
check_supervisor_running vxlanmgrd
check_supervisor_running tunnelmgrd
check_supervisor_running fabricmgrd
check_supervisor_running rebootbackend
check_supervisor_running p4rt
check_supervisor_any_running telemetry gnmi telemetry
check_supervisor_defined alpine

info "checking processes"
check_process rsyslogd "/usr/sbin/rsyslogd"
check_process redis-server "/usr/bin/redis-server|[[:space:]]redis-server[[:space:]]"
check_process syncd "syncd"
check_process portsyncd "portsyncd"
check_process orchagent "orchagent"
check_process coppmgrd "coppmgrd"
check_process neighsyncd "neighsyncd"
check_process fdbsyncd "fdbsyncd"
check_process vlanmgrd "vlanmgrd"
check_process intfmgrd "intfmgrd"
check_process buffermgrd "buffermgrd"
check_process vrfmgrd "vrfmgrd"
check_process portmgrd "portmgrd"
check_process nbrmgrd "nbrmgrd"
check_process vxlanmgrd "vxlanmgrd"
check_process tunnelmgrd "tunnelmgrd"
check_process fabricmgrd "fabricmgrd"
check_process rebootbackend "rebootbackend"
check_process p4rt "/usr/local/bin/p4rt|[[:space:]]p4rt[[:space:]]"
check_process_any telemetry "/usr/sbin/telemetry" "[[:space:]]telemetry[[:space:]]"
check_process_any alpine-services "pkt-handler"

info "checking logs"
check_syslog

echo
echo "AlpineVS healthcheck summary: ${FAILURES} failure(s), ${WARNINGS} warning(s)"

if [ "$FAILURES" -ne 0 ]; then
    exit 1
fi

exit 0
