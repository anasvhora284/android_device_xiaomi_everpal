#!/system/bin/sh
# Bring up the installed ROM's MT6833 CONNAC stack without modifying its vendor partition.
ROM_VENDOR=/mnt/vendor_everpal_wifi
ROM_DLKM=/mnt/vendor_dlkm_everpal_wifi
export LD_LIBRARY_PATH="$ROM_VENDOR/lib64:$ROM_VENDOR/lib:/system/lib64:/vendor/lib64:/vendor/lib"

log() { echo "wifi-everpal: $*" > /dev/kmsg; }

case "$1" in
    loader) exec "$ROM_VENDOR/bin/wmt_loader" ;;
    launcher) exec "$ROM_VENDOR/bin/wmt_launcher" -p /vendor/firmware/ -o 1 ;;
    start) ;;
    *) exit 2 ;;
esac

[ "$(getprop vendor.prepdecrypt.everpal.done)" = 1 ] || exit 1
setprop wifi.driver.ready false
if [ -e /sys/class/net/wlan0 ]; then
    setprop wifi.driver.ready true
    exit 0
fi
SLOT=$(getprop ro.boot.slot_suffix)
VENDOR=
for i in $(seq 1 20); do
    for suffix in "$SLOT" ""; do
        [ -b "/dev/block/mapper/vendor$suffix" ] && VENDOR="/dev/block/mapper/vendor$suffix" && break 2
    done
    sleep 0.5
done
[ -n "$VENDOR" ] || { log "ROM vendor mapper not found"; exit 1; }

mkdir -p "$ROM_VENDOR" "$ROM_DLKM"
if ! grep -q " $ROM_VENDOR " /proc/mounts; then
    mount -o ro "$VENDOR" "$ROM_VENDOR" 2>/dev/null ||
        mount -t erofs -o ro "$VENDOR" "$ROM_VENDOR" 2>/dev/null || {
            log "ROM vendor mount failed"; exit 1;
        }
fi
[ -x "$ROM_VENDOR/bin/wmt_loader" ] && [ -x "$ROM_VENDOR/bin/wmt_launcher" ] || {
    log "ROM WMT executables missing"; exit 1;
}

# Firmware requests use /vendor/firmware; expose only the ROM's WLAN files there.
# The recovery's haptic/touch firmware and TEE files stay visible.
mkdir -p /vendor/firmware /vendor/etc/wifi
for pattern in WMT_SOC.cfg WIFI_RAM_CODE_soc2_2_* soc2_2_ram_*; do
    for file in "$ROM_VENDOR"/firmware/$pattern; do
        [ -f "$file" ] || continue
        name=${file##*/}
        [ -e "/vendor/firmware/$name" ] || ln -s "$file" "/vendor/firmware/$name"
    done
done
# Own writable config, never the ROM's: its ctrl_interface=wlan0 needs Android's init socket
# (wpa_wlan0) and its P2P/HS2.0 driver_param lines are for the framework -> supplicant exits 255.
# /vendor/etc/wifi/wpa_supplicant.conf is the path AERA's WLAN code and our rc both use.
if [ ! -f /tmp/recovery/wpa_supplicant.conf ]; then
    mkdir -p /tmp/recovery/sockets
    printf 'ctrl_interface=/tmp/recovery/sockets\nupdate_config=1\npmf=1\nsae_pwe=2\n' \
        > /tmp/recovery/wpa_supplicant.conf
fi
ln -sf /tmp/recovery/wpa_supplicant.conf /vendor/etc/wifi/wpa_supplicant.conf
# wpa_supplicant drops to the wifi user (1010) on its own: it must read the config, write
# <conf>.tmp next to it when saving networks, and own its control socket dir. mkdir -p made these
# 0700/0600 root -> "Failed to open config file ... Permission denied", exit 255 (seen on evergo).
chown 1010:1010 /vendor/etc/wifi /tmp/recovery/wpa_supplicant.conf /tmp/recovery/sockets
chmod 0775 /vendor/etc/wifi
chmod 0660 /tmp/recovery/wpa_supplicant.conf

# Stock 4.14.186 may place modules on vendor_dlkm; Aqua 4.14.357 has WLAN built in.
for suffix in "$SLOT" ""; do
    if [ -b "/dev/block/mapper/vendor_dlkm$suffix" ]; then
        mount -o ro "/dev/block/mapper/vendor_dlkm$suffix" "$ROM_DLKM" 2>/dev/null ||
            mount -t erofs -o ro "/dev/block/mapper/vendor_dlkm$suffix" "$ROM_DLKM" 2>/dev/null
        break
    fi
done

setprop ctl.start aera-wmt-loader
for i in $(seq 1 10); do
    [ "$(getprop init.svc.aera-wmt-loader)" = stopped ] && break
    sleep 0.5
done
if [ ! -e /dev/wmtWifi ]; then
    for module in connfem.ko wmt_drv.ko wmt_chrdev_wifi.ko wlan_drv_gen4m.ko; do
        found=
        for dir in "$ROM_VENDOR/lib/modules" "$ROM_DLKM/lib/modules" "$ROM_DLKM/lib/modules/mtk"; do
            [ -f "$dir/$module" ] && found="$dir/$module" && break
        done
        [ -n "$found" ] || { log "missing module $module"; exit 1; }
        insmod "$found" || { log "insmod failed: $module"; exit 1; }
    done
    setprop ctl.start aera-wmt-loader
fi

setprop ctl.start aera-wmt-launcher
for i in $(seq 1 30); do
    [ -e /dev/wmtWifi ] && break
    sleep 0.5
done
[ -e /dev/wmtWifi ] || { log "/dev/wmtWifi missing"; exit 1; }
echo 1 > /dev/wmtWifi || { log "could not enable WLAN"; exit 1; }
for i in $(seq 1 40); do
    [ -e /sys/class/net/wlan0 ] && { setprop wifi.driver.ready true; exit 0; }
    sleep 0.5
done
log "wlan0 did not appear"
exit 1
