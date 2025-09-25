import json
import os

from sonic_platform_base import device_telemetry_base

class TelemetryDevice(device_telemetry_base.DeviceTelemetryBase):
    def __init__(self, device_config, dynamic_config_dir):
        self._device_config = self._convert_device_config(device_config)
        self._name = device_config["name"]
        self._dynamic_config_path = dynamic_config_dir
        self._dynamic_config_file = self._name + ".json"

    def _convert_device_config(self, json_config):
        """
        Converts all the json config metrics entries into tuples instead of
            key:value pair entries.

        Returns:
            dict: The converted configuration.
        """
        if "metrics" in json_config.keys() and isinstance(json_config["metrics"], dict):
            new_metrics = []
            for key in json_config["metrics"].keys():
                new_metrics.append((key, json_config["metrics"][key]))
            json_config["metrics"] = new_metrics

        if "children" in json_config.keys():
            child_entries = []
            for child_entry in json_config["children"]:
                child_entries.append(self._convert_device_config(child_entry))
            json_config["children"] = child_entries

        return json_config

    def _modify_device_children(self, source_config, modified_config):
        """
        Modifies all the json config metrics/child entries. Assumes that format
            of config is same as config passed through _convert_device_config.

        Returns:
            dict: The modified configuration.
        """
        if "metrics" in modified_config.keys() and "metrics" not in source_config.keys():
            source_config["metrics"] = modified_config["metrics"]
        elif "metrics" in modified_config.keys() and "metrics" in source_config.keys():
            for metric in modified_config["metrics"]:
                for src_metric in source_config["metrics"]:
                    if metric[0] == src_metric[0]:
                        source_config["metrics"].remove(src_metric)
                        break
                source_config["metrics"].append(metric)

        if "children" in modified_config.keys() and "children" not in source_config.keys():
            source_config["children"] = modified_config["children"]
        elif "children" in modified_config.keys() and "children" in source_config.keys():
            for mod_child_entry in modified_config["children"]:
                for child_entry in source_config["children"]:
                    if mod_child_entry["name"] == child_entry["name"]:
                        child_entry = self._modify_device_children(child_entry, mod_child_entry)
                        break
                else:
                    source_config["children"].append(mod_child_entry)

        return source_config

    def _modify_device_config(self):
        """
        If a dynamic reconfiguration file exists, modify and/or add configs
            specified to the telemetry device config.
        """
        json_config = None
        try:
            configs = [config for config in os.listdir(self._dynamic_config_path) if config.endswith(".json")]
        except FileNotFoundError:
            return
        if self._dynamic_config_file in configs:
            fname = os.path.join(self._dynamic_config_path, self._dynamic_config_file)
            with open(fname) as cf:
                json_config = json.load(cf)
        if not json_config:
            return

        modified_config = self._convert_device_config(json_config)
        self._device_config = self._modify_device_children(self._device_config, modified_config)

    def get_name(self):
        """
        Retrieves the name of the device

        Returns:
            string: The name of the device
        """
        return self._name

    def get_device_info(self):
        """Gets telemetry info of the device and its children

        Returns:
            Dictionary with all the telemetry info of the
            specific device and any children if available.
            Dict is of this format:
            {
             "type": <enum string of TelemetryDeviceType>,
             "name": <component's name as a string>,
             "metrics": [ ("<attribute Name>": "<attribute Value as string>"), …],
             "children" : [ {
                 "name": <sub component's name as a string>,
                 "metrics": [ ("<attribute Name>": "<attribute Value as string>"),...],
                 "children": [ {...} ],
                 },
              ],
           }
        """
        self._modify_device_config()
        return self._device_config