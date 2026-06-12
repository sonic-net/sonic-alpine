# docker image for alpine virtual switch based sonic docker image

DOCKER_SONIC_ALPINEVS = docker-sonic-alpinevs.gz
$(DOCKER_SONIC_ALPINEVS)_PATH = $(PLATFORM_PATH)/docker-sonic-alpinevs
$(DOCKER_SONIC_ALPINEVS)_DEPENDS += $(SYNCD_VS) \
                              $(LEMMINGSAI) \
                              $(PKT_HANDLER) \
                              $(PYTHON3_SWSSCOMMON) \
                              $(SONIC_DEVICE_DATA) \
                              $(LIBYANG) \
                              $(LIBYANG3) \
                              $(LIBYANG_CPP) \
                              $(LIBYANG_PY3) \
                              $(SONIC_UTILITIES_DATA) \
                              $(SONIC_HOST_SERVICES_DATA) \
                              $(SYSMGR) \
                              $(SONIC_P4RT) \
                              $(SONIC_TELEMETRY) \
                              $(SONIC_MGMT_FRAMEWORK) \
                              $(SONIC_MGMT_COMMON)

$(DOCKER_SONIC_ALPINEVS)_PYTHON_WHEELS += $(SONIC_PY_COMMON_PY3) \
                                    $(SONIC_PLATFORM_COMMON_PY3) \
                                    $(SONIC_YANG_MODELS_PY3) \
                                    $(SONIC_YANG_MGMT_PY3) \
                                    $(SONIC_UTILITIES_PY3) \
                                    $(SONIC_HOST_SERVICES_PY3)

ifeq ($(INSTALL_DEBUG_TOOLS), y)
$(DOCKER_SONIC_ALPINEVS)_DEPENDS += $(LIBSWSSCOMMON_DBG) \
                              $(LIBSAIREDIS_DBG) \
                              $(SYNCD_VS_DBG)
endif

$(DOCKER_SONIC_ALPINEVS)_FILES += $(CONFIGDB_LOAD_SCRIPT) \
                            $(ARP_UPDATE_SCRIPT) \
                            $(ARP_UPDATE_VARS_TEMPLATE) \
                            $(BUFFERS_CONFIG_TEMPLATE) \
                            $(QOS_CONFIG_TEMPLATE) \
                            $(SONIC_VERSION) \
                            $(UPDATE_CHASSISDB_CONFIG_SCRIPT) \
                            $(COPP_CONFIG_TEMPLATE)

$(DOCKER_SONIC_ALPINEVS)_LOAD_DOCKERS += $(DOCKER_SWSS_LAYER_TRIXIE)
SONIC_DOCKER_IMAGES += $(DOCKER_SONIC_ALPINEVS)
SONIC_TRIXIE_DOCKERS += $(DOCKER_SONIC_ALPINEVS)

# Move the alpine scripts to the common location
# Execute synchronously during Makefile parsing to bypass the SONiC wipe-out step

# 1. Compile the Go binary natively
$(shell $(MAKE) -C $(PLATFORM_PATH)/src/services/pkt-handler all >&2)

# 2. Create the target directory
$(shell mkdir -p $(PLATFORM_PATH)/docker-sonic-alpinevs/bin)

# 3. Copy the compiled binary over
$(shell cp $(PLATFORM_PATH)/src/services/pkt-handler/pkt-handler $(PLATFORM_PATH)/docker-sonic-alpinevs/bin/)

# 4. Copy and DEREFERENCE soft links (-L) into the source directory
$(shell cp -L $(PLATFORM_PATH)/src/services/config/alpinevs-config.sh $(PLATFORM_PATH)/docker-sonic-alpinevs/bin/)
$(shell cp -L $(PLATFORM_PATH)/src/services/init/alpinevs-init.sh $(PLATFORM_PATH)/docker-sonic-alpinevs/bin/)
