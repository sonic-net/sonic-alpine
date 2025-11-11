"""Platform specific class for interaction with LED."""
import copy
import enum
import logging
import sys
import typing
from typing import Optional, Union

from sonic_platform_base.led_base import LedBase

logger = logging.getLogger(__name__)

ADMIN_STATUS = "admin_status"
ADMIN_STATUS_DEFAULT = "down"
ADMIN_STATUS_GOOD = "up"
HEALTH_STATUS = "health_ind"
HEALTH_STATUS_DEFAULT = "unknown"
HEALTH_STATUS_GOOD = "good"
LACP_STATUS = "lacp_state"
LACP_STATUS_BAD = "blocked"
LACP_STATUS_DEFAULT = "unblocked"
LACP_STATE_COLLECTING = 0x10
LACP_STATE_DISTRIBUTING = 0x20
OPER_STATUS = "oper_status"
OPER_STATUS_DEFAULT = "down"
OPER_STATUS_GOOD = "up"
STATUS_KEYS = [ADMIN_STATUS, HEALTH_STATUS, LACP_STATUS, OPER_STATUS]


class LedState(enum.Enum):
  OFF = 1
  ON_BLUE = 2
  BLINK_BLUE = 3
  ON_AMBER = 4
  BLINK_AMBER = 5


class LedControl(LedBase):
  """Platform specific class for interfacing with transceiver LEDs."""

  _default_status = {
      OPER_STATUS: OPER_STATUS_DEFAULT,
      HEALTH_STATUS: HEALTH_STATUS_DEFAULT,
      LACP_STATUS: LACP_STATUS_DEFAULT,
      ADMIN_STATUS: ADMIN_STATUS_DEFAULT
  }

  def __init__(
      self,
      sysfs_paths: dict[str, str],
      register_state_lookup: dict[LedState, int],
  ):
    super().__init__()

    self._sysfs_paths = sysfs_paths
    self._transceivers_with_leds = list(map(int, self._sysfs_paths.keys()))
    self._register_lookup = register_state_lookup

    for tcvr in self._sysfs_paths.keys():
      self._write_led_file(tcvr, LedState.OFF)

  def _write_led_file(self, tcvr: Optional[str], led_state: LedState):
    """Writes the desired led state to an LED sysfs entry.

    Args:
      tcvr: Transceiver for which LED we're writing.
      led_state: LedState enum signifying the LED colour to write.
    """
    path = ""
    led = ""
    try:
      path = self._sysfs_paths[tcvr]
      led = str(self._register_lookup[led_state])
    except (TypeError, ValueError, IndexError, KeyError) as err:
      logger.error(
          f"Unable to determine LED path/data for transceiver {tcvr}: {err}")
      return

    try:
      with open(path, "w") as f:
        f.write(led)
    except (IOError) as err:
      logger.error("Error writing LED file %s: %s", path, err)

  def _determine_lacp_state(self, lacp_state: str):
    try:
      state = int(lacp_state)
    except ValueError as e:
      logger.error("Failed to convert %s to integer: %s", lacp_state, e)
      return LACP_STATUS_DEFAULT
    # LACP state is considered unblocked only if both collecting and
    # distributing bits are set. Otherwise, the port is considered to be in
    # blocked state.
    return (LACP_STATUS_DEFAULT if state & LACP_STATE_COLLECTING and
            state & LACP_STATE_DISTRIBUTING else LACP_STATUS_BAD)

  def _determine_led_health_colour(self, status: dict[str, str]):
    """Determines a single LED colour given the status.

    Args:
      status: A dictionary containing port health, e.g.: {
        'oper_status': 'up',
        'admin_status': 'enabled',
        'lacp_state': 'distributing',
        'health_ind': 'good' }

    Returns:
      An LedState enum signifying the desired LED colour for the status.
    """
    # By default, assume link is down and change colour in priority order to
    # determine final colour for LED.
    led_colour = LedState.OFF

    if status[ADMIN_STATUS] != ADMIN_STATUS_GOOD:
      led_colour = LedState.ON_AMBER
      return led_colour

    # Health & LACP only need to be checked if link is up.
    if status[OPER_STATUS] == OPER_STATUS_GOOD:
      led_colour = LedState.ON_BLUE
      if status[LACP_STATUS] == LACP_STATUS_BAD or status[
          HEALTH_STATUS] == HEALTH_STATUS_DEFAULT:
        led_colour = LedState.BLINK_BLUE
      elif status[HEALTH_STATUS] != HEALTH_STATUS_GOOD:
        led_colour = LedState.BLINK_AMBER

    return led_colour

  def _aggregate_led_colour(self, colours: list[LedState]):
    """Aggregates multiple LED colours for one transceiver and determines the final colour.

    Args:
      colours: A list of LedState enums representing LED colours for one port.

    Returns:
      An LedState enum signifying the aggregated colour to use.
    """
    if not colours:
      return LedState.OFF
    elif LedState.BLINK_AMBER in colours:
      return LedState.BLINK_AMBER

    final_colour = colours[0]
    for colour in colours[1:]:
      # If any difference in colours, final colour is amber.
      if final_colour != colour:
        return LedState.ON_AMBER

    return final_colour

  def get_transceivers_with_leds(self) -> list[int]:
    return self._transceivers_with_leds

  def port_link_state_change_extended(
      self,
      tcvr_idx: Optional[str],
      statuses: list[Union[dict[str, str], str]],
  ):
    """Called when a transceiver link state changes, update transceiver link state LED here.

    Args:
      tcvr_idx: A string, transceiver ID (e.g., "1")
      statuses: A list of dictionaries containing port health for each port
        breakout under the transceiver, e.g.: [ {
            'oper_status': 'up',
            'admin_status': 'up',
            'lacp_state': 'distributing',
            'health_ind': 'good' }, {
            'oper_status': 'up',
            'admin_status': 'down',
            'lacp_state': 'distributing',
            'health_ind': 'good' } ]
    """
    # Take a copy of the input since it is going to be modified by this method.
    # We don't want these modifications to be reflected in the daemon.
    statuses = copy.deepcopy(statuses)
    if not isinstance(statuses, list):
      # Handle as empty list of statuses, which will be LED off.
      statuses = []

    led_states = []
    for status in statuses:
      if not isinstance(status, dict):
        logger.error("Expect transceiver statuses as a dictionary.")
        return
      for k in STATUS_KEYS:
        if k not in status.keys() or not status[k]:
          status[k] = self._default_status[k]
        if k == LACP_STATUS and status[k] != self._default_status[k]:
          # LACP state has been passed from the daemon. The daemon passes a
          # bitmap of the various LACP states. We are concerned only whether
          # it corresponds to a blocked state or not. Therefore, determine
          # whether the bitmap means that LACP is blocked and update the status.
          status[k] = self._determine_lacp_state(status[k])
      try:
        led_states.append(self._determine_led_health_colour(status))
      except (KeyError, TypeError) as err:
        logger.error(f"Failed to parse health statuses: {err}")
        return

    led_colour = self._aggregate_led_colour(led_states)

    self._write_led_file(tcvr_idx, led_colour)
