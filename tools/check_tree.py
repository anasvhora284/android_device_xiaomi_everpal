#!/usr/bin/env python3
"""Static checks for the everpal recovery tree (run before every build).

Usage: python3 -I tools/check_tree.py <tree> <ref_dir>
  <tree>    device_xiaomi_everpal
  <ref_dir> ref/ (crdroid_boot/rd, vendor_everpal, docs/ variable lists)
Exit status 1 if any check fails.
"""
import os
import re
import subprocess
import sys

tree, ref = sys.argv[1], sys.argv[2]
docs = f"{ref}/docs"
fails = []


def check(ok, msg):
    print(("PASS " if ok else "FAIL ") + msg)
    if not ok:
        fails.append(msg)


def read(p):
    with open(p, errors="replace") as f:
        return f.read()


def words(path, prefix):
    return set(re.findall(rf"\b{prefix}[A-Z0-9_]+\b", read(path)))


board = read(f"{tree}/BoardConfig.mk")
board_code = "\n".join(l for l in board.splitlines() if not l.lstrip().startswith("#"))
setup = read(f"{tree}/vendorsetup.sh")
setup_code = "\n".join(l for l in setup.splitlines() if not l.lstrip().startswith("#"))
root = f"{tree}/recovery/root"

# 1. Every TW_/PB_ variable we set is understood by OrangeFox 12.1 / PBRP 12.1 / TWRP vendor config
known_tw = set(read(f"{docs}/tw_vars_all.txt").split())
known_pb = set().union(*(words(f"{docs}/{f}", "PB_") for f in os.listdir(docs) if f.startswith("pb")))
for v in sorted(set(re.findall(r"^\s*(TW_[A-Z0-9_]+)\s*[:+?]?=", board_code, re.M))):
    check(v in known_tw, f"TW var {v} is known to the recovery sources")
for v in sorted(set(re.findall(r"^\s*(PB_[A-Z0-9_]+)\s*[:+?]?=", board_code, re.M))):
    check(v in known_pb, f"PB var {v} is known to PBRP")

# 2. OrangeFox variables exist and none is obsolete
known_of = set(read(f"{docs}/ofox12_vars.txt").split())
obsolete = set(re.findall(r'"([A-Z0-9_]+)" is obsolete', read(f"{docs}/ofox12_bootable_orangefox.mk")))
for v in sorted(set(re.findall(r"export ((?:OF|FOX)_[A-Z0-9_]+)=", setup_code))):
    check(v in known_of and v not in obsolete, f"OrangeFox var {v} is valid and not obsolete")
check(subprocess.run(["bash", "-n", f"{tree}/vendorsetup.sh"]).returncode == 0, "vendorsetup.sh parses")
check("download" not in setup_code.lower() and "wget" not in setup_code and "curl" not in setup_code,
      "vendorsetup.sh downloads nothing at build time")

# 3. Files referenced by the build exist
for rel in ("prebuilt/Image.gz", "prebuilt/dtb/mt6833.dtb", "recovery/root/first_stage_ramdisk/fstab.mt6833",
            "recovery/root/system/etc/recovery.fstab", "recovery/root/system/etc/twrp.flags",
            "gatekeeper/Android.mk", "twrp_everpal.mk", "pb_everpal.mk"):
    check(os.path.isfile(f"{tree}/{rel}"), f"file exists: {rel}")
check(os.path.islink(f"{root}/system/flashlight/brightness"), "flashlight brightness symlink present")

# 4. Prebuilt kernel/dtb are byte-identical to crDroid 12.11 boot.img
for a, b in (("prebuilt/Image.gz", "crdroid_boot/out/kernel"), ("prebuilt/dtb/mt6833.dtb", "crdroid_boot/out/dtb")):
    check(open(f"{tree}/{a}", "rb").read() == open(f"{ref}/{b}", "rb").read(), f"{a} == crDroid {b}")

