# docker image for alpine virtual switch based sonic docker image

DOCKER_SONIC_ALPINEVS = docker-sonic-alpinevs.gz
$(DOCKER_SONIC_ALPINEVS)_PATH = $(PLATFORM_PATH)/docker-sonic-alpinevs
$(DOCKER_SONIC_ALPINEVS)_DEPENDS += $(SYNCD_VS) \
                              $(LEMMINGSAI) \
                              $(PKT_HANDLER) \
                              $(PYTHON3_SWSSCOMMON) \
                              $(SONIC_DEVICE_DATA) \
                              $(LIBYANG) \
                              $(LIBYANG_CPP) \
                              $(LIBYANG_PY3) \
                              $(SONIC_UTILITIES_DATA) \
                              $(SONIC_HOST_SERVICES_DATA) \
                              $(SYSMGR)

$(DOCKER_SONIC_ALPINEVS)_PYTHON_WHEELS += $(SONIC_PY_COMMON_PY3) \
                                    $(SONIC_PLATFORM_COMMON_PY3) \
                                    $(SONIC_YANG_MODELS_PY3) \
                                    $(SONIC_YANG_MGMT_PY3) \
                                    $(SONIC_UTILITIES_PY3) \
                                    $(SONIC_HOST_SERVICES_PY3)

ifeq ($(INSTALL_DEBUG_TOOLS), y)
$(DOCKER_SONIC_ALPINEVS)_DEPENDS += $(LIBSWSSCOMMON_DBG) \
                              $(LIBSAIREDIS_DBG) \
                              $(SYNCD_VS_DBG) \
                              $(SYSMGR_DBG)
endif

$(DOCKER_SONIC_ALPINEVS)_FILES += $(CONFIGDB_LOAD_SCRIPT) \
                            $(ARP_UPDATE_SCRIPT) \
                            $(ARP_UPDATE_VARS_TEMPLATE) \
                            $(BUFFERS_CONFIG_TEMPLATE) \
                            $(QOS_CONFIG_TEMPLATE) \
                            $(SONIC_VERSION) \
                            $(UPDATE_CHASSISDB_CONFIG_SCRIPT) \
                            $(COPP_CONFIG_TEMPLATE)

$(DOCKER_SONIC_ALPINEVS)_LOAD_DOCKERS += $(DOCKER_SWSS_LAYER_BOOKWORM)
SONIC_DOCKER_IMAGES += $(DOCKER_SONIC_ALPINEVS)
SONIC_BOOKWORM_DOCKERS += $(DOCKER_SONIC_ALPINEVS)
