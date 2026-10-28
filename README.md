# Xiaomi everpal — AERA Recovery (Android 16)

Unified recovery tree for the MT6833 Xiaomi `evergo`, `evergreen`, `everpal`, and `opal` family. The AERA product remains `twrp_everpal`; the lunch target is `twrp_everpal-bp2a-eng`.

**Status: untested, builds not yet verified.** The expected recovery features are a software-rendered UI, FBEv2 and metadata decryption, Wi-Fi, and PC Connection. Wi-Fi uses the installed ROM's MediaTek vendor binaries, firmware, and (on stock kernels) kernel modules. The on-phone browser is Adreno-only upstream; mobile data has not been ported. None of these features has been validated in an AERA build or on a device yet.

## Build

```bash
mkdir -p ~/android/AERA_16.0
cd ~/android/AERA_16.0
repo init -u https://github.com/AERA-Recovery/android_manifest.git -b aera-16.0
repo sync -c --force-sync --no-clone-bundle --no-tags -j$(nproc)
git clone -b aera-16.0 https://github.com/anasvhora284/recovery_device_xiaomi_everpal device/xiaomi/everpal
# AERA_ENABLE_WLAN refuses to build without it:
git clone --depth=1 https://android.googlesource.com/platform/external/wpa_supplicant_8 -b android16-s2-release external/wpa_supplicant_8
export AERA_BUILD_DEVICE=everpal
source build/envsetup.sh
lunch twrp_everpal-bp2a-eng
mka adbd bootimage   # recovery-as-boot: the recovery IS boot.img on everpal
```

The expected image location is `out/target/product/everpal/`. No AERA installer or flash method has been verified. The scripts under `tools/`, including the build gates and `patch_installer.py`, target the older OrangeFox/PitchBlack builds and have not been adapted to AERA.

## Device notes

The recovery runs on the installed ROM's boot kernel, either Aqua 4.14.357 or Xiaomi stock 4.14.186. The bundled prebuilt kernel and DTB are for image creation; a recovery installer must preserve the ROM's kernel and first-stage fstab. AERA installer behavior has not been verified for this tree.

Beanpod keymaster must see the installed ROM's real OS version and security patch. `prepdecrypt-everpal.sh` reads them from the ROM's system and vendor partitions before the keymaster service starts. The built-in fallback stays at Android 16, platform patch `2026-08-01`, and vendor patch `2024-02-01`. Do not use future version or patch spoofing: it caused `KEY_REQUIRES_UPGRADE` on this device. Recovery sets SELinux permissive at early init so the fscrypt keyring can be created. The TEE and gatekeeper start immediately; only keymaster waits for prepdecrypt.

Wi-Fi is requested by AERA after prepdecrypt. The helper mounts the installed ROM vendor read only at a private path and starts its WMT stack. Aqua has WLAN built in; for stock kernels the helper tries the ROM's `connfem`, `wmt_drv`, `wmt_chrdev_wifi`, and `wlan_drv_gen4m` modules. No Wi-Fi blobs or modules are included here.

## Credits

- AERA Recovery, OrangeFox Recovery, and PitchBlack Recovery teams
- The original 2023 `evergo` TWRP tree
- Maintainer: **aetomtomy**

Licensed under Apache-2.0 — see [LICENSE](LICENSE).
