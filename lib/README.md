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

