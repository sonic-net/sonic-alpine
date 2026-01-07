# Platform config services for Alpine
ALPINE_SRC_PATH = platform/alpinevs
ALPINE_PLATFORM= alpine-platform_1.0_$(CONFIGURED_ARCH).deb
$(ALPINE_PLATFORM)_SRC_PATH = $(ALPINE_SRC_PATH)/src/platform

# Define the build rule
$(ALPINE_PLATFORM):
	$(DEB_BUILDER) -v $(ALPINE_PLATFORM) -s $($(ALPINE_PLATFORM)_SRC_PATH)

# Register the deb so the build system treats it like a real package
SONIC_DPKG_DEBS += $(ALPINE_PLATFORM)

