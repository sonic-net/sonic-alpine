try:
    import os
    import json
    from sonic_platform_base.chassis_base import ChassisBase
    from sonic_platform.telemetry_device import TelemetryDevice
    from sonic_platform import led_control
except ImportError as e:
    raise ImportError(str(e) + "- required module not found")

class Chassis(ChassisBase):
    """
    AlpineVS platform-specific Chassis class
    """

    TELEMETRY_DIR_BASE = "/usr/share/sonic/"
    TELEMETRY_DIR = f"{TELEMETRY_DIR_BASE}hwsku/telemetry/"
    DYNAMIC_TELEMETRY_DIR = f"{TELEMETRY_DIR}dynamic/"
    PATH_LED_FMT = TELEMETRY_DIR_BASE + "device/gfpga-platform/osfp_led_{0:d}_l"
    PATH_SFP_PLUS_LED_FMT = TELEMETRY_DIR_BASE + "device/gfpga-platform/sfp_plus_led_{0:d}_l"

    def __init__(self):
        ChassisBase.__init__(self)

        self._telemetry_device_list = []
        config_list = self._parse_telemetry_json_dir(self.TELEMETRY_DIR)
        for cf in config_list:
            self._telemetry_device_list.append(TelemetryDevice(cf, self.DYNAMIC_TELEMETRY_DIR))

        self._add_leds()

    def _parse_telemetry_json_dir(self, directory):
        """
        Parses all .json files in provided telemetry directory and return a
            single list of all json configs. Expect contents of each json to be
            a list of dicts.

        Args:
            directory: The directory to parse the json configs from.

        Returns:
            list: A list of json configs parsed from the telemetry directory.
        """
        cf_list = []
        try:
            configs = [config for config in os.listdir(directory) if config.endswith(".json")]
        except FileNotFoundError:
            return []
        for config in configs:
            with open(os.path.join(directory, config)) as cf:
                cf_list.extend(json.load(cf))
        return cf_list

    def get_name(self):
        """
        Retrieves the name of the chassis
        Returns:
            string: The name of the chassis
        """
        return "AlpineVS"

    def get_presence(self):
        """
        Retrieves the presence of the chassis
        Returns:
            bool: True if chassis is present, False if not
        """
        return True

    def get_model(self):
        """
        Retrieves the model number (or part number) of the chassis
        Returns:
            string: Model/part number of chassis
        """
        return "alpine_vs"

    def get_serial(self):
        """
        Retrieves the serial number of the chassis (Service tag)
        Returns:
            string: Serial number of chassis
        """
        return "Alpine00"

    def get_revision(self):
        """
        Retrieves the revision number of the chassis (Service tag)
        Returns:
            string: Revision number of chassis
        """
        return "alpine.v.0"

    def get_status(self):
        """
        Retrieves the operational status of the chassis
        Returns:
            bool: A boolean value, True if chassis is operating properly
            False if not
        """
        return True

    def get_position_in_parent(self):
        """
        Retrieves 1-based relative physical position in parent device. If the agent cannot determine the parent-relative position
        for some reason, or if the associated value of entPhysicalContainedIn is '0', then the value '-1' is returned
        Returns:
            integer: The 1-based relative physical position in parent device or -1 if cannot determine the position
        """
        return -1

    def is_replaceable(self):
        """
        Indicate whether this device is replaceable.
        Returns:
            bool: True if it is replaceable.
        """
        return False

    def get_all_telemetry_devices(self):
        """
        Retrieves all telemetry supply units available on this chassis.

        Returns:
            A list of objects representing all telemetry
            devices available on this chassis.
        """
        return self._telemetry_device_list

    def _add_leds(self):
        # Initialize LED controller.
        register_state_lookup = {
            led_control.LedState.OFF: 0x00,
            led_control.LedState.ON_BLUE: 0x01,
            led_control.LedState.BLINK_BLUE: 0x05,
            led_control.LedState.ON_AMBER: 0x02,
            led_control.LedState.BLINK_AMBER: 0x06,
        }

        # 34 transceivers & LEDs, last two sfp plus.
        sysfs_paths = {}
        for i in range(1, 33):
            sysfs_paths[str(i)] = self.PATH_LED_FMT.format(i)
        for i in range(33, 35):
            sysfs_paths[str(i)] = self.PATH_SFP_PLUS_LED_FMT.format(i)

        self._port_status_led = led_control.LedControl(sysfs_paths,
                                                       register_state_lookup)