# 5. Decryption-critical fstab lines match the ROM exactly
rom = read(f"{ref}/crdroid_boot/rd/system/etc/recovery.fstab")
ours = read(f"{root}/system/etc/recovery.fstab")
for key in ("/dev/block/by-name/userdata", "/dev/block/by-name/metadata"):
    rl = [l.split() for l in rom.splitlines() if l.startswith(key)]
    ol = [l.split() for l in ours.splitlines() if l.startswith(key)]
    check(len(ol) == 1 and rl == ol, f"{key} line identical to crDroid fstab")
logical = lambda s: {l.split()[0] for l in s.splitlines() if "logical" in l and not l.startswith("#")}
logical_rom, logical_ours = logical(rom), logical(ours)
check(logical_rom == logical_ours, f"logical partition set matches ROM: {sorted(logical_ours)}")
check(read(f"{root}/first_stage_ramdisk/fstab.mt6833")
      == read(f"{ref}/crdroid_boot/rd/first_stage_ramdisk/system/etc/fstab.mt6833"), "first-stage fstab == crDroid")

# 6. twrp.flags safety
flags = read(f"{root}/system/etc/twrp.flags")
entries = [l for l in flags.splitlines() if l.startswith("/")]
forbidden = re.compile(r"by-name/(preloader|lk2?|tee[12]|scp[12]|sspm_[12]|dpm_[12]|mcupm_[12]|gz[12]|spmfw|efuse|seccfg|otp|pi_img|boot_para|para)\b")
check(not any(forbidden.search(l) for l in entries), "no bootloader-chain partition exposed")
check(not any(re.search(r"/dev/block/sd[a-z]", l) for l in entries), "no fixed /dev/block/sdX paths (internal UFS LUNs)")
# mmcblk0 is the microSD only because internal storage is UFS: prove that from the phone's own data
pre_sd = read(f"{ref}/phone_precheck.txt")
ufs = re.search(r"by-name/userdata -> /dev/block/sd[a-z]\d+", pre_sd) is not None
sd_is_mmc = re.search(r"^/sys/devices/platform/externdevice$", pre_sd, re.M) is not None and " mmcblk0 " in f" {pre_sd} "
mmc_lines = [l for l in entries if "mmcblk" in l]
check(all(l.startswith("/external_sd") for l in mmc_lines), "mmcblk only used by the /external_sd entry")
check(not mmc_lines or (ufs and sd_is_mmc), "mmcblk0 = microSD is proven (userdata on UFS sdX, mmcblk0 under externdevice)")
check(all(l.startswith("/external_sd") for l in entries if "wipeingui" in l), "only the microSD is wipeable from the GUI")
for p in ("nvram", "nvdata", "nvcfg", "protect1", "protect2", "persist", "proinfo", "md1img"):
    check(any(f"by-name/{p}" in l and "backup=1" in l for l in entries), f"{p} is backed up")
# A/B truth = the real by-name list read from the phone (phone_precheck.sh); crDroid's fstab was wrong here
pre = read(f"{ref}/phone_precheck.txt")
names = set(re.findall(r" ([a-z0-9_]+) -> /dev/block/", pre))
check(len(names) > 30, f"phone by-name list loaded ({len(names)} entries)")
for l in entries:
    m = re.search(r"by-name/([a-z0-9_]+)", l)
    if not m:
        continue
    n = m.group(1)
    if "slotselect" in l:
        check({f"{n}_a", f"{n}_b"} <= names, f"{n}: A/B on the phone (slotselect)")
    else:
        check(n in names, f"{n}: single partition exists on the phone")

