# Platform config services for Alpine
ALPINE_SRC_PATH = platform/alpinevs
ALPINE_CONFIG = alpine-config_1.0_$(CONFIGURED_ARCH).deb
$(ALPINE_CONFIG)_SRC_PATH = $(ALPINE_SRC_PATH)/src/services/config

# Define the build rule
$(ALPINE_CONFIG):
	$(DEB_BUILDER) -v $(ALPINE_CONFIG) -s $($(ALPINE_CONFIG)_SRC_PATH)

# Register the deb so the build system treats it like a real package
SONIC_DPKG_DEBS += $(ALPINE_CONFIG)

