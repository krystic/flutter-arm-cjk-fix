# Flutter Engine SO Library Directory

This directory contains custom-compiled Flutter Engine shared libraries that fix the fontconfig issue on ARM64 Linux systems.

## Available Versions

- `libflutter_linux_gtk.so.X.Y.Z` - Compiled with fontconfig support for Flutter X.Y.Z
  - Fixes: Root cause of CJK character rendering on ARM64
  - Auto-detected from app source code (.fvmrc)

## Usage

The `flutter-font-fix` script automatically:
1. Detects the app's Flutter version from GitHub source (.fvmrc)
2. Checks if a matching SO file exists in this directory
3. Mounts the SO file to replace the official one

No manual version mapping needed!

## Build Information

These libraries were compiled from Flutter Engine source with the following modifications:
- `flutter_use_fontconfig = true` in args.gn
- Target: linux-arm64
- Mode: debug/profile/release

For build instructions, see `../FONTCONFIG_BUG_INVESTIGATION.md`

## Example

```bash
# Place your compiled SO file here:
lib/libflutter_linux_gtk.so.3.35.3

# Run repair (auto-detects version):
sudo flutter-font-fix -a desktop-security-center

# Output:
# [INFO] Auto-detecting Flutter version...
#        Repository: https://github.com/canonical/desktop-security-center
#        Commit: d93b42d
#        Flutter version: 3.35.3
# [INFO] Found matching SO file!
#        SO file: libflutter_linux_gtk.so.3.35.3
# [OK] Root cause fixed with Flutter Engine replacement!
```
## Flutter 3.38.5
- Flutter Commit: f6ff1529fd6d8af5f706051d9251ac9231c83407
- Built on: 2025-12-26 07:54:34 UTC
- Size: 32M
- Platform: Linux ARM64
- Build Type: Release
- Features: Fontconfig enabled
- Built by: GitHub Actions


## Flutter 3.38.6
- Flutter Commit: 8b872868494e429d94fa06dca855c306438b22c0
- Built on: 2026-01-09 20:44:48 UTC
- Size: 32M
- Platform: Linux ARM64
- Build Type: Release
- Features: Fontconfig enabled
- Built by: GitHub Actions


## Flutter 3.38.7
- Flutter Commit: 3b62efc2a3da49882f43c372e0bc53daef7295a6
- Built on: 2026-01-14 20:44:44 UTC
- Size: 32M
- Platform: Linux ARM64
- Build Type: Release
- Features: Fontconfig enabled
- Built by: GitHub Actions


## Flutter 3.38.8
- Flutter Commit: bd7a4a6b5576630823ca344e3e684c53aa1a0f46
- Built on: 2026-01-27 20:56:22 UTC
- Size: 32M
- Platform: Linux ARM64
- Build Type: Release
- Features: Fontconfig enabled
- Built by: GitHub Actions


## Flutter 3.38.9
- Flutter Commit: 67323de285b00232883f53b84095eb72be97d35c
- Built on: 2026-01-29 21:03:56 UTC
- Size: 32M
- Platform: Linux ARM64
- Build Type: Release
- Features: Fontconfig enabled
- Built by: GitHub Actions


## Flutter 3.41.0
- Flutter Commit: 44a626f4f0027bc38a46dc68aed5964b05a83c18
- Built on: 2026-02-11 21:14:59 UTC
- Size: 33M
- Platform: Linux ARM64
- Build Type: Release
- Features: Fontconfig enabled
- Built by: GitHub Actions


## Flutter 3.41.1
- Flutter Commit: 582a0e7c5581dc0ca5f7bfd8662bb8db6f59d536
- Built on: 2026-02-13 21:04:55 UTC
- Size: 33M
- Platform: Linux ARM64
- Build Type: Release
- Features: Fontconfig enabled
- Built by: GitHub Actions


## Flutter 3.41.2
- Flutter Commit: 90673a4eef275d1a6692c26ac80d6d746d41a73a
- Built on: 2026-02-20 04:36:08 UTC
- Size: 33M
- Platform: Linux ARM64
- Build Type: Release
- Features: Fontconfig enabled
- Built by: GitHub Actions


## Flutter 3.41.3
- Flutter Commit: 48c32af0345e9ad5747f78ddce828c7f795f7159
- Built on: 2026-03-02 21:05:52 UTC
- Size: 33M
- Platform: Linux ARM64
- Build Type: Release
- Features: Fontconfig enabled
- Built by: GitHub Actions


## Flutter 3.41.4
- Flutter Commit: ff37bef603469fb030f2b72995ab929ccfc227f0
- Built on: 2026-03-04 20:46:32 UTC
- Size: 33M
- Platform: Linux ARM64
- Build Type: Release
- Features: Fontconfig enabled
- Built by: GitHub Actions


