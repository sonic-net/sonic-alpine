# Platform init services for Alpine
ALPINE_SRC_PATH = platform/alpinevs
ALPINE_INIT = alpine-init_1.0_$(CONFIGURED_ARCH).deb
$(ALPINE_INIT)_SRC_PATH = $(ALPINE_SRC_PATH)/src/services/init

# Define the build rule
$(ALPINE_INIT):
	$(DEB_BUILDER) -v $(ALPINE_INIT) -s $($(ALPINE_INIT)_SRC_PATH)

# Register the deb so the build system treats it like a real package
SONIC_DPKG_DEBS += $(ALPINE_INIT)

