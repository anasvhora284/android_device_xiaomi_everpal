#!/usr/bin/env python3
"""Patch an OFox/PBRP installer zip: keep the ROM's own first-stage fstab, and print our own banner.

The installers replace the whole boot ramdisk with the recovery ramdisk, which carries crDroid's
first_stage_ramdisk/fstab.*. Ports (e.g. ColorOS/HyperOS: erofs, mi_ext, no system_ext/vendor_dlkm/odm)
then fail first-stage mount and bootloop. Recovery mode uses its own recovery.fstab, so it is unaffected.
Our 12.1 init reads first_stage_ramdisk/fstab.<hw>; newer ROMs (crDroid) keep it in first_stage_ramdisk/system/etc/,
so that copy is used as a fallback (crDroid's is identical to the one already in our ramdisk).

    patch_installer.py <in.zip> <out.zip> [build-date]
"""
import sys, zipfile

REPO = "https://github.com/anasvhora284/recovery_device_xiaomi_everpal"

def banner(date, flavour, aera=False):
    # AERA is an OrangeFox fork: same installer layout ("ofox" anchors), different name
    name = "AERA R1.0 (TEST)" if aera else "OrangeFox R12.0" if flavour == "ofox" else "PitchBlack 4.0"
    L = [
      "",
      "=================================================",
      f"  {name}  -  everpal (unified)",
      "  Redmi Note 11T 5G / POCO M4 Pro 5G",
      "  evergo . evergreen . everpal . opal",
      f"  Build {date}   Maintainer: aetomtomy",
      "=================================================",
      "  This build decrypts /data on ANY ROM: it reads",
      "  YOUR ROM's Android version + security patch",
      "  before keymaster starts, so the TEE unwraps",
      "  your keys (stock, custom and ported ROMs).",
      "",
      "  Your ROM's own first-stage fstab is kept, so",
      "  ported ROMs keep booting after the install.",
      "",
      "  Both slots are patched. Your kernel is kept.",
      "=================================================",
      "",
    ]
    return "".join(f'ui_print "{t}"\n' for t in L)

def footer():
    L = [
      "",
      "=================================================",
      "  Done. Reboot to recovery, then unlock with your",
      "  lockscreen PIN/pattern/password to decrypt /data.",
      "",
      "  Harmless red lines you can ignore:",
      "   - APEX loop-mount errors",
      "   - Unable to mount /auto0  (USB-OTG, nothing in)",
      "   - Unable to mount /data   (before you unlock)",
      "",
      "  Thanks: OrangeFox & PitchBlack teams, and the",
      "  original 2023 evergo TWRP tree.",
      f"  Issues: {REPO}/issues",
      "=================================================",
      "",
    ]
    return "".join(f'ui_print "{t}"\n' for t in L)

BIN = "META-INF/com/google/android/update-binary"
# AERA zips also carry this copy of update-binary; AERA execs it instead when the zip is flashed from
# AERA itself, so it must get the same patch or AERA-to-AERA updates lose the ROM's fstab again.
AERA_BIN = "META-INF/com/google/android/aera-installer"

def keep(cpio):  # before the ramdisk is replaced: save the ROM's fstabs from the unpacked stock ramdisk
    return (f'    # keep the ROM\'s own first-stage fstab (ports use a different partition layout)\n'
            f'    rm -rf keep_fs; mkdir keep_fs\n'
            f'    for f in fstab.mt6833 fstab.emmc; do\n'
            f'      "$tool" cpio {cpio} "extract first_stage_ramdisk/$f keep_fs/$f" >/dev/null 2>&1 \\\n'
            f'        || "$tool" cpio {cpio} "extract first_stage_ramdisk/system/etc/$f keep_fs/$f" >/dev/null 2>&1\n'
            f'    done\n')

def restore(cpio):  # after: put them into the new ramdisk
    return (f'    for f in keep_fs/*; do [ -s "$f" ] || continue\n'
            f'      "$tool" cpio {cpio} "add 0644 first_stage_ramdisk/${{f##*/}} $f" >/dev/null 2>&1 \\\n'
            f'        && ui_print "- Kept your ROM\'s own first-stage ${{f##*/}} (ports stay bootable)" || abort "Failed to keep ${{f##*/}}"\n'
            f'    done; rm -rf keep_fs\n')

PATCHES = [  # (anchor line, ramdisk filename var)
    ('    cp -f "$recoverycpio" "$TARGET_RAMDISK_NAME"\n', '"$TARGET_RAMDISK_NAME"'),  # PBRP
    ('\t\tcp -f ramdisk-ofrp.cpio ramdisk.cpio\n', 'ramdisk.cpio'),                     # OrangeFox
]

BANNER_ANCHORS = [  # (flavour, anchor, where)  -- anchor must occur exactly once
    ("ofox", "\n# --\nMain\n# --\n", "before"),
    ("pbrp", 'ui_print "|-----------Unpacking the installer-----------|"\n', "before"),
]
FOOTER_ANCHORS = [
    ("ofox", '\tui_print "- Rebooting to Recovery now ..."\n'),
    ("pbrp", 'ui_print "|------------Installation finished!-----------|"\n'),
]

MARKER = "keep the ROM's own first-stage fstab"
BANNER_MARKER = "everpal (unified)"

def main(src, dst, date="unreleased"):
    zin = zipfile.ZipFile(src)
    s = zin.read(BIN).decode()
    if MARKER in s or BANNER_MARKER in s:
        raise SystemExit(f"{src} is already patched - patch the unmodified upstream zip instead")
    hits = 0
    for anchor, cpio in PATCHES:
        n = s.count(anchor)
        if n:
            assert n == 1, f"fstab anchor found {n} times"
            s = s.replace(anchor, keep(cpio) + anchor + restore(cpio)); hits += 1
    assert hits == 1, "expected exactly one known installer layout"

    flavour = None
    for f, anchor, _ in BANNER_ANCHORS:
        if s.count(anchor) == 1:
            flavour = f
            aera = "META-INF/com/google/android/aera-installer" in zin.namelist()
            s = s.replace(anchor, banner(date, f, aera) + anchor)
            break
    assert flavour, "no known banner anchor"
    for f, anchor in FOOTER_ANCHORS:
        if f == flavour:
            assert s.count(anchor) == 1, f"footer anchor for {f} found {s.count(anchor)} times"
            s = s.replace(anchor, footer() + anchor)

    with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as zout:
        for i in zin.infolist():
            if i.filename == AERA_BIN:
                assert zin.read(AERA_BIN) == zin.read(BIN), "aera-installer differs from update-binary"
            data = s.encode() if i.filename in (BIN, AERA_BIN) else zin.read(i)
            zout.writestr(i, data)
    print(f"patched {src} -> {dst} ({flavour}, banner+footer+fstab)")

if __name__ == "__main__":
    main(*sys.argv[1:4])
