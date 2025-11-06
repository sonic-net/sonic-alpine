#!/usr/bin/env python2

"""
    Fake xcvrd
    Fake transceiver information update daemon for SONiC Alpine
"""

from sonic_py_common import daemon_base, logger, interface
from swsscommon import swsscommon

SYSLOG_IDENTIFIER = "xcvrd"
PORT_TABLE = 'PORT_TABLE'
XCVRD_MAIN_THREAD_SLEEP_SECS = 60
SELECT_TIMEOUT_MSECS = 1000

COMPONENT_NAME = "pmon:xcvrd"
VERIFY_STATE_REQ_CHANNEL = "VERIFY_STATE_REQ_CHANNEL"

# Global logger instance for helper functions and classes
helper_logger = logger.Logger(SYSLOG_IDENTIFIER)
helper_logger.set_min_log_priority_info()


#
# Daemon =======================================================================
#

class DaemonXcvrd(daemon_base.DaemonBase):
    def __init__(self, log_identifier):
        super(DaemonXcvrd, self).__init__(log_identifier)

        self.timeout = XCVRD_MAIN_THREAD_SLEEP_SECS

    def _process_appl_state_port_table_event(self, logical_port, op, fvp, port_cache,
                                             appl_state_port_tbl, app_port_tbl):
        """Reacts to change in PORT_TABLE in APPL_STATE_DB."""

        if logical_port.startswith(interface.backplane_prefix()):
            helper_logger.log_info("Skip _process_appl_state_port_table_event for "
                                   "logical port {}".format(logical_port))
            return

        if logical_port not in port_cache:
            app_port_tbl_fvs = swsscommon.FieldValuePairs([("presence", "1")])
            app_port_tbl.set(logical_port, app_port_tbl_fvs)

            helper_logger.log_info("Set presence for logical_port {}".format(logical_port))

        if op == swsscommon.SET_COMMAND:
            if not fvp:
                return
            port_cache.add(logical_port)
        elif op == swsscommon.DEL_COMMAND:
            port_cache.remove(logical_port)

    def _process_state_verification_notification_channel(
            self, sv_ntf_consumer, verify_state_tbl):
        if not sv_ntf_consumer.hasData():
            return

        try:
            (channel_op, channel_data, channel_fvp) = sv_ntf_consumer.pop()
        except RuntimeError as run_time_error:
            # RuntimeError("notification queue is empty, can't pop")
            helper_logger.log_error(
                "Unexpected runtime error {} received in "
                "_process_state_verification_notification_channel".format(
                    run_time_error))
            return

        if channel_op != COMPONENT_NAME:
            return

        helper_logger.log_info(
            "Process state verification notification channel with op: {}, data: {}, "
            "fvp: {}".format(channel_op, channel_data, channel_fvp))

        verify_state_fvp = swsscommon.FieldValuePairs([
            ("status", "pass"),
            ("timestamp", channel_data),
            ("err_str", "")])
        verify_state_tbl.set(channel_op, verify_state_fvp)
        helper_logger.log_info(
            "State verification finished with status pass at timestamp {} ".format(
                channel_data))

    # Run daemon
    def run(self):
        helper_logger.log_info(
            "Start notification channel and DB change subscribing loop"
        )

        # Initialize database objects
        sel = swsscommon.Select()
        appl_db = daemon_base.db_connect("APPL_DB")
        appl_state_db = daemon_base.db_connect("APPL_STATE_DB")
        state_db = daemon_base.db_connect("STATE_DB")

        appl_state_port_subscriber_tbl = (
            swsscommon.SubscriberStateTable(appl_state_db, PORT_TABLE)
        )
        app_port_tbl = swsscommon.ProducerStateTable(
            appl_db, swsscommon.APP_PORT_TABLE_NAME)
        appl_state_port_tbl = swsscommon.Table(appl_state_db, PORT_TABLE)
        sel.addSelectable(appl_state_port_subscriber_tbl)

        verify_state_tbl = swsscommon.Table(state_db, "VERIFY_STATE_RESP_TABLE")

        sv_ntf_consumer = swsscommon.NotificationConsumer(
            state_db, VERIFY_STATE_REQ_CHANNEL)
        sel.addSelectable(sv_ntf_consumer)

        # Initialize port cache with ports in app state db
        port_cache = set(appl_state_port_tbl.getKeys())

        # Listen indefinitely for Redis DB notifications
        while True:
            (state, selectableObj) = sel.select(SELECT_TIMEOUT_MSECS)

            if state == swsscommon.Select.TIMEOUT:
                # Do not flood log when select times out
                continue
            if state != swsscommon.Select.OBJECT:
                helper_logger.log_warning("sel.select() did not return "
                                          "swsscommon.Select.OBJECT")
                continue

            # Get the right selectable object
            is_redis_select = True
            selectObj = swsscommon.CastSelectableToRedisSelectObj(selectableObj)
            if selectObj is None:
                # The select object is NotificationConsumer instead of RedisSelect.
                is_redis_select = False
                selectObj = swsscommon.CastSelectableToNotificationConsumerObj(
                    selectableObj)
                if selectObj is None:
                    helper_logger.log_error("Found None type selectObj")
                    continue

            if is_redis_select:
                # Pop DB change
                redis_event_list = swsscommon.transpose_pops(
                    appl_state_port_subscriber_tbl.pops())
                for key, op, fvp in redis_event_list:
                    self._process_appl_state_port_table_event(
                        key, op, fvp, port_cache, appl_state_port_tbl, app_port_tbl)
            else:
                self._process_state_verification_notification_channel(
                    sv_ntf_consumer, verify_state_tbl)

        helper_logger.log_info(
            "Stop notification channel and DB change subscribing loop"
        )

#
# Main =========================================================================
#

def main():
    xcvrd = DaemonXcvrd(SYSLOG_IDENTIFIER)
    xcvrd.run()

if __name__ == '__main__':
    main()
