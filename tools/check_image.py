#!/usr/bin/env python3
"""Verify a built everpal recovery boot image before it touches a phone.

Usage: python3 -I tools/check_image.py <boot.img> <tree> <mode> <tools_dir>
  <mode>      ramboot  -> must carry twrpfastboot=1 (fastboot-boot test only, never flash)
              flash    -> must NOT carry twrpfastboot=1
  <tools_dir> directory with unpack_bootimg.py and avbtool.py
"""
import gzip
import os
import re
import subprocess
import sys
import tempfile

img, tree, mode, tools = sys.argv[1:5]
assert mode in ("ramboot", "flash"), "mode must be ramboot or flash"
fails = []


def check(ok, msg):
    print(("PASS " if ok else "FAIL ") + msg)
    if not ok:
        fails.append(msg)


work = tempfile.mkdtemp()
u = subprocess.run([sys.executable, "-I", f"{tools}/unpack_bootimg.py", "--boot_img", img, "--out", work],
                   capture_output=True, text=True)
check(u.returncode == 0, "unpack_bootimg.py succeeded")
info = u.stdout
field = lambda k: (re.search(rf"^{k}: (.*)$", info, re.M) or [None, ""])[1].strip()

# Header / layout (values from crDroid 12.11 boot.img)
check(field("boot magic") == "ANDROID!", "boot magic")
check(field("boot image header version") == "2", "header v2")
check(field("page size") == "2048", "page size 2048")
check(field("kernel load address") == "0x40080000", "kernel load address")
check(field("ramdisk load address") == "0x51100000", "ramdisk load address")
check(field("kernel tags load address") == "0x47c80000", "tags load address")
check(field("dtb address") == "0x0000000047c80000", "dtb address")
check(os.path.getsize(img) <= 134217728, "image fits the 128 MiB boot partition")
# Beanpod TEE binds keys to the boot header OS version/patch: must equal her real boot_b header
# (16.0.0 / 2026-08). A newer value made the TEE request a key upgrade on the first real test.
check(field("os version") == "16.0.0", f"header os version == phone's 16.0.0 (got {field('os version')})")
check(field("os patch level") == "2026-08", f"header os patch == phone's 2026-08 (got {field('os patch level')})")

cmdline = field("command line args")
# selinux=permissive: the crypto services run with seclabel u:r:recovery:s0 and would be denied otherwise
for tok in ("bootopt=64S3,32N2,64N2", "androidboot.init_fatal_reboot_target=recovery", "androidboot.selinux=permissive"):
    check(tok in cmdline, f"cmdline has {tok}")
check(("twrpfastboot=1" in cmdline) == (mode == "ramboot"), f"twrpfastboot=1 present only in ramboot mode ({mode})")

same = lambda a, b: open(a, "rb").read() == open(b, "rb").read()
check(same(f"{work}/kernel", f"{tree}/prebuilt/Image.gz"), "kernel identical to prebuilt")
check(same(f"{work}/dtb", f"{tree}/prebuilt/dtb/mt6833.dtb"), "dtb identical to prebuilt")

# Ramdisk: must be gzip (4.14 kernel), unpack with cpio into a temp dir
raw = open(f"{work}/ramdisk", "rb").read()
check(raw[:2] == b"\x1f\x8b", "ramdisk is gzip-compressed")
rd = f"{work}/rd"
os.makedirs(rd)
subprocess.run(["cpio", "-idm", "--quiet"], input=gzip.decompress(raw), cwd=rd, check=False)

src_root = f"{tree}/recovery/root"
FSTABS = ("first_stage_ramdisk/fstab.mt6833", "system/etc/recovery.fstab")
strip = lambda t: t.replace(",formattable", "").replace("formattable,", "")
for d, _, fs in os.walk(src_root):
    for f in fs:
        rel = os.path.relpath(f"{d}/{f}", src_root)
        p = f"{rd}/{rel}"
        if rel in FSTABS and os.path.isfile(p):
            got, want = open(p).read(), open(f"{src_root}/{rel}").read()
            if mode == "ramboot":   # build strips 'formattable' so the RAM test can never auto-format
                check("formattable" not in got and got == strip(want), f"ramdisk {rel} == tree minus formattable")
            else:
                check(got == want, f"ramdisk {rel} identical to tree (formattable kept for flashable)")
            continue
        if rel == "system/etc/twrp.flags" and os.path.isfile(p):   # PBRP build drops only the /storage line
            got, want = open(p).read(), open(f"{src_root}/{rel}").read()
            no_storage = "".join(l for l in want.splitlines(True) if not re.match(r"/storage\s", l))
            check(got in (want, no_storage), f"ramdisk {rel} == tree (or tree minus /storage for PBRP)")
            continue
        check(os.path.lexists(p) and (os.path.islink(p) or same(p, f"{src_root}/{rel}")), f"ramdisk has {rel}")

