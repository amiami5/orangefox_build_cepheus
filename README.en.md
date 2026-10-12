# orangefox_build_cepheus

[English](README.en.md) | [日本語](README.md)

An environment for building OrangeFox (fox_12.1) for the Xiaomi Mi 9 (cepheus) against the ROM's 4.19 kernel.
The source tree (`12.1/`) is not included. It is fetched by the sync script.

- device tree: https://github.com/amiami5/device_xiaomi_cepheus_orangefox (branch `fox_12.1`)
- Target ROM: lineage-based Android 16 (kernel 4.19.325, develop-419), non-A/B with retrofit dynamic partitions

## Steps

```bash
# 1. Fetch the source (repo sync, about 70GB. Limited to -j4 to avoid throttling)
./orangefox_sync.sh --branch 12.1 --path "$PWD/12.1"

# 2. Replace the official device tree with our own
rm -rf 12.1/device/xiaomi/cepheus
git clone -b fox_12.1 https://github.com/amiami5/device_xiaomi_cepheus_orangefox \
    12.1/device/xiaomi/cepheus

# 3. Build
./build-cepheus.sh        # Pass the parallel job count as an argument (default: 6)
```

Output: `12.1/out/target/product/cepheus/OrangeFox-R12.0-Unofficial-cepheus.img`

## Changes from the original OrangeFox sync script

- Removed `--depth=1` from `repo init` / `repo sync` (to avoid problems when pushing)
- Changed `repo sync` to `-j4` (to avoid HTTP 429 from googlesource)
- Adjusted the `patches/` path to match this repository's root

## Flashing and booting

```cmd
fastboot flash recovery OrangeFox-R12.0-Unofficial-cepheus.img
```

- To boot, power off completely, then press **Volume Up + Power**. You can also enter recovery from the ROM's power menu
- Booting from the recovery partition requires the **recovery dtbo to be included** (with header v2, the bootloader drops to fastboot if it is empty). The device tree's `prebuilt/dtbo.img` provides it
- `adb sideload` works with the sideload USB configuration in the device tree's `init.recovery.qcom.rc` (`adb devices` shows `sideload`)
- `fastboot boot` only works from fastboot entered with **Volume Down + Power** (a degraded fastboot after a failure shows `Load Error`)

## Whether a rebuild is needed after a ROM update

Recovery does not use the ROM's userspace, so **most ROM updates do not require a rebuild**.
Rebuild only when the kernel or the encryption-related parts change, replacing the device tree's `prebuilt/` and similar files.

| ROM-side change | Rebuild | Replace |
|---|---|---|
| Kernel source / config changes (`CONFIG_UNICODE`, FS_ENCRYPTION, DM_DEFAULT_KEY, UFS encryption, driver fixes) | **Required** | `prebuilt/Image.gz` |
| dts changes (the dtb changes) | **Required** | `prebuilt/dtbs/`, `prebuilt/dtbo.img` |
| Encryption method changes (`fileencryption` / `wrappedkey` in fstab) | **Required** | `recovery/root/system/etc/recovery.fstab`, `BoardConfig.mk` |
| keymaster / gatekeeper HAL version or TZ firmware updates | **Required** | Blobs in `recovery/root/` |
| Major Android version updates (e.g. changes to the synthetic password format) | Depends | Check whether OrangeFox's decryption implementation keeps up |
| App, framework, system / vendor images, or SELinux policy updates | Not required | - |

If in doubt, check whether the ROM's kernel matches the one in the device tree. If it does, no rebuild is needed.

```bash
md5sum <ROM source>/out/target/product/cepheus/kernel \
       12.1/device/xiaomi/cepheus/prebuilt/Image.gz
```

Even if the kernel has changed, if the change is unrelated to /data decryption (for example, a fix to audio driver logging), it is enough to pick it up the next time the kernel is updated.

## When the ROM kernel is updated

Copy the ROM-side build outputs (`out/target/product/cepheus/`) into the device tree.

| Destination (device tree) | Source |
|---|---|
| `prebuilt/Image.gz` | `kernel` |
| `prebuilt/dtbs/*.dtb` | dtbs built by the ROM |
| `prebuilt/dtbo.img` | `dtbo.img` (**truncate to the total_size in the header**, so it fits the recovery partition) |

## About decryption (/data)

userdata is ext4 with casefold + FBE v2 + wrapped key. Decryption only works when all of the following are in place.

- Kernel `CONFIG_UNICODE` (enabled in the ROM's 4.19 kernel)
- `TW_SKIP_ADDITIONAL_FSTAB` (adds `inlinecrypt` to the ext4 device)
- `OF_FIX_DECRYPTION_ON_DATA_MEDIA` (does not re-mount /data after the DE key is loaded)
- keymaster 4.1 / gatekeeper 1.0 / qseecomd, plus the framework manifest and a libc++ stub
