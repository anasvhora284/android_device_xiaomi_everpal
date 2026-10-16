#
# SPDX-License-Identifier: Apache-2.0
#
# OrangeFox (fox_12.1) build settings for everpal. Only exported for OrangeFox builds; PitchBlack
# ignores FOX_/OF_ variables. Names verified against fox_12.1 orangefox.mk / OrangeFox_A12.sh
# (OF_VIRTUAL_AB_DEVICE, OF_AB_DEVICE, OF_VANILLA_BUILD, OF_TARGET_DEVICES are obsolete there).
#
# Unlike the 2023 tree, nothing is downloaded at build time (it fetched "latest" Magisk unpinned).
#

FDEVICE="everpal"

if [ "$1" = "$FDEVICE" ] || [ "$FOX_BUILD_DEVICE" = "$FDEVICE" ]; then
	# Device / partitions
	export FOX_VIRTUAL_AB_DEVICE=1
	export FOX_VANILLA_BUILD=1
	export FOX_TARGET_DEVICES="evergo,evergreen,everpal,opal"
	export TARGET_DEVICE_ALT="evergo,evergreen,opal"
	export FOX_RECOVERY_BOOT_PARTITION="/dev/block/by-name/boot"
	export FOX_RECOVERY_SYSTEM_PARTITION="/dev/block/mapper/system"
	export FOX_RECOVERY_VENDOR_PARTITION="/dev/block/mapper/vendor"
	# OrangeFox's own anti-rollback check: pin build date (kept from the proven 2023 tree)
	export FOX_BUGGED_AOSP_ARB_WORKAROUND="1616300800"

	# Tools (FOX_USE_NANO_EDITOR needs external/nano — the build script clones it)
	export FOX_USE_BASH_SHELL=1
	export FOX_ASH_IS_BASH=1
	export FOX_USE_TAR_BINARY=1
	export FOX_USE_SED_BINARY=1
	export FOX_USE_XZ_UTILS=1
	export FOX_USE_NANO_EDITOR=1
	export FOX_ENABLE_APP_MANAGER=1
	export FOX_DELETE_AROMAFM=1

	# Screen: 1080x2400, centre punch-hole
	export OF_SCREEN_H=2400
	export OF_STATUS_H=100
	export OF_STATUS_INDENT_LEFT=48
	export OF_STATUS_INDENT_RIGHT=48
	export OF_HIDE_NOTCH=1
	export OF_CLOCK_POS=1

	# Flashlight (symlink in recovery/root/system/flashlight -> flashlights_mt6360)
	export OF_FLASHLIGHT_ENABLE=1
	export OF_FL_PATH1="/system/flashlight"

	export OF_MAINTAINER="aetomtomy"
fi