# 7. TEE: every trusted app the ROM ships is present and identical; blobs identical to ROM vendor
vend = f"{ref}/vendor_everpal/proprietary/vendor"
rom_tas = sorted(os.listdir(f"{vend}/thh/ta"))
check(sorted(os.listdir(f"{root}/vendor/thh/ta")) == rom_tas, f"all {len(rom_tas)} trusted apps present")
for dirpath, _, files in os.walk(f"{root}/vendor"):
    for fn in files:
        rel = os.path.relpath(f"{dirpath}/{fn}", root)
        src = f"{ref}/vendor_everpal/proprietary/{rel}"
        if rel.startswith(("vendor/bin", "vendor/lib", "vendor/thh", "vendor/firmware")):
            if not os.path.isfile(src):  # e.g. vendor/lib/libmtk_drvb.so -> vendor/lib/mt6833/ (SYMLINK in proprietary-files)
                alt = os.path.join(os.path.dirname(src), "mt6833", os.path.basename(src))
                src = alt if os.path.isfile(alt) else src
            check(os.path.isfile(src) and open(src, "rb").read() == open(f"{root}/{rel}", "rb").read(),
                  f"blob identical to crDroid vendor: {rel}")
rc = read(f"{root}/vendor/etc/init/init.microtrust.rc")
rom_rc = read(f"{vend}/etc/init/microtrust.rc")
ta_ids = lambda s: sorted(re.findall(r"-[rt] ([0-9a-f]{32})", s))
check(ta_ids(rc) == ta_ids(rom_rc), "teei_daemon TA list identical to ROM's microtrust.rc")

# 8. Every NEEDED lib of the vendor blobs is shipped, relinked, or a core recovery lib
core = {"libc.so", "libm.so", "libdl.so", "libc++.so", "liblog.so", "libcutils.so", "libutils.so",
        "libbase.so", "libhardware.so", "libhidlbase.so"}
relinked = set(re.findall(r"/([A-Za-z0-9_.@-]+\.so)", board_code))
shipped = {fn for _, _, fs in os.walk(f"{root}/vendor/lib64") for fn in fs}
for blob in ("vendor/bin/teei_daemon", "vendor/bin/hw/android.hardware.keymaster@4.1-service.beanpod",
             "vendor/lib64/hw/gatekeeper.beanpod.so", "vendor/lib64/libTEECommon.so",
             "vendor/lib64/libteei_daemon_vfs.so", "vendor/lib64/libimsg_log.so"):
    out = subprocess.run(["readelf", "-d", f"{root}/{blob}"], capture_output=True, text=True).stdout
    for lib in re.findall(r"\[([^\]]+\.so)\]", out):
        check(lib in core | relinked | shipped, f"{blob} -> {lib} available")

# 9. init: every started service is defined
rcs = "".join(read(os.path.join(d, f)) for d, _, fs in os.walk(root) for f in fs if f.endswith(".rc"))
rcs += read(f"{tree}/gatekeeper/android.hardware.gatekeeper@1.0-service-recovery.rc")
defined = set(re.findall(r"^service (\S+)", rcs, re.M))
external = {"health-hal-2-1", "boot-hal-1-2", "adbd"}  # provided by TWRP's own rc files
for s in sorted(set(re.findall(r"^\s*start (\S+)", rcs, re.M))):
    check(s in defined or s in external, f"started service '{s}' is defined")

# 9b. OS version/patch must equal the phone's (TEE key binding); never the 99.87.36 / 2127 spoof
pre = read(f"{ref}/phone_precheck.txt")
phone_patch = re.search(r"===== build\n[^\n]*\n[^\n]*\n16\n(\d{4}-\d\d-\d\d)", pre)
check(phone_patch is not None, "phone security patch found in precheck")
if phone_patch:
    check(re.search(rf"^PLATFORM_SECURITY_PATCH := {phone_patch.group(1)}$", board_code, re.M) is not None,
          f"PLATFORM_SECURITY_PATCH == phone's {phone_patch.group(1)}")
