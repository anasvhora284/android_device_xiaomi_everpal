# device/xiaomi/everpal — OrangeFox & PitchBlack recovery tree

Unified recovery tree for the MT6833 (Dimensity 810) Xiaomi family sold as
**Redmi Note 11T 5G / POCO M4 Pro 5G / Redmi Note 11S 5G**:
`evergo`, `evergreen`, `everpal`, `opal`.

One tree builds both recoveries:

| Recovery | Manifest | Lunch target |
|---|---|---|
| OrangeFox R12.0 | `fox_12.1` | `twrp_everpal-eng` |
| PitchBlack 4.0 | `android-12.1` (`vendor/pb`) | `pb_everpal-eng` |

## What is different about this tree

The device ships Beanpod TEE + FBEv2 with metadata encryption, and the recovery boots on
**whatever kernel the installed ROM put in `boot`**. Three things follow from that, and they are
the reason this tree decrypts on ROMs other trees fail on:

1. **`recovery/root/system/bin/prepdecrypt-everpal.sh`** — before keymaster starts, it mounts the
   installed ROM's `system`/`vendor` read-only and copies that ROM's exact
   `ro.build.version.{release,sdk,security_patch}` and `ro.vendor.build.security_patch` into the
   recovery. Beanpod binds keys to those values, so a recovery that looks older than the ROM
   cannot unwrap the `/metadata` key (`Unable to decrypt metadata encryption`). Values are copied
   verbatim, never raised, so keys are never upgraded. Falls back to the built-in values if the
   ROM's partitions can't be read.
2. **`recovery/root/init.recovery.mt6833.rc`** — forces SELinux permissive at `early-init`. ROMs
   without `androidboot.selinux=permissive` on the cmdline leave init unable to create the fscrypt
   keyring (`Unable to find device keyring`), which breaks FBE decryption. Recovery only; a normal
   Android boot still runs Enforcing.
3. **Service ordering** (`recovery/root/vendor/etc/init/init.mt6833.rc`) — `teei_daemon` and
   `gatekeeper-1-0` start immediately from the recovery's own `/vendor`; only
   `keymaster-4-1-beanpod` waits on `prepdecrypt`. PitchBlack mounts the ROM's vendor over
   `/vendor`, which hides `gatekeeper@1.0-service-recovery` and otherwise hangs on
   "Trying to decrypt".

The installer also **keeps the installed ROM's first-stage `fstab.mt6833`** when it repacks the
boot image, instead of overwriting it with the tree's copy — overwriting it bootloops ported ROMs
whose fstab differs from stock.

Also here: an AOSP gatekeeper@1.0 HIDL service backed by `gatekeeper.beanpod.so` (`gatekeeper/`),
a recovery vibrator HAL (`vibrator/`), real battery percentage, and proper microSD labelling.

## Tested

| | ColorOS V2 A16 port | Infinity X 4.1 (Android 17) | crDroid 12.11 |
|---|---|---|---|
| Installs, ROM still boots | ✅ | ✅ | ✅ |
| Decrypts `/data` | n/a (port `/data` unencrypted) | ✅ pattern | ✅ |
| ROM boots Enforcing afterwards | ✅ | ✅ | ✅ |

## Installing

> ⚠️ **Update your firmware first.** Your phone needs the firmware your ROM requires — current ROMs
> need **HyperOS firmware**. Old MIUI 14 firmware has caused a bootloop. Make sure your ROM boots
> *before* you install the recovery.

| File | Use it when |
|---|---|
| `*-installer.zip` | **Recommended.** Flash from any existing recovery. Patches **both slots**, keeps your kernel and your ROM's fstab. |
| `*-flashable.img` | No recovery yet: `fastboot flash boot <img>` |
| `*-RAMBOOT-TEST-DO-NOT-FLASH.img` | Maintainer testing only — never flash this. |

After installing, reboot to recovery and unlock with your lockscreen PIN/pattern/password to
decrypt `/data`. Always verify the `.sha256sum` next to each file.

Harmless red lines in the log: APEX loop-mount errors, `Unable to mount '/auto0'` (USB-OTG with
nothing attached), and `Unable to mount '/data'` before you unlock.

## Building

`tools/build_recovery.sh` is the full pipeline: it syncs the manifest, adds the `external/nano`
dependency, builds `ofox`/`pbrp` × `flashable`/`ramboot`, and packs the installer zips.
`vendorsetup.sh` holds the OrangeFox `FOX_*`/`OF_*` settings (read only for OrangeFox builds;
PitchBlack ignores them).

```bash
bash tools/build_recovery.sh both     # or: ofox | pbrp
```

Four gates run on every artifact and the build fails if any of them does:

| Script | Checks |
|---|---|
| `tools/check_tree.py` | tree vs. the reference crDroid boot image (fstab, props, partition layout) |
| `tools/check_image.py` | the built boot image: header version, ramdisk contents, cmdline |
| `tools/check_zip.py` | the installer zip installs exactly the ramdisk that was built |
| `tools/verify_patched.py` | the post-build patch landed |

`tools/patch_installer.py` runs after the upstream installer zip is produced. It injects the
"keep the ROM's first-stage fstab" logic described above, plus this build's banner and footer.
Build from the tree alone and you get a working recovery, but **not** that fstab protection —
run the patcher, or port its logic, if you repackage the zip yourself.

## Reporting a problem

Open an issue with: your ROM name and version, which recovery and its build date (in the file
name, in the install banner, and in OrangeFox's About screen), what you did, and
`/tmp/recovery.log` — in recovery: `adb pull /tmp/recovery.log`.

## Credits

- The **OrangeFox** and **PitchBlack Recovery** teams
- The original 2023 `evergo` TWRP tree this started from
- Maintainer: **aetomtomy**

Licensed under Apache-2.0 — see [LICENSE](LICENSE).
