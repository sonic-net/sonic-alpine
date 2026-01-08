# Platform device services for Alpine
ALPINE_SRC_PATH = platform/alpinevs
ALPINE_DEVICE = alpine-device_1.0_$(CONFIGURED_ARCH).deb
$(ALPINE_DEVICE)_SRC_PATH = $(ALPINE_SRC_PATH)/src/sonic-platform-alpinevs/alpinevs-device

# Define the build rule
$(ALPINE_DEVICE):
	$(DEB_BUILDER) -v $(ALPINE_DEVICE) -s $($(ALPINE_DEVICE)_SRC_PATH)

# Register the deb so the build system treats it like a real package
SONIC_DPKG_DEBS += $(ALPINE_DEVICE)

