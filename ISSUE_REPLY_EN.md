This is a unified response template for Flutter official CJK-related issues, upgraded to prioritize "SO root cause fix" with font mapping as a fallback solution. Ready to copy and use:

-----------------------------------------------------------------------------

**TL;DR**: The root cause of CJK characters displaying as squares (□□□) in Flutter apps on ARM64 Linux has been identified: the official ARM64 `libflutter_linux_gtk.so` does not have `fontconfig` enabled, preventing proper fallback to system fonts. We provide a universal solution by "replacing with fixed Engine SO", with "font mapping" as a temporary backup.

Project repository: 👉 **https://github.com/krystic/flutter-arm-cjk-fix**

**Root Cause & Solutions**
- Root cause: Official ARM64 Flutter Engine is not linked with `fontconfig` (especially when running in Snap sandbox), causing CJK fallback failure.
- Solution 1 (Recommended, universal root fix): Replace with our compiled `libflutter_linux_gtk.so` with `fontconfig` enabled.
- Solution 2 (Fallback, temporary fix): Use `mount --bind` to map system Noto Sans CJK fonts to the app's font directory.

**Available Versions (Linux ARM64)**
- Currently available: `3.24.3`, `3.32.7`, `3.35.3`, `3.38.1` (all with `fontconfig` enabled)
- Building automatically: `3.38.5` (Actions will trigger build and release upon detecting new tags)

**Quick Start**
1) One-command installation (recommended, auto-detects ARM64 architecture and completes setup):
	```bash
	curl -fsSL https://raw.githubusercontent.com/krystic/flutter-arm-cjk-fix/main/install.sh | sudo bash
	```

2) Fix an app (tries "SO root fix" first, auto-fallback to font mapping):
	```bash
	sudo flutter-font-fix -a <your_app_name>
	# Example: sudo flutter-font-fix -a snap-store
	```

3) View fix method and status (will show SO / font / unknown):
	```bash
	sudo flutter-font-fix -d
	```

**Or manually clone repository for installation**:
```bash
git clone https://github.com/krystic/flutter-arm-cjk-fix.git
cd flutter-arm-cjk-fix
sudo ./flutter-font-fix -a <your_app_name>
```

**Compatibility & Security**
- Does not modify Snap read-only images; SO replacement uses system-level mounting, maintained by systemd after boot.
- If official fix is released later, this tool can be uninstalled with one command to restore original state.

**Conclusion**
This is not a font-missing issue for individual apps, but a systemic problem where Flutter Engine (official build) on ARM64 platform does not have `fontconfig` enabled. By replacing with an Engine SO that has `fontconfig` enabled, we can fix all affected Flutter desktop apps at the root cause level; when SO is temporarily unavailable, font mapping provides a reliable temporary alternative.

Testing and feedback are welcome. We will continue to track and maintain the latest versions.
