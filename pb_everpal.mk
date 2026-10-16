#
# SPDX-License-Identifier: Apache-2.0
#
# PitchBlack (android-12.1 / vendor/pb pb-12.1) product. Lunch: pb_everpal-eng

$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/base.mk)

# PitchBlack common configuration (PBRP's manifest has vendor/pb, not vendor/twrp)
$(call inherit-product, vendor/pb/config/common.mk)

$(call inherit-product, device/xiaomi/everpal/device.mk)

PRODUCT_DEVICE := everpal
PRODUCT_NAME := pb_everpal
PRODUCT_BRAND := Redmi
PRODUCT_MODEL := everpal
PRODUCT_MANUFACTURER := Xiaomi
PRODUCT_RELEASE_NAME := everpal

# PBRP's ramdisk has a real /etc directory (not a symlink to /system/etc like OrangeFox), so the boot
# control HAL's ReadDefaultFstab() cannot find /etc/recovery.fstab and init of IBootControl fails;
# recovery then retries getService forever while mounting /data (observed hang on the splash screen).
PRODUCT_COPY_FILES += \
    device/xiaomi/everpal/recovery/root/system/etc/recovery.fstab:$(TARGET_COPY_OUT_RECOVERY)/root/etc/recovery.fstab
