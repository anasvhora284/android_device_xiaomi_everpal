#
# Copyright (C) 2023 The OrangeFox Recovery Project
#
# SPDX-License-Identifier: Apache-2.0
#

LOCAL_PATH := $(call my-dir)

ifeq ($(TARGET_DEVICE),everpal)
include $(call all-subdir-makefiles,$(LOCAL_PATH))

# boot-service.default_recovery installs its *device* VINTF fragment under the recovery's /system
# (framework) manifest dir. servicemanager then rejects the whole framework manifest ("Cannot add a
# device manifest to a framework manifest"): keystore2/health/boot crash-loop, hwservicemanager.ready
# never fires, prepdecrypt/keymaster never start and AERA hangs on its logo. The HAL is declared in
# our vendor manifest instead; drop the misplaced fragment before the ramdisk is packed.
EVERPAL_BOOT_VINTF_FRAG := $(TARGET_RECOVERY_ROOT_OUT)/system/etc/vintf/manifest/android.hardware.boot-service.default.xml
EVERPAL_RAMDISK_TRIM_STAMP := $(TARGET_RECOVERY_ROOT_OUT)/.everpal-ramdisk-trim

$(EVERPAL_RAMDISK_TRIM_STAMP): $(EVERPAL_BOOT_VINTF_FRAG)
	@echo "everpal: removing framework-dir copy of the boot HAL device VINTF fragment"
	@rm -f $(EVERPAL_BOOT_VINTF_FRAG) && touch $@

$(PRODUCT_OUT)/obj/PACKAGING/recovery_intermediates/ramdisk_files-timestamp: \
    $(EVERPAL_RAMDISK_TRIM_STAMP)
endif
