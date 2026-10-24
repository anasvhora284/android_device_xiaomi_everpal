#!/system/bin/sh
# Make the recovery present the INSTALLED ROM's OS version / patch levels to the Beanpod keymaster before it
# starts. Keys (incl. the /metadata key) are bound to these; a recovery that looks older than the ROM that made
# them cannot unwrap them (seen: Infinity X 17 / 2026-10-01 vs built-in 16 / 2026-08-01 -> "Unable to decrypt
# metadata encryption"). Values are copied exactly, never raised, so keys are never upgraded.
# Falls back to the built-in values if the ROM's partitions can't be read.
log() { echo "prepdecrypt-everpal: $*" > /dev/kmsg; }
setp() { [ -n "$2" ] && [ "$(getprop "$1")" != "$2" ] && resetprop "$1" "$2" && log "$1=$2"; }
getv() { grep -m1 "^$1=" "$2" 2>/dev/null | cut -d= -f2-; }

S=; V=
SL=$(getprop ro.boot.slot_suffix)
for i in $(seq 1 40); do   # TWRP maps the logical partitions (as <name>_<slot>) while processing the fstab
	for n in "$SL" ""; do
		[ -b /dev/block/mapper/system$n ] && [ -b /dev/block/mapper/vendor$n ] && { S=/dev/block/mapper/system$n; V=/dev/block/mapper/vendor$n; break 2; }
	done
	sleep 0.5
done
if [ -n "$S" ]; then
	mkdir -p /tmp/pd_s /tmp/pd_v
	mount -o ro "$S" /tmp/pd_s 2>/dev/null || mount -t erofs -o ro "$S" /tmp/pd_s 2>/dev/null
	mount -o ro "$V" /tmp/pd_v 2>/dev/null || mount -t erofs -o ro "$V" /tmp/pd_v 2>/dev/null
	SP=/tmp/pd_s/system/build.prop; [ -f "$SP" ] || SP=/tmp/pd_s/build.prop
	setp ro.build.version.release "$(getv ro.build.version.release "$SP")"
	setp ro.build.version.release_or_codename "$(getv ro.build.version.release_or_codename "$SP")"
	setp ro.build.version.sdk "$(getv ro.build.version.sdk "$SP")"
	setp ro.build.version.security_patch "$(getv ro.build.version.security_patch "$SP")"
	setp ro.vendor.build.security_patch "$(getv ro.vendor.build.security_patch /tmp/pd_v/build.prop)"
	umount /tmp/pd_s 2>/dev/null; umount /tmp/pd_v 2>/dev/null
else
	log "ROM partitions not found, using built-in version/patch"
fi
setprop vendor.prepdecrypt.everpal.done 1   # vendor.* : readable by vendor_init (rc lives in /vendor)
