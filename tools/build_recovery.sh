#!/usr/bin/env bash
# Build OrangeFox (fox_12.1) and PitchBlack (android-12.1) for everpal on the build VM.
#
#   bash build_recovery.sh <ofox|pbrp|both>
#
# Expects ~/evergo-recovery/{device_xiaomi_everpal,tools,ref} uploaded from the laptop.
# Each flavour is built twice from the same tree:
#   *-RAMBOOT-TEST-DO-NOT-FLASH.img  (twrpfastboot=1, only for `fastboot boot`)
#   *-flashable.img                  (normal; follows the bootloader)
# Both checkers must pass or the script stops. Log: ~/evergo-recovery/build_<flavour>.log
set -euo pipefail
export PATH=$HOME/bin:$PATH
command -v repo >/dev/null || { echo "repo not installed (~/bin/repo)"; exit 1; }

W=~/evergo-recovery
DATE=$(date -u +%Y%m%d)   # one date for every artifact of this run
IMG_OUT=$W/images   # NOT "OUT": OrangeFox envsetup exports OUT_DIR="$OUT" if OUT is set
TOOLS=$W/tools/aosp          # unpack_bootimg.py, avbtool.py
mkdir -p "$IMG_OUT"
export USE_CCACHE=1

python3 -I "$W/tools/check_tree.py" "$W/device_xiaomi_everpal" "$W/ref"   # gate 1: static tree checks

sync_ofox() {   # prints only the source path on stdout; all sync output goes to stderr
	local S=~/fox_12.1
	{
	if [ ! -d "$S/.repo" ]; then
		mkdir -p ~/fox_sync && cd ~/fox_sync
		[ -d sync ] || git clone --depth=1 https://gitlab.com/OrangeFox/sync.git
		cd sync && ./orangefox_sync.sh --branch 12.1 --path "$S"
		[ -f "$S/build/envsetup.sh" ] || { echo "OrangeFox sync failed"; exit 1; }
	fi
	[ -d "$S/external/nano" ] || git clone --depth=1 -b lineage-19.1 https://github.com/LineageOS/android_external_nano "$S/external/nano"
	} >&2
	echo "$S"
}

sync_pbrp() {   # prints only the source path on stdout; all sync output goes to stderr
	local S=~/pbrp_12.1
	{
	if [ ! -d "$S/.repo" ]; then
		mkdir -p "$S" && cd "$S"
		repo init --depth=1 -u https://github.com/PitchBlackRecoveryProject/manifest_pb -b android-12.1
		repo sync -c --force-sync --no-tags --no-clone-bundle -j8
		[ -f "$S/build/envsetup.sh" ] || { echo "PBRP sync failed"; exit 1; }
	fi
	} >&2
	echo "$S"
}

