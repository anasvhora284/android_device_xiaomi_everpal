#
# Copyright (C) 2023 The OrangeFox Recovery Project
# Copyright (C) 2026 The Android Open Source Project
#
# SPDX-License-Identifier: Apache-2.0
#
# Recovery tree for Xiaomi evergo / evergreen / opal (unified "everpal", MT6833).
# AERA Recovery (aera-16.0).
# Ported from OrangeFoxRecovery/device_xiaomi_everpal (fox_12.1); kernel, dtb, fstab and TEE blobs
# are taken from Addster09's crDroid 12.11 (lineage-23.2) so decryption matches that ROM family.
#

DEVICE_PATH := device/xiaomi/everpal

# Build hacks needed by recovery-only trees
ALLOW_MISSING_DEPENDENCIES := true
BUILD_BROKEN_DUP_RULES := true
BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true
BUILD_BROKEN_PLUGIN_VALIDATION := soong-libaosprecovery_defaults soong-libguitwrp_defaults soong-libminuitwrp_defaults soong-vold_defaults

# A/B — same partition set as the lineage-23.2 ROM tree (no dtbo / odm_dlkm / system_dlkm on everpal ROMs)
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS += \
    boot \
    system \
    system_ext \
    product \
    vendor \
    vendor_dlkm \
    odm \
    vbmeta \
    vbmeta_system \
    vbmeta_vendor
BOARD_USES_RECOVERY_AS_BOOT := true

# Architecture
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-2a-dotprod
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := cortex-a76

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv8-2a
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := generic
TARGET_2ND_CPU_VARIANT_RUNTIME := cortex-a55

# Assert
TARGET_OTA_ASSERT_DEVICE := evergo,evergreen,everpal,opal

# Bootloader
TARGET_BOOTLOADER_BOARD_NAME := everpal
TARGET_NO_BOOTLOADER := true

# Platform
TARGET_BOARD_PLATFORM := mt6833

# Kernel — prebuilt 4.14.357 + dtb extracted from crDroid 12.11 boot.img (header v2, dtb in boot)
BOARD_KERNEL_CMDLINE := bootopt=64S3,32N2,64N2
BOARD_KERNEL_CMDLINE += androidboot.init_fatal_reboot_target=recovery
BOARD_KERNEL_CMDLINE += androidboot.selinux=permissive
BOARD_BOOTIMG_HEADER_VERSION := 2
BOARD_BOOT_HEADER_VERSION := 2
BOARD_KERNEL_IMAGE_NAME := Image.gz
BOARD_INCLUDE_DTB_IN_BOOTIMG := true
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/Image.gz
BOARD_PREBUILT_DTBIMAGE_DIR := $(DEVICE_PATH)/prebuilt/dtb

# Offsets verified against crDroid boot.img: kernel 0x40080000, ramdisk 0x51100000, tags/dtb 0x47c80000
BOARD_KERNEL_BASE := 0x40078000
BOARD_KERNEL_OFFSET := 0x00008000
BOARD_KERNEL_PAGESIZE := 2048
BOARD_RAMDISK_OFFSET := 0x11088000
BOARD_KERNEL_TAGS_OFFSET := 0x07c08000
BOARD_DTB_OFFSET := 0x07c08000
BOARD_MKBOOTIMG_ARGS += --ramdisk_offset $(BOARD_RAMDISK_OFFSET)
BOARD_MKBOOTIMG_ARGS += --tags_offset $(BOARD_KERNEL_TAGS_OFFSET)
BOARD_MKBOOTIMG_ARGS += --dtb_offset $(BOARD_DTB_OFFSET)
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOTIMG_HEADER_VERSION)

# Partitions
BOARD_FLASH_BLOCK_SIZE := 131072
BOARD_BOOTIMAGE_PARTITION_SIZE := 134217728
BOARD_USES_METADATA_PARTITION := true

BOARD_SUPER_PARTITION_SIZE := 9126805504
BOARD_SUPER_PARTITION_GROUPS := xiaomi_dynamic_partitions
BOARD_XIAOMI_DYNAMIC_PARTITIONS_PARTITION_LIST := \
    system \
    system_ext \
    product \
    vendor \
    vendor_dlkm \
    odm
BOARD_XIAOMI_DYNAMIC_PARTITIONS_SIZE := 9122611200

BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_SYSTEM_EXTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDOR_DLKMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_ODMIMAGE_FILE_SYSTEM_TYPE := ext4

TARGET_COPY_OUT_SYSTEM_EXT := system_ext
TARGET_COPY_OUT_PRODUCT := product
TARGET_COPY_OUT_VENDOR := vendor
TARGET_COPY_OUT_VENDOR_DLKM := vendor_dlkm
TARGET_COPY_OUT_ODM := odm

TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true

# Recovery
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery/root/system/etc/recovery.fstab
TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888
RECOVERY_SDCARD_ON_DATA := true
AERA_SKIP_ADDITIONAL_FSTAB := true

