# Lucius packet handler for Alpine

ALPINE_SRC_PATH=platform/alpinevs
PKT_HANDLER = lucius-pkthandler_1.0-2_$(CONFIGURED_ARCH).deb
$(PKT_HANDLER)_SRC_PATH = $(ALPINE_SRC_PATH)/src/services/pkt-handler
$(PKT_HANDLER)_DEPENDS += $(LIBNL3_DEV) $(LIBNL_GENL3_DEV)
$(PKT_HANDLER)_RDEPENDS += $(LIBNL3) $(LIBNL_GENL3)

PKT_HANDLER_SRC_FILES = \
    $(wildcard $($(PKT_HANDLER)_SRC_PATH)/*.go) \
    $(wildcard $($(PKT_HANDLER)_SRC_PATH)/go.mod) \
    $(wildcard $($(PKT_HANDLER)_SRC_PATH)/go.sum) \
    $($(PKT_HANDLER)_SRC_PATH)/Makefile \
    $($(PKT_HANDLER)_SRC_PATH)/lucius-pkthandler.service \
    $(wildcard $($(PKT_HANDLER)_SRC_PATH)/debian/*)

$(addprefix $(DEBS_PATH)/,$(PKT_HANDLER)): $(PKT_HANDLER_SRC_FILES)

$(DEBS_PATH)/$(PKT_HANDLER): $(PKT_HANDLER_SRC_FILES)
$(DOCKER_SONIC_ALPINEVS)_CONTAINER_DEBS += $(PKT_HANDLER)

SONIC_DPKG_DEBS += $(PKT_HANDLER)
