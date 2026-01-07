include $(PLATFORM_PATH)/syncd-vs.mk
include $(PLATFORM_PATH)/sonic-version.mk
include $(PLATFORM_PATH)/docker-syncd-vs.mk
include $(PLATFORM_PATH)/lemmingsai.mk
include $(PLATFORM_PATH)/pkt-handler.mk
include $(PLATFORM_PATH)/alpine-init.mk
include $(PLATFORM_PATH)/alpine-platform.mk
include $(PLATFORM_PATH)/alpine-config.mk
include $(PLATFORM_PATH)/one-image.mk
include $(PLATFORM_PATH)/onie.mk
include $(PLATFORM_PATH)/kvm-image.mk
include $(PLATFORM_PATH)/raw-image.mk

# Inject lemming sai into syncd
$(SYNCD)_DEPENDS += $(LEMMINGSAI)
$(SYNCD)_UNINSTALLS += $(LEMMINGSAI)

# Ensure dependencies are built/available before your packages
$(ALPINE_INIT)_DEPENDS += $(SONIC_UTILITIES)
$(ALPINE_CONFIG)_DEPENDS += $(SONIC_UTILITIES)

SONIC_ALL += $(SONIC_ONE_IMAGE) $(SONIC_KVM_IMAGE) $(SYNCD_VS) $(SONIC_RAW_IMAGE)
