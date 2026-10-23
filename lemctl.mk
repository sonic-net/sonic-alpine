# Diagnostic CLI built from the pinned Lemming source with downstream fixes.
LEMCTL = lemctl_1.0-1_$(CONFIGURED_ARCH).deb
$(LEMCTL)_SRC_PATH = $(PLATFORM_PATH)/src/lemctl
SONIC_DPKG_DEBS += $(LEMCTL)
$(DOCKER_SONIC_ALPINEVS)_DEPENDS += $(LEMCTL)