## Flutter 3.41.5
- Flutter Commit: 2c9eb20739dfec95e2c74bd3dfa4601b0a8a36aa
- Built on: 2026-03-18 21:15:54 UTC
- Size: 33M
- Platform: Linux ARM64
- Build Type: Release
- Features: Fontconfig enabled
- Built by: GitHub Actions


## Flutter 3.41.6
- Flutter Commit: db50e20168db8fee486b9abf32fc912de3bc5b6a
- Built on: 2026-03-26 20:40:32 UTC
- Size: 33M
- Platform: Linux ARM64
- Build Type: Release
- Features: Fontconfig enabled
- Built by: GitHub Actions


## Flutter 3.41.7
- Flutter Commit: cc0734ac716fbb8b90f3f9db8020958b1553afa7
- Built on: 2026-04-16 20:41:44 UTC
- Size: 33M
- Platform: Linux ARM64
- Build Type: Release
- Features: Fontconfig enabled
- Built by: GitHub Actions


## Flutter 3.41.8
- Flutter Commit: 02085feb3f5d8a8156e5e28512b9d99351d510c0
- Built on: 2026-04-27 20:47:04 UTC
- Size: 33M
- Platform: Linux ARM64
- Build Type: Release
- Features: Fontconfig enabled
- Built by: GitHub Actions


## Flutter 3.41.9
- Flutter Commit: 00b0c91f06209d9e4a41f71b7a512d6eb3b9c694
- Built on: 2026-04-30 20:29:14 UTC
- Size: 33M
- Platform: Linux ARM64
- Build Type: Release
- Features: Fontconfig enabled
- Built by: GitHub Actions


## Flutter 3.38.10
- Flutter Commit: c6f67dede3d4aa1aa7a69dd56a3494a5cde6cc80
- Built on: 2026-05-02 03:35:41 UTC
- Size: 32M
- Platform: Linux ARM64
- Build Type: Release
- Features: Fontconfig enabled
- Built by: GitHub Actions


## Flutter 3.44.0
- Flutter Commit: 559ffa3f75e7402d65a8def9c28389a9b2e6fe42
- Built on: 2026-05-18 20:23:37 UTC
- Size: 16M
- Platform: Linux ARM64
- Build Type: Release
- Features: Fontconfig enabled
- Built by: GitHub Actions


## Flutter 3.44.1
- Flutter Commit: 924134a44c189315be2148659913dda1671cbe99
- Built on: 2026-06-01 21:34:41 UTC
- Size: 16M
- Platform: Linux ARM64
- Build Type: Release
- Features: Fontconfig enabled
- Built by: GitHub Actions


## Flutter 3.44.2
- Flutter Commit: c9a6c484230f8b5e408ec57be1ef71dee1e77020
- Built on: 2026-06-12 02:34:34 UTC
- Size: 16M
- Platform: Linux ARM64
- Build Type: Release
- Features: Fontconfig enabled
- Built by: GitHub Actions


## Flutter 3.44.3
- Flutter Commit: e1fd963c6f6922bd32afde2e9698a363cd0406d2
- Built on: 2026-06-22 20:57:44 UTC
- Size: 16M
- Platform: Linux ARM64
- Build Type: Release
- Features: Fontconfig enabled
- Built by: GitHub Actions


## Flutter 3.44.4
- Flutter Commit: ad70ec4617166f1c38e5d2bfd388af71fda14f06
- Built on: 2026-06-25 02:54:11 UTC
- Size: 16M
- Platform: Linux ARM64
- Build Type: Release
- Features: Fontconfig enabled
- Built by: GitHub Actions


## Flutter 3.44.5
- Flutter Commit: f94f4fc76b4d74543ed9b085bbd75341ef65de22
- Built on: 2026-07-07 02:45:41 UTC
- Size: 16M
- Platform: Linux ARM64
- Build Type: Release
- Features: Fontconfig enabled
- Built by: GitHub Actions


## Flutter 3.44.6
- Flutter Commit: ee80f08bbf97172ec030b8751ceab557177a34a6
- Built on: 2026-07-09 20:24:31 UTC
- Size: 16M
- Platform: Linux ARM64
- Build Type: Release
- Features: Fontconfig enabled
- Built by: GitHub Actions


## Flutter 3.44.7
- Flutter Commit: 84fc5cbb223bc12f83d65b647ff8a56caf779ffd
- Built on: 2026-07-20 20:33:37 UTC
- Size: 16M
- Platform: Linux ARM64
- Build Type: Release
- Features: Fontconfig enabled
- Built by: GitHub Actions


## Flutter 3.38.2
- Flutter Commit: b5990e5ccc5e325fd24f0746e7d6689bbebc7c65
- Built on: 2026-07-23 10:35:05 UTC
- Size: 32M
- Platform: Linux ARM64
- Build Type: Release
- Features: Fontconfig enabled
- Built by: GitHub Actions