build_one() {   # $1=src dir  $2=lunch target  $3=flavour tag  $4=ramboot|flash
	local S=$1 T=$2 F=$3 M=$4
	cd "$S"
	local P=$S/out/target/product/everpal
	local ZPAT
	case $F in ofox) ZPAT="OrangeFox*.zip" ;; pbrp) ZPAT="PBRP-*.zip" ;; esac
	rm -f "$P"/$ZPAT   # never pick up a zip from an earlier (e.g. ramboot) build
	rm -rf device/xiaomi/everpal && mkdir -p device/xiaomi && cp -a "$W/device_xiaomi_everpal" device/xiaomi/everpal
	if [ "$F" = pbrp ]; then
		# PBRP: drop the OrangeFox-style "/storage" (bind of /data/media/0) entry so PBRP uses its standard
		# automatic /data/media handling (tester: "internal storage mount error" on an AOSP ROM; OFox is fine).
		sed -i '/^\/storage[[:space:]]/d' device/xiaomi/everpal/recovery/root/system/etc/twrp.flags
		! grep -q '^/storage[[:space:]]' device/xiaomi/everpal/recovery/root/system/etc/twrp.flags || { echo "pbrp /storage strip failed"; exit 1; }
	fi
	if [ "$M" = ramboot ]; then
		# RAM-test image must never auto-format anything (first-stage init formats a 'formattable'
		# partition whose mount fails and that looks wiped; /metadata holds the /data key).
		sed -i 's/,formattable//; s/formattable,//' \
			device/xiaomi/everpal/recovery/root/first_stage_ramdisk/fstab.mt6833 \
			device/xiaomi/everpal/recovery/root/system/etc/recovery.fstab
		! grep -q formattable device/xiaomi/everpal/recovery/root/first_stage_ramdisk/fstab.mt6833 \
			device/xiaomi/everpal/recovery/root/system/etc/recovery.fstab || { echo "formattable strip failed"; exit 1; }
	fi
	(
		set +eu   # envsetup.sh/lunch are not set -e/-u clean; success is checked explicitly below
		[ "$F" = ofox ] && export FOX_BUILD_DEVICE=everpal
		[ "$M" = ramboot ] && export EVERPAL_RAMBOOT_TEST=1
		export ALLOW_MISSING_DEPENDENCIES=true
		# PBRP's vendor/utils/vendorsetup.sh curls its official device list with no timeout and has
		# hung on throttled GitHub; it is only used for official builds, so bound it.
		curl() { command curl --max-time 20 "$@"; }
		. build/envsetup.sh
		lunch "$T" || exit 1
		# OrangeFox's build script packages its installer zip as part of bootimage; PBRP needs `pbrp`
		local targets="adbd bootimage"
		[ "$M" = flash ] && [ "$F" = pbrp ] && targets="$targets pbrp"
		mka $targets -j"$(nproc)" || exit 1
	)
	local IMG=$P/boot.img
	local NAME=$F-everpal-$DATE
	[ "$M" = ramboot ] && NAME=$NAME-RAMBOOT-TEST-DO-NOT-FLASH.img || NAME=$NAME-flashable.img
	python3 -I "$W/tools/check_image.py" "$IMG" "$W/device_xiaomi_everpal" "$M" "$TOOLS"   # gate 2: image checks
	cp "$IMG" "$IMG_OUT/$NAME"
	( cd "$IMG_OUT" && sha256sum "$NAME" > "$NAME.sha256sum" )
	echo "BUILT $IMG_OUT/$NAME"
	if [ "$M" = flash ]; then
		# installer zip: replaces only the ramdisk of each slot's boot (keeps the user's kernel + header)
		local Z
		Z=$(ls -t "$P"/$ZPAT 2>/dev/null | head -1 || true)
		[ -n "$Z" ] || { echo "no installer zip produced"; exit 1; }
		local ZNAME=$F-everpal-$DATE-installer.zip
		python3 -I "$W/tools/check_zip.py" "$Z" "$IMG" "$F" "$TOOLS"   # gate 3: zip installs exactly this ramdisk
		# keep the installed ROM's own first-stage fstab (ports bootlooped with crDroid's)
		python3 -I "$W/tools/patch_installer.py" "$Z" "$IMG_OUT/$ZNAME" "$DATE"
		( cd "$IMG_OUT" && sha256sum "$ZNAME" > "$ZNAME.sha256sum" )
		echo "BUILT $IMG_OUT/$ZNAME"
		rm -f "$Z"
	fi
	# the next build of this tree must re-evaluate BoardConfig (cmdline changes between modes)
	rm -f "$S/out/target/product/everpal/boot.img" "$S/out/target/product/everpal/ramdisk-recovery.img"
}

flavour() {   # $1=ofox|pbrp
	local S T
	case $1 in
		ofox) S=$(sync_ofox); T=twrp_everpal-eng ;;
		pbrp) S=$(sync_pbrp); T=pb_everpal-eng ;;
	esac
	build_one "$S" "$T" "$1" ramboot
	build_one "$S" "$T" "$1" flash
}

case "${1:-}" in
	ofox|pbrp) flavour "$1" 2>&1 | tee "$W/build_$1.log" ;;
	both) flavour ofox 2>&1 | tee "$W/build_ofox.log"; flavour pbrp 2>&1 | tee "$W/build_pbrp.log" ;;
	*) echo "usage: $0 <ofox|pbrp|both>"; exit 2 ;;
esac
ls -la "$IMG_OUT"
