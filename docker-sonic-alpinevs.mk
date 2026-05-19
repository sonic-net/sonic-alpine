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

ALPINEVS_DOCKER_STAGING_DIR := $(PLATFORM_PATH)/docker-sonic-alpinevs/bin
ALPINEVS_PKT_HANDLER_SRC_DIR := $(PLATFORM_PATH)/src/services/pkt-handler
ALPINEVS_CONFIG_SRC := $(PLATFORM_PATH)/src/services/config/alpinevs-config.sh
ALPINEVS_INIT_SRC := $(PLATFORM_PATH)/src/services/init/alpinevs-init.sh

ALPINEVS_DOCKER_STAGE_FILES := \
	$(ALPINEVS_DOCKER_STAGING_DIR)/pkt-handler \
	$(ALPINEVS_DOCKER_STAGING_DIR)/alpinevs-config.sh \
	$(ALPINEVS_DOCKER_STAGING_DIR)/alpinevs-init.sh

$(ALPINEVS_DOCKER_STAGING_DIR):
	mkdir -p $@

# Always rebuild it before staging the Docker build-context copy
.PHONY: $(ALPINEVS_DOCKER_STAGING_DIR)/pkt-handler
$(ALPINEVS_DOCKER_STAGING_DIR)/pkt-handler: | $(ALPINEVS_DOCKER_STAGING_DIR)
	$(MAKE) -C $(ALPINEVS_PKT_HANDLER_SRC_DIR) clean
	$(MAKE) -C $(ALPINEVS_PKT_HANDLER_SRC_DIR) all
	cp $(ALPINEVS_PKT_HANDLER_SRC_DIR)/pkt-handler $@

$(ALPINEVS_DOCKER_STAGING_DIR)/alpinevs-config.sh: \
		$(ALPINEVS_CONFIG_SRC) | $(ALPINEVS_DOCKER_STAGING_DIR)
	cp -L $< $@

$(ALPINEVS_DOCKER_STAGING_DIR)/alpinevs-init.sh: \
		$(ALPINEVS_INIT_SRC) | $(ALPINEVS_DOCKER_STAGING_DIR)
	cp -L $< $@

$(addprefix $(TARGET_PATH)/,$(DOCKER_SONIC_ALPINEVS)): $(ALPINEVS_DOCKER_STAGE_FILES)
