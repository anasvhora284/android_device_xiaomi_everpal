#
# Copyright (C) 2023 The OrangeFox Recovery Project
# Copyright (C) 2026 The Android Open Source Project
#
# SPDX-License-Identifier: Apache-2.0
#

LOCAL_PATH := device/xiaomi/everpal

# Kept from the proven OrangeFox tree
$(call inherit-product, $(SRC_TARGET_DIR)/product/updatable_apex.mk)

# Virtual A/B (everpal ROMs: launch.mk, matching the lineage-23.2 device tree)
$(call inherit-product, $(SRC_TARGET_DIR)/product/virtual_ab_ota/launch.mk)

# Lets recovery verify GSI-signed system images (harmless otherwise)
$(call inherit-product, $(SRC_TARGET_DIR)/product/developer_gsi_keys.mk)

PRODUCT_SHIPPING_API_LEVEL := 30
PRODUCT_TARGET_VNDK_VERSION := 31
PRODUCT_USE_DYNAMIC_PARTITIONS := true

# A/B OTA install support (payload.bin ROM zips)
PRODUCT_PACKAGES += \
    update_engine \
    update_engine_sideload \
    update_verifier \
    checkpoint_gc \
    otapreopt_script

PRODUCT_PACKAGES_DEBUG += \
    update_engine_client

AB_OTA_POSTINSTALL_CONFIG += \
    RUN_POSTINSTALL_system=true \
    POSTINSTALL_PATH_system=system/bin/otapreopt_script \
    FILESYSTEM_TYPE_system=ext4 \
    POSTINSTALL_OPTIONAL_system=true

AB_OTA_POSTINSTALL_CONFIG += \
    RUN_POSTINSTALL_vendor=true \
    POSTINSTALL_PATH_vendor=bin/checkpoint_gc \
    FILESYSTEM_TYPE_vendor=ext4 \
    POSTINSTALL_OPTIONAL_vendor=true

# Boot control (AOSP misc-based, same implementation family the ROM uses)
PRODUCT_PACKAGES += \
    android.hardware.boot@1.2-impl \
    android.hardware.boot@1.2-impl.recovery \
    android.hardware.boot@1.2-service

# Gatekeeper: AOSP HIDL service in recovery, backed by the Beanpod HAL (vendor/lib64/hw/gatekeeper.beanpod.so)
PRODUCT_PACKAGES += \
    android.hardware.gatekeeper@1.0-service-recovery \
    android.hardware.gatekeeper@1.0-impl-recovery

# Decryption properties (MediaTek Microtrust TEE)
PRODUCT_VENDOR_PROPERTIES += \
    ro.crypto.volume.filenames_mode=aes-256-cts \
    ro.hardware.gatekeeper=beanpod \
    ro.hardware.kmsetkey=beanpod \
    ro.vendor.mtk_microtrust_tee_support=1 \
    ro.vendor.mtk_svp_on_mtee_support=1 \
    ro.vendor.mtk_tee_gp_support=1

# MTP by default in recovery
PRODUCT_SYSTEM_PROPERTIES += \
    ro.sys.usb.storage.type=mtp
