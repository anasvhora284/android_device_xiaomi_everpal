#
# SPDX-License-Identifier: Apache-2.0
#
# OrangeFox (fox_12.1) product. Lunch: twrp_everpal-eng

$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/base.mk)

# OrangeFox / TWRP common configuration
$(call inherit-product, vendor/twrp/config/common.mk)

$(call inherit-product, device/xiaomi/everpal/device.mk)

PRODUCT_DEVICE := everpal
PRODUCT_NAME := twrp_everpal
PRODUCT_BRAND := Redmi
PRODUCT_MODEL := everpal
PRODUCT_MANUFACTURER := Xiaomi
PRODUCT_RELEASE_NAME := everpal
