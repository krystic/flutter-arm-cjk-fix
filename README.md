# Flutter ARM Linux Font Fixer

**针对在 Ubuntu（Snap 包）上运行且由 Flutter 引擎构建的应用在 ARM 架构上出现中文显示为方框（豆腐块）的问题的系统级修复工具。**

> 说明：本脚本的**主要适用场景**为在 Ubuntu ARM 系统上以 Snap 方式分发、并由 Flutter 引擎构建的应用；并非针对所有 Flutter 应用或所有发行版通用，但其中的实现方法可为类似问题提供借鉴。 / Note: This tool is primarily targeted at Flutter-built apps packaged as Snap on Ubuntu ARM systems; it is not a universal fix for all Flutter apps or distributions, but may offer guidance for similar issues.



### 📝 背景与原理

在 ARM 架构（如树莓派、飞腾、RK3588 或 Parallels 虚拟机）运行 Ubuntu 时，许多**由 Flutter 引擎构建并通过 Snap 分发**的应用（如 `desktop-security-center`）会出现中文乱码。

**根本原因：**
1. **沙盒隔离**：Snap 包内的 `libfontconfig` 无法正确读取宿主系统的 `/etc/fonts` 配置。
2. **Engine 缺陷**：Flutter Engine 在 ARM 构建版本中，若 Fontconfig 初始化失败，不会向系统请求备用字体。
3. **字重陷阱**：Flutter 渲染不同字号时会请求特定字重（如 Light/Bold），如果只映射标准体，小号字和标题依然会乱码。

### ✨ 特性

* 🚀 **全自动修复**：一键检测并修复指定应用的中文显示。
* 📦 **多字重支持**：完整映射 Regular, Bold, Light, Medium 等 8 种字重。
* 🔄 **开机自启**：自动集成 Systemd 系统级服务，重启后后台静默恢复映射。
* 🛠️ **智能管理**：支持自动安装字体依赖、持久化配置管理、一键全量卸载。

### 适用范围 / Scope

* 主要目标：**在 Ubuntu ARM 平台上运行、由 Flutter 引擎构建并以 Snap 分发的应用**。
* 非主要目标：非 Snap 分发、非 Ubuntu 平台或非 Flutter 引擎构建的应用可能不受支持。
* 参考价值：即便不在适用范围内，该脚本中的排查与修复思路（例如通过 bind-mount 替换字体、systemd 启动时恢复映射）可供移植和参考。 / Note: While this tool focuses on Ubuntu ARM + Snap Flutter apps, its methods may help diagnose or mitigate similar problems elsewhere.

### 🚀 快速开始

> 说明：本示例假设你在 Ubuntu ARM 系统上，问题应用为通过 Snap 分发并由 Flutter 引擎构建的程序。 / Note: The examples below assume an Ubuntu ARM environment and a Flutter-built app distributed as a Snap package.

### 1. 安装脚本
下载脚本并赋予执行权限：
```bash
sudo wget https://github.com/krystic/flutter-arm-cjk-fix/raw/main/flutter-font-fix.sh -O /usr/local/bin/flutter-font-fix.sh
sudo chmod +x /usr/local/bin/flutter-font-fix.sh
```

### 2. 命令参考

| 命令 | 描述 / Description |
| :--- | :--- |
| `sudo flutter-font-fix.sh -a <app_name>` | **修复并开启自启**：注入字体并将应用加入自启列表 / Repair an app and enable persistence (add to startup list) |
| `sudo flutter-font-fix.sh -u -a <app_name>` | **取消修复**：解除该应用的映射并从列表中移除 / Unrepair an app and remove from startup list |
| `sudo flutter-font-fix.sh --unmount-all` | **全量释放**：临时释放所有挂载点（保留配置记录） / Unmount all mappings (keeps config) |
| `sudo flutter-font-fix.sh --remove-service` | **彻底卸载**：清理所有映射、删除配置并注销自启服务 / Remove manager, clear mappings and disable service |
| `sudo flutter-font-fix.sh -i` or `sudo flutter-font-fix.sh --init` | **安装 Shell 补全**：为 `-a/--app` 启用 Tab 补全（snap 已安装的应用名）/ Install shell completion (Tab completion for `-a/--app`, completes `snap list` apps) |

#### 补充说明 / Notes
- 补全安装会在 `/etc/bash_completion.d/flutter-font-fix` 生成补全脚本；若以 `sudo` 运行，会提示是否将 `source /etc/bash_completion.d/flutter-font-fix` 追加到原始调用者的 `~/.bashrc`（交互式时询问并做幂等追加）。
- 补全在非交互环境下不会提示，只会输出如何手动安装的指令。
- 所有用户可见信息为中英双语，并带有统一前缀（如 `[INFO]`、`[OK]`、`[ERROR]`）以便脚本化处理和日志分析。

### 📂 文件结构说明

* `/usr/local/bin/flutter-font-fix.sh`：主执行脚本。
* `/etc/flutter_font_fixed_apps.conf`：已修复应用的持久化列表。
* `/etc/systemd/system/flutter-font-fix.service`：系统级 Systemd 服务单元。

### 🔍 技术实现



该脚本通过 Systemd 的 `After=snapd.service` 确保在 Snap 挂载点就绪后执行。它利用 `find -L` 动态探测应用内部的资产路径。由于使用了 `mount --bind`，这是一种内存级的“外科手术”修复，不会修改磁盘上的原始镜像文件。

### 📄 开源协议
[MIT License](LICENSE)
