#!/usr/bin/env python3
"""Verify a recovery installer zip installs exactly the ramdisk of the checked flashable image.

Usage: python3 -I tools/check_zip.py <installer.zip> <flashable boot.img> <ofox|pbrp> <tools_dir>

Both installers dump each slot's boot, `magiskboot unpack -h` it (keeping the user's kernel and
header), swap in the recovery ramdisk and repack. This checks that ramdisk and that configuration.
"""
import gzip
import hashlib
import lzma
import os
import re
import subprocess
import sys
import tempfile
import zipfile

zpath, img, flavour, tools = sys.argv[1:5]
assert flavour in ("ofox", "pbrp")
fails = []


def check(ok, msg):
    print(("PASS " if ok else "FAIL ") + msg)
    if not ok:
        fails.append(msg)


def unpack_ramdisk(boot_img):
    """Return the decompressed ramdisk cpio bytes of a boot image."""
    out = tempfile.mkdtemp()
    r = subprocess.run([sys.executable, "-I", f"{tools}/unpack_bootimg.py", "--boot_img", boot_img, "--out", out],
                       capture_output=True, text=True)
    check(r.returncode == 0, f"unpack {os.path.basename(boot_img)}")
    return decompress(open(f"{out}/ramdisk", "rb").read())


def decompress(data):
    if data[:2] == b"\x1f\x8b":
        return gzip.decompress(data)
    if data[:6] == b"\xfd7zXZ\x00":
        return lzma.decompress(data)
    return data  # already a plain cpio


def tree(cpio):
    """{path: (mode, sha256 | 'link:target' | 'dir')} for every entry of a newc cpio, incl. dir symlinks."""
    d = tempfile.mkdtemp()
    r = subprocess.run(["cpio", "-idm", "--quiet"], input=cpio, cwd=d, capture_output=True)
    check(r.returncode == 0, "cpio extracted cleanly")
    res = {}
    for root, dirs, files in os.walk(d):  # os.walk does not follow dir symlinks; they appear in dirs
        for name in dirs + files:
            p = os.path.join(root, name)
            st = os.lstat(p)
            if os.path.islink(p):
                what = "link:" + os.readlink(p)
            elif os.path.isdir(p):
                what = "dir"
            else:
                what = hashlib.sha256(open(p, "rb").read()).hexdigest()
            res[os.path.relpath(p, d)] = (oct(st.st_mode), what)
    return res


work = tempfile.mkdtemp()
with zipfile.ZipFile(zpath) as z:
    names = z.namelist()
    z.extractall(work)

ub = f"{work}/META-INF/com/google/android/update-binary"
check(os.path.isfile(ub), "update-binary present")
script = open(ub, errors="replace").read() if os.path.isfile(ub) else ""
check(any(n.endswith("magiskboot") for n in names), "magiskboot shipped in the zip")
check("unpack -h" in script, "installer unpacks with -h (keeps the user's kernel + header)")  # template text

want = tree(unpack_ramdisk(img))
check(len(want) > 100, f"reference ramdisk from flashable image ({len(want)} files)")

if flavour == "pbrp":
    check(re.search(r"^IS_AB=true$", script, re.M) is not None, "PBRP installer: IS_AB=true")
    check(re.search(r"^IS_RECOVERY_AS_BOOT=true$", script, re.M) is not None, "PBRP installer: IS_RECOVERY_AS_BOOT=true")
    cpios = sorted((os.path.getsize(f"{work}/{n}"), n) for n in names if n.endswith(".cpio"))
    check(bool(cpios), "PBRP zip carries a ramdisk cpio")
    got = tree(decompress(open(f"{work}/{cpios[-1][1]}", "rb").read())) if cpios else {}
else:
    check(re.search(r'^TARGET_DEVICE="?everpal"?$', script, re.M) is not None, "OrangeFox installer: TARGET_DEVICE=everpal")
    check(re.search(r'^BOOT_PARTITION="/dev/block/by-name/boot"$', script, re.M) is not None,
          "OrangeFox installer: BOOT_PARTITION=/dev/block/by-name/boot")
    # these select update-binary's "patch each slot's boot ramdisk" path (not vendor_boot / recovery_ab)
    check(re.search(r'^FOX_AB_DEVICE="1"', script, re.M) is not None, 'OrangeFox installer: FOX_AB_DEVICE="1"')
    check(re.search(r'^FOX_VENDOR_BOOT_RECOVERY="1"', script, re.M) is None, "OrangeFox installer: not vendor_boot mode")
    check(os.path.isfile(f"{work}/recovery.img"), "OrangeFox zip carries recovery.img")
    got = tree(unpack_ramdisk(f"{work}/recovery.img")) if os.path.isfile(f"{work}/recovery.img") else {}

missing = sorted(set(want) - set(got))
extra = sorted(set(got) - set(want))
differ = sorted(k for k in set(want) & set(got) if want[k] != got[k])
check(not missing and not extra and not differ,
      f"zip ramdisk == flashable image ramdisk (missing {len(missing)}, extra {len(extra)}, differ {len(differ)})")
for k in (missing + extra + differ)[:15]:
    print("   ", k)

print(f"\n{len(fails)} failure(s)")
sys.exit(1 if fails else 0)
