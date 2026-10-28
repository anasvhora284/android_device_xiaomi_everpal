#!/bin/bash
# Host-side installer test: run an everpal recovery installer zip in an arm64 chroot (qemu-user) built
# from the recovery's own ramdisk, with boot_a/boot_b = loop devices holding a real ROM boot.img.
# Slot _b gets a marked "port" first-stage fstab to prove the installer keeps the ROM's fstab.
#   sudo bash aera_zip_qemu_test.sh <installer.zip> <rom boot.img> <recovery root dir> <outdir>
set -eu
ZIP=$1; ROMBOOT=$2; RROOT=$3; OUT=$4
MKB=${AERA_SRC:-$HOME/android/AERA_16.0}/system/tools/mkbootimg #/AERA_16.0/system/tools/mkbootimg
rm -rf "$OUT"; mkdir -p "$OUT"; W=$(mktemp -d)

# 1. slot images: a = ROM boot as is, b = ROM boot with a marker line in its first-stage fstab
cp "$ROMBOOT" "$OUT/pre_boot_a.img"
python3 $MKB/unpack_bootimg.py --boot_img "$ROMBOOT" --out $W/u --format=mkbootimg > $W/args
mkdir $W/rd && (cd $W/rd && gzip -dc ../u/ramdisk | cpio -idm --quiet)
echo "# PORT-ROM-MARKER keep-me" >> $W/rd/first_stage_ramdisk/system/etc/fstab.mt6833
(cd $W/rd && find . | cpio -o -H newc --quiet | gzip -9) > $W/u/ramdisk
eval python3 $MKB/mkbootimg.py $(cat $W/args) --output $W/b.img
truncate -s $(stat -c %s "$ROMBOOT") $W/b.img; cp $W/b.img "$OUT/pre_boot_b.img"

# 2. chroot = recovery ramdisk + fake by-name links to loop devices
C=$W/root; cp -a "$RROOT" $C
mkdir -p $C/dev $C/proc $C/tmp $C/dev/block/by-name
cp "$OUT/pre_boot_a.img" $W/slot_a.img; cp "$OUT/pre_boot_b.img" $W/slot_b.img
LA=$(losetup -f --show $W/slot_a.img); LB=$(losetup -f --show $W/slot_b.img)
trap 'umount -l $C/dev/block/loopa $C/dev/block/loopb $C/proc 2>/dev/null; losetup -d $LA $LB 2>/dev/null' EXIT
touch $C/dev/block/loopa $C/dev/block/loopb $C/dev/null 2>/dev/null || true
mount --bind $LA $C/dev/block/loopa; mount --bind $LB $C/dev/block/loopb
mount --bind /dev/null $C/dev/null
ln -sf /dev/block/loopa $C/dev/block/by-name/boot_a; ln -sf /dev/block/loopb $C/dev/block/by-name/boot_b
mount -t proc proc $C/proc
# no property service in a chroot: answer the props the installer reads
mv $C/system/bin/getprop $C/system/bin/getprop.real 2>/dev/null || true
cat > $C/system/bin/getprop <<'G'
#!/system/bin/sh
case "$1" in
  ro.product.device) echo everpal;; ro.boot.slot_suffix) echo _b;; ro.build.ab_update) echo true;;
  ro.boot.dynamic_partitions) echo true;; ro.virtual_ab.enabled) echo true;; *) echo "";;
esac
G
chmod 755 $C/system/bin/getprop
cp "$ZIP" $C/tmp/installer.zip
unzip -p "$ZIP" META-INF/com/google/android/update-binary > $C/tmp/update-binary
# 3. run it exactly like recovery does: update-binary <api> <outfd> <zip>
set +e
chroot $C /system/bin/sh /tmp/update-binary 3 1 /tmp/installer.zip > "$OUT/install_output.txt" 2>&1
echo "update-binary exit: $?" | tee -a "$OUT/install_output.txt"
set -e
sync; cp $W/slot_a.img "$OUT/patched_boot_a.img"; cp $W/slot_b.img "$OUT/patched_boot_b.img"
# 4. was the port marker kept on slot b?
python3 $MKB/unpack_bootimg.py --boot_img "$OUT/patched_boot_b.img" --out $W/pb >/dev/null
mkdir $W/prd && (cd $W/prd && gzip -dc ../pb/ramdisk 2>/dev/null | cpio -idm --quiet 2>/dev/null || (cd $W/prd && cat ../pb/ramdisk | cpio -idm --quiet))
grep -rl "PORT-ROM-MARKER" $W/prd/first_stage_ramdisk 2>/dev/null && echo "PASS slot b: ROM's own first-stage fstab kept" || echo "FAIL slot b: port fstab marker lost"