check(re.search(r"^PLATFORM_VERSION := 16$", board_code, re.M) is not None, "PLATFORM_VERSION == 16 (phone)")
check("99.87.36" not in board_code and "2127-" not in board_code and "2099-" not in board_code, "no version/patch spoof")
pb = read(f"{tree}/pb_everpal.mk")
check("root/etc/recovery.fstab" in pb, "PBRP copies recovery.fstab into /etc")

# 9c. service managers must survive decryption (IBootControl for A/B installs, AIDL vibrator)
check(not re.search(r"^\s*stop (hw)?servicemanager\s*$", rcs, re.M), "service managers are never stopped")
# 9d. haptics wiring: flag, relinked service, init service, VINTF entry
check("TW_SUPPORT_INPUT_AIDL_HAPTICS := true" in board_code, "AIDL haptics enabled")
check("vibrator-service.everpal-recovery" in board_code, "vibrator service relinked into recovery")
check(re.search(r"^service \S+ /system/bin/vibrator-service\.everpal-recovery$", rcs, re.M) is not None, "vibrator init service defined")
vintf = read(f"{root}/vendor/etc/vintf/manifest.xml")
check("<name>android.hardware.vibrator</name>" in vintf and "IVibrator/default" in vintf, "vibrator declared in VINTF")
check('"awinic_haptic"' in read(f"{tree}/vibrator/aidl/Vibrator.cpp"), "vibrator accepts awinic_haptic")

# 9e. battery gauge: 32-bit runtime == copy taken from the phone, service wiring, nvram never involved
p32 = f"{ref}/phone_system_lib32"
for fn in sorted(os.listdir(f"{root}/system/lib")):
    check(open(f"{root}/system/lib/{fn}", "rb").read() == open(f"{p32}/lib/{fn}", "rb").read(), f"32-bit lib == phone copy: {fn}")
check(open(f"{root}/system/bin/linker", "rb").read() == open(f"{p32}/linker", "rb").read(), "32-bit linker == phone copy")
check(re.search(r"^service fuelgauged /system/bin/linker /vendor/bin/fuelgauged\n\s+setenv LD_LIBRARY_PATH /system/lib:/vendor/lib$", rcs, re.M) is not None,
      "fuelgauged runs through the 32-bit loader with an explicit lib path")
check("TW_NO_BATT_PERCENT" not in board_code, "battery percentage enabled")
everything = "".join(l for d, _, fs in os.walk(tree) if not d.startswith(f"{tree}/.git")
                     for f in fs if f.endswith((".rc", ".mk", ".fstab", ".flags", ".xml", ".bp", ".sh"))
                     for l in read(os.path.join(d, f)).splitlines(True) if not l.lstrip().startswith(("#", "//")))
check("fuelgauged_nvram" not in everything and not os.path.exists(f"{root}/vendor/bin/fuelgauged_nvram"), "fuelgauged_nvram is never shipped or started")
check("/mnt/vendor" not in "".join(l for l in (read(f"{root}/system/etc/recovery.fstab") + flags).splitlines(True) if not l.startswith("#")),
      "recovery never mounts anything under /mnt/vendor")
for p in ("nvdata", "nvcfg", "protect_f", "protect_s", "persist"):
    check(re.search(rf"^/{p}\s+emmc\s", flags, re.M) is not None, f"{p}: raw image backup only (never mounted)")

# 10. Boot-mode guard: flashable builds never carry twrpfastboot=1
check("TW_NO_FASTBOOT_BOOT := true" in board_code, "TW_NO_FASTBOOT_BOOT forced")
check(re.search(r"ifeq \(\$\(EVERPAL_RAMBOOT_TEST\),1\)\s*\n\s*BOARD_KERNEL_CMDLINE \+= twrpfastboot=1", board_code) is not None,
      "twrpfastboot=1 only inside the EVERPAL_RAMBOOT_TEST guard")
check(board_code.count("twrpfastboot") == 1, "twrpfastboot appears nowhere else")

print(f"\n{len(fails)} failure(s)")
sys.exit(1 if fails else 0)
