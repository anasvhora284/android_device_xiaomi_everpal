#!/bin/bash
# Host-side test (no phone): see tools/aera_zip_qemu_test.sh. Needs qemu-user-static + root.
#   sudo bash wifi_qemu_test.sh <out/target/product/everpal/recovery/root>
# Exercise wifi-everpal.sh's stock-kernel path (no built-in driver) in an arm64 chroot of the recovery.
set -u
R=$1; C=$(mktemp -d)/root; cp -a "$R" $C; mkdir -p $C/dev/block/mapper $C/proc $C/sys/class/net $C/tmp
# fake ROM vendor as an ext4 image on a loop device
V=$(mktemp -d); mkdir -p $V/bin $V/firmware $V/lib/modules $V/etc/wifi
for b in wmt_loader wmt_launcher; do printf '#!/system/bin/sh\necho "%s $*" >> /tmp/calls\n' $b > $V/bin/$b; chmod 755 $V/bin/$b; done
for f in WMT_SOC.cfg WIFI_RAM_CODE_soc2_2_1_1.bin soc2_2_ram_wifi_1_1_hdr.bin soc2_2_ram_mcu_1_1_hdr.bin; do echo x > $V/firmware/$f; done
for m in connfem wmt_drv wmt_chrdev_wifi wlan_drv_gen4m; do echo ko > $V/lib/modules/$m.ko; done
printf 'ctrl_interface=wlan0\ndriver_param=use_p2p_group_interface=1\n' > $V/etc/wifi/wpa_supplicant.conf
truncate -s 64M /tmp/fakevendor.img; mkfs.ext4 -q -F -d $V /tmp/fakevendor.img
L=$(losetup -f --show /tmp/fakevendor.img); touch $C/dev/block/mapper/vendor_b; mount --bind $L $C/dev/block/mapper/vendor_b
mount -t proc proc $C/proc; touch $C/dev/kmsg $C/dev/null; mount --bind /dev/null $C/dev/null
trap 'umount -l $C/mnt/vendor_everpal_wifi $C/dev/block/mapper/vendor_b $C/proc $C/dev/null 2>/dev/null; losetup -d $L' EXIT
# stubs: props, ctl.start, insmod (creates /dev/wmtWifi only after all 4 modules, in order)
rm -f $C/system/bin/getprop $C/system/bin/setprop $C/system/bin/insmod
cat > $C/system/bin/getprop <<'G'
#!/system/bin/sh
case "$1" in vendor.prepdecrypt.everpal.done) echo 1;; ro.boot.slot_suffix) echo _b;; init.svc.aera-wmt-loader) echo stopped;; *) cat /tmp/prop.$1 2>/dev/null;; esac
G
cat > $C/system/bin/setprop <<'G'
#!/system/bin/sh
echo "setprop $1 $2" >> /tmp/calls; echo "$2" > /tmp/prop.$1
case "$1=$2" in ctl.start=aera-wmt-loader) /system/bin/wifi-everpal.sh loader;; ctl.start=aera-wmt-launcher) /system/bin/wifi-everpal.sh launcher & ;; esac
G
cat > $C/system/bin/insmod <<'G'
#!/system/bin/sh
echo "insmod ${1##*/}" >> /tmp/calls
[ "${1##*/}" = wlan_drv_gen4m.ko ] && [ "$(grep -c insmod /tmp/calls)" = 4 ] && { touch /dev/wmtWifi; }
exit 0
G
chmod 755 $C/system/bin/getprop $C/system/bin/setprop $C/system/bin/insmod
# wlan0 appears when "1" is written to /dev/wmtWifi (a plain file here): background watcher
( for i in $(seq 1 120); do [ -s $C/dev/wmtWifi ] && { mkdir -p $C/sys/class/net/wlan0; break; }; sleep 0.5; done ) &
timeout 120 chroot $C /system/bin/sh /system/bin/wifi-everpal.sh start; echo "exit: $?"
echo "--- calls:"; cat $C/tmp/calls
echo "--- wpa conf used:"; ls -la $C/vendor/etc/wifi/wpa_supplicant.conf; cat $C/tmp/recovery/wpa_supplicant.conf
echo "--- firmware links:"; ls -la $C/vendor/firmware | grep -E 'soc2_2|WMT|WIFI'
echo "--- wifi.driver.ready = $(cat $C/tmp/prop.wifi.driver.ready 2>/dev/null)"