# AVB — same key/algorithm/rollback index as crDroid's boot.img footer (testkey_rsa2048, index 1)
BOARD_AVB_ENABLE := true
BOARD_AVB_ALGORITHM := SHA256_RSA2048
BOARD_AVB_KEY_PATH := external/avb/test/data/testkey_rsa2048.pem
BOARD_AVB_MAKE_VBMETA_IMAGE_ARGS += --set_hashtree_disabled_flag
BOARD_AVB_BOOT_KEY_PATH := external/avb/test/data/testkey_rsa2048.pem
BOARD_AVB_BOOT_ALGORITHM := SHA256_RSA2048
BOARD_AVB_BOOT_ROLLBACK_INDEX := 1
BOARD_AVB_BOOT_ROLLBACK_INDEX_LOCATION := 1

# OS version / patch levels: MUST equal what the phone boots with (boot header 16.0.0 / 2026-08,
# ro.vendor.build.security_patch 2024-02-01 on crDroid 12.11). The Beanpod TEE binds keys to these.
# The usual TWRP spoof (99.87.36 / 2127-12-31) made the TEE answer KEY_REQUIRES_UPGRADE (-62) for the
# /metadata key on a real test: had the upgraded blob been saved, the ROM could no longer unlock /data.
# Equal values never trigger an upgrade; if the ROM later gets a newer patch, decryption just fails
# (no writes) until this is bumped and the recovery rebuilt.
PLATFORM_SECURITY_PATCH := 2026-08-01
VENDOR_SECURITY_PATCH := 2024-02-01
PLATFORM_VERSION := 16
PLATFORM_VERSION_LAST_STABLE := $(PLATFORM_VERSION)

# Decryption — FBEv2 + metadata encryption via MediaTek Microtrust/Beanpod keymaster 4.1
AERA_INCLUDE_CRYPTO := true
AERA_INCLUDE_CRYPTO_FBE := true
AERA_INCLUDE_FBE_METADATA_DECRYPT := true
AERA_USE_FSCRYPT_POLICY := 2
AERA_PREPARE_DATA_MEDIA_EARLY := true

# Every library the Beanpod keymaster service links against (readelf NEEDED) that is not a vendor blob
TARGET_RECOVERY_DEVICE_MODULES += \
    android.hardware.keymaster@4.0 \
    android.hardware.keymaster@4.1 \
    libkeymaster4 \
    libkeymaster41 \
    libkeymaster4_1support \
    libkeymaster_messages
AERA_RECOVERY_ADDITIONAL_RELINK_LIBRARY_FILES += \
    $(TARGET_OUT_SHARED_LIBRARIES)/android.hardware.keymaster@4.0.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/android.hardware.keymaster@4.1.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/libkeymaster4.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/libkeymaster41.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/libkeymaster4_1support.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/libkeymaster_messages.so

# TWRP UI / hardware
AERA_THEME := portrait_hdpi
AERA_EXTRA_LANGUAGES := true
AERA_FRAMERATE := 90
AERA_SCREEN_BLANK_ON_BOOT := true
AERA_INPUT_BLACKLIST := "hbtp_vm"
AERA_BRIGHTNESS_PATH := "/sys/class/leds/lcd-backlight/brightness"
AERA_MAX_BRIGHTNESS := 2047
AERA_DEFAULT_BRIGHTNESS := 1024
AERA_EXCLUDE_DEFAULT_USB_INIT := true
AERA_UI_ADAPTIVE_RESOLUTION := true
AERA_EXCLUDE_APEX := true

# Haptics: TWRP's AIDL client -> vibrator/ service -> awinic_haptic FF input device
AERA_SUPPORT_INPUT_AIDL_HAPTICS := true
AERA_RECOVERY_ADDITIONAL_RELINK_BINARY_FILES += \
    $(TARGET_OUT_EXECUTABLES)/vibrator-service.everpal-recovery
AERA_RECOVERY_ADDITIONAL_RELINK_LIBRARY_FILES += \
    $(TARGET_OUT_SHARED_LIBRARIES)/android.hardware.vibrator-V1-ndk.so

# Battery %: comes from MediaTek's fuelgauged, started by init.mt6833.rc (see there)

# Boot mode. TWRP's first-stage init only ignores the bootloader's force_normal_boot when the
# cmdline has twrpfastboot=1, so one image cannot be both "fastboot boot"-testable and flashable:
#   EVERPAL_RAMBOOT_TEST=1  -> always boots recovery; ONLY for `fastboot boot` (never flash it:
#                              a flashed copy would boot to recovery forever).
#   unset (default)         -> flashable; follows the bootloader (Android normally, recovery on key combo).
# AERA_NO_FASTBOOT_BOOT prevents the vendor config from adding the flag on its own.
AERA_NO_FASTBOOT_BOOT := true
ifeq ($(EVERPAL_RAMBOOT_TEST),1)
    BOARD_KERNEL_CMDLINE += twrpfastboot=1
endif

# Tools
AERA_USE_TOOLBOX := true
AERA_INCLUDE_RESETPROP := true
AERA_INCLUDE_NTFS_3G := true
AERA_INCLUDE_PYTHON := true
TARGET_USES_MKE2FS := true

# Logging (keeps logcat/dmesg available for bug reports)
AERA_INCLUDE_LOGCAT := true
TARGET_USES_LOGD := true