board = open(f"{tree}/BoardConfig.mk").read()
for lib in re.findall(r"\$\(TARGET_OUT_SHARED_LIBRARIES\)/([A-Za-z0-9_.@-]+\.so)", board):
    check(os.path.exists(f"{rd}/system/lib64/{lib}"), f"relinked lib present: {lib}")
for b in ("system/bin/vold_prepare_subdirs", "system/bin/update_engine_sideload"):
    check(os.path.exists(f"{rd}/{b}") or os.path.exists(f"{rd}/{b.replace('system/', '')}"), f"has {b}")
gk = [p for p in ("vendor/bin/hw/android.hardware.gatekeeper@1.0-service-recovery",) if os.path.exists(f"{rd}/{p}")]
check(bool(gk), "gatekeeper recovery service built into ramdisk")

props = ""
for p in ("prop.default", "vendor/build.prop", "system/etc/prop.default", "default.prop"):
    if os.path.exists(f"{rd}/{p}"):
        props += open(f"{rd}/{p}", errors="replace").read()
for kv in ("ro.hardware.gatekeeper=beanpod", "ro.crypto.volume.filenames_mode=aes-256-cts",
           "ro.vendor.build.security_patch=2024-02-01"):
    check(kv in props, f"prop {kv}")

# vibrator service: present, and every lib it links is in the ramdisk (a missing one would make
# TWRP block on getService at every tap)
vib = f"{rd}/system/bin/vibrator-service.everpal-recovery"
check(os.path.isfile(vib), "vibrator service binary in ramdisk")
if os.path.isfile(vib):
    out = subprocess.run(["readelf", "-d", vib], capture_output=True, text=True).stdout
    for lib in re.findall(r"\[([^\]]+\.so)\]", out):
        found = any(os.path.exists(f"{rd}/{d}/{lib}") for d in ("system/lib64", "vendor/lib64", "lib64"))
        check(found, f"vibrator dependency {lib} in ramdisk")

# battery gauge: 32-bit loader + every library fuelgauged / libfgauge_gm30 / libmtk_drvb need
check(os.path.isfile(f"{rd}/system/bin/linker"), "32-bit linker in ramdisk")
for blob in ("vendor/bin/fuelgauged", "vendor/lib/libfgauge_gm30.so", "vendor/lib/libmtk_drvb.so"):
    check(os.path.isfile(f"{rd}/{blob}"), f"gauge blob in ramdisk: {blob}")
    if os.path.isfile(f"{rd}/{blob}"):
        out = subprocess.run(["readelf", "-d", f"{rd}/{blob}"], capture_output=True, text=True).stdout
        for lib in re.findall(r"\[([^\]]+\.so)\]", out):
            check(any(os.path.exists(f"{rd}/{d}/{lib}") for d in ("system/lib", "vendor/lib")), f"{os.path.basename(blob)} -> {lib} (32-bit) in ramdisk")
check(not os.path.exists(f"{rd}/vendor/bin/fuelgauged_nvram"), "fuelgauged_nvram not in ramdisk")

# boot control HAL reads /etc/recovery.fstab: /etc must be a link to /system/etc or contain the file
etc = f"{rd}/etc"
etc_ok = (os.path.islink(etc) and os.readlink(etc).rstrip("/") == "/system/etc" and os.path.isfile(f"{rd}/system/etc/recovery.fstab")) \
    or os.path.isfile(f"{etc}/recovery.fstab")
check(etc_ok, "/etc/recovery.fstab resolvable (boot control HAL; PBRP hang otherwise)")

# AVB footer: same key / algorithm / partition as the ROM's boot
a = subprocess.run([sys.executable, "-I", f"{tools}/avbtool.py", "info_image", "--image", img],
                   capture_output=True, text=True)
check(a.returncode == 0, "avbtool info_image succeeded")
avb = a.stdout
check("SHA256_RSA2048" in avb, "AVB algorithm SHA256_RSA2048")
check("cdbb77177f731920bbe0a0f94f84d9038ae0617d" in avb, "AVB key = testkey_rsa2048 (same as crDroid boot)")
check(re.search(r"Partition Name:\s+boot", avb) is not None, "AVB hash descriptor for 'boot'")
check(re.search(r"Rollback Index:\s+1\b", avb) is not None, "AVB rollback index 1 (same as crDroid boot)")

print(f"\n{len(fails)} failure(s)")
sys.exit(1 if fails else 0)
