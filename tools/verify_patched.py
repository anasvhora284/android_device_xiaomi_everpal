#!/usr/bin/env python3
"""Compare boot images before/after an installer zip ran (zip_sandbox_test.sh output).

Usage: python3 -I tools/verify_patched.py <sandbox_dir> <recovery flashable.img> <tools_dir>
Pass = for each slot: identical header fields, kernel and dtb; ramdisk == the recovery's ramdisk.
"""
import gzip
import hashlib
import os
import re
import subprocess
import sys
import tempfile

sb, rec_img, tools = sys.argv[1:4]
fails = []


def check(ok, msg):
    print(("PASS " if ok else "FAIL ") + msg)
    if not ok:
        fails.append(msg)


def unpack(img):
    out = tempfile.mkdtemp()
    r = subprocess.run([sys.executable, "-I", f"{tools}/unpack_bootimg.py", "--boot_img", img, "--out", out],
                       capture_output=True, text=True)
    header = {k: v.strip() for k, v in re.findall(r"^([a-z ]+[a-z]): (.*)$", r.stdout, re.M)
              if k not in ("ramdisk size", "kernel_size")}
    return out, header


def tree(ramdisk_path):
    data = open(ramdisk_path, "rb").read()
    if data[:2] == b"\x1f\x8b":
        data = gzip.decompress(data)
    d = tempfile.mkdtemp()
    subprocess.run(["cpio", "-idm", "--quiet"], input=data, cwd=d, check=False)
    res = {}
    for root, dirs, files in os.walk(d):
        for n in dirs + files:
            p = os.path.join(root, n)
            st = os.lstat(p)
            what = ("link:" + os.readlink(p) if os.path.islink(p) else "dir" if os.path.isdir(p)
                    else hashlib.sha256(open(p, "rb").read()).hexdigest())
            res[os.path.relpath(p, d)] = (oct(st.st_mode), what)
    return res


rec_dir, _ = unpack(rec_img)
want = tree(f"{rec_dir}/ramdisk")
same = lambda a, b: open(a, "rb").read() == open(b, "rb").read()
for s in ("a", "b"):
    pre_dir, pre_h = unpack(f"{sb}/pre_boot_{s}.img")
    new_dir, new_h = unpack(f"{sb}/patched_boot_{s}.img")
    diff = {k: (pre_h.get(k), new_h.get(k)) for k in set(pre_h) | set(new_h) if pre_h.get(k) != new_h.get(k)}
    check(not diff, f"slot {s}: header fields identical (os version {new_h.get('os version')}, patch {new_h.get('os patch level')})"
          + (f" DIFF {diff}" if diff else ""))
    # magiskboot repack re-compresses the kernel, so compare the decompressed image
    raw = lambda p: (gzip.decompress(open(p, "rb").read()) if open(p, "rb").read(2) == b"\x1f\x8b" else open(p, "rb").read())
    check(raw(f"{pre_dir}/kernel") == raw(f"{new_dir}/kernel"),
          f"slot {s}: kernel content identical (user's own kernel kept; bytes {'identical' if same(f'{pre_dir}/kernel', f'{new_dir}/kernel') else 're-compressed'})")
    check(same(f"{pre_dir}/dtb", f"{new_dir}/dtb"), f"slot {s}: dtb identical")
    got = tree(f"{new_dir}/ramdisk")
    bad = sorted(k for k in set(want) | set(got) if want.get(k) != got.get(k))
    check(not bad, f"slot {s}: ramdisk == recovery ramdisk ({len(got)} entries, {len(bad)} differ)")
    for k in bad[:10]:
        print("    ", k)

print(f"\n{len(fails)} failure(s)")
sys.exit(1 if fails else 0)
