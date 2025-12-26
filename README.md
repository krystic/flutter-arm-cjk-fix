# Flutter ARM CJK Font Fix

[![缩略图](images/snap-store-screenshot-thumb.png)](images/snap-store-screenshot.png)

**Ubuntu ARM 平台下 Flutter 应用 CJK 字体显示修复工具**

针对在 Ubuntu ARM 架构上运行的 Flutter 应用（Snap 和非 Snap）出现 CJK（中日韩）字符显示为方框（豆腐块）的问题，提供系统级自动修复方案。

> **适用范围**：支持 Snap 应用（如 snap-store）和非 Snap 应用（如 rustdesk、AppImage、deb 包等）。通过 Engine Hash 自动检测 Flutter 版本，智能匹配和替换 SO 文件。
>
> **Scope**: Supports both Snap apps (snap-store) and non-Snap apps (rustdesk, AppImage, deb packages, etc.). Auto-detects Flutter version via Engine Hash for intelligent SO file matching.

---

## 📝 背景与原理

### 问题现象
在 ARM 架构（树莓派、飞腾、RK3588、Parallels 虚拟机等）运行 Ubuntu 时，许多由 Flutter 引擎构建的应用会出现 CJK 字符显示为方框。

### 根本原因（已验证）

**问题已彻底定位**：通过自编译 Flutter Engine 并对比官方版本，确认核心原因是官方 ARM64 版本 `libflutter_linux_gtk.so` **未链接 Fontconfig 库**。

#### 技术层面
Flutter 文本渲染链：`Flutter App → libflutter_linux_gtk.so → Skia → FontConfig`

**验证方法**：
```bash
# 官方 ARM64 版本（缺陷）
readelf -d libflutter_linux_gtk.so | grep fontconfig
# (无输出)

# 自编译修复版本
readelf -d libflutter_linux_gtk.so | grep fontconfig
# 0x0000000000000001 (NEEDED)  共享库：[libfontconfig.so.1]
```

#### 构建配置缺陷
- **x64 平台**（正常）：使用 `linux_host_desktop_engine.json` 配置，包含 `--enable-fontconfig` 参数
- **ARM64 平台**（缺陷）：使用 `linux_arm_host_engine.json` 配置，**缺少** `--enable-fontconfig` 参数
- **架构失误**：官方将桌面目标和嵌入式目标混在同一个配置中，导致桌面版继承了嵌入式的"精简"配置

#### 后果
- Fontconfig 未启用 → Flutter Engine 无法发现系统字体
- 字体回退机制失效 → CJK 字符找不到可用字体
- 最终表现 → 显示为方框（□□□）

**详细技术分析见**：[FONTCONFIG_BUG_INVESTIGATION.md](FONTCONFIG_BUG_INVESTIGATION.md)

### 解决方案

本项目由 **Krystic** 使用 **VS Code + GitHub Copilot + Claude Sonnet 4.5** 协同开发，最终根本原因的定位得益于自编译对比验证。

#### 根治方案（推荐）
通过自编译启用 Fontconfig 支持的 Flutter Engine SO 文件（`libflutter_linux_gtk.so`），使用 `mount --bind` 替换应用内的官方 SO，从根本上解决字体渲染问题。

- ✅ 完全修复 Fontconfig 支持
- ✅ 支持所有语言字符（不限于 CJK）
- ✅ 自动版本检测和智能匹配
- ✅ 版本缓存机制（提升启动速度）
- ✅ Systemd 开机自启

**编译说明**：[FONTCONFIG_BUG_INVESTIGATION.md](FONTCONFIG_BUG_INVESTIGATION.md)

#### 兜底方案
如果没有匹配的 SO 文件，自动回退到字体映射方案：通过 `mount --bind` 将 Noto Sans CJK 字体动态挂载到 Snap 应用内的 Ubuntu 字体路径。

- ⚠️ 仅修复 CJK 字符显示
- ⚠️ 其他语言符号可能仍显示为方框

---

## ✨ 特性

### 核心功能
* 🎯 **双应用类型支持**
  - **Snap 应用**（`-a` 模式）：自动检测 Flutter 版本，使用精确匹配的 SO 文件，无匹配时回退到字体映射
  - **非 Snap 应用**（`-e` 模式）：支持直接指定可执行文件路径，智能提取 SO 信息，支持相似版本选择
* 🔍 **版本智能检测**
  - **Hash 精确匹配**：通过 SO 文件中的 Engine Hash 精确识别 Flutter 版本
  - **版本缓存机制**：缓存 Flutter 版本对照表（7天），避免重复网络请求
  - **双源查找**：同时查找本地库和 GitHub 仓库，本地精确版本时自动跳过线上查询
* 📦 **自动下载**：在线 SO 文件自动下载到本地（带进度条），支持 CDN 加速
* 🔄 **开机自启**：自动创建 Systemd 服务，系统重启后静默恢复所有映射
* 🛠️ **智能管理**
  - 自动安装字体依赖（`fonts-noto-cjk`）
  - 冲突检测（SO 替换与字体映射模式智能切换）
  - 配置持久化（`/etc/flutter-cjk/`）
  - Tab 自动补全（Snap 应用名称 + 文件路径）

### 用户体验
* 📋 **列表查看**：显示已映射应用的简要或详细信息
* 🌐 **双语输出**：所有信息提供中英文对照
* 🎨 **格式规范**：统一的 `[INFO]` / `[OK]` / `[ERROR]` / `[WARN]` 标签
* ⚡ **即时生效**：无需重启应用，映射立即应用

---

## 🚀 快速开始

### 安装

#### 方式 1：一键安装（推荐）
```bash
curl -fsSL https://raw.githubusercontent.com/krystic/flutter-arm-cjk-fix/main/install.sh | sudo bash
```

**功能**：
- ✅ 自动检测 ARM64 Linux 架构（非 ARM64 会提示并退出）
- ✅ 安装主脚本到 `/usr/local/bin/flutter-font-fix`
- ✅ 安装必要依赖（`bash-completion`, `fonts-noto-cjk`）
- ✅ 初始化配置目录（`/etc/flutter-cjk/`）
- ✅ 注册并启用 systemd 服务
- ✅ 安装 Bash 自动补全

#### 方式 2：手动安装
```bash
# 下载脚本
sudo wget https://github.com/krystic/flutter-arm-cjk-fix/raw/main/flutter-font-fix \
  -O /usr/local/bin/flutter-font-fix

# 赋予执行权限
sudo chmod +x /usr/local/bin/flutter-font-fix

# 首次运行初始化（创建配置文件）
sudo flutter-font-fix -l

# 安装 Tab 补全（可选）
sudo flutter-font-fix -i

# 安装 systemd 服务（可选）
sudo flutter-font-fix --install-service
```

### 基本用法

#### 1. 修复 Snap 应用
使用精确版本的 SO 文件替换，无匹配时回退到字体映射：
```bash
sudo flutter-font-fix -a snap-store

# 输出示例：
# [OK] [snap-store] Flutter Engine replaced with libflutter_linux_gtk.so.3.38.1
#      Flutter 引擎已替换，字体问题已根治。
```

#### 2. 修复非 Snap 应用
支持精确版本和相似版本选择（如 3.24.3 用于 3.24.5）：
```bash
sudo flutter-font-fix -e rustdesk
# 或
sudo flutter-font-fix -e /usr/bin/rustdesk

# 相似版本选择示例：
# [WARN] No exact version found for 3.24.5
# [INFO] Found compatible versions:
#   [1] 3.24.3 [本地/local]
#   [2] 3.24.1 [线上/online]
# 尝试这些版本之一吗？[1]: 
```

**工作原理**：
- 从 SO 文件提取 40 位 Engine Hash
- 查询 Flutter GitHub 匹配版本（7 天缓存）
- 本地精确版本时自动跳过线上查询
- 支持 CDN 加速：`--cdn https://raw.staticdn.net/`

#### 3. 自定义字体修复
交互式选择应用内的字体文件并映射：
```bash
sudo flutter-font-fix -c snap-store

# 脚本会：
# 1. 搜索应用内所有字体文件
# 2. 显示编号列表供选择（支持逗号分隔多选，'a' 全选）
# 3. 为每个字体选择目标 Noto 字重（Regular/Bold/Light/Medium）
# 4. 保存配置并立即应用
```

#### 4. 查看和管理
```bash
# 简要列表
flutter-font-fix -l

# 详细信息
flutter-font-fix -d

# 移除映射
sudo flutter-font-fix -r <app_name>

# 移除全部
sudo flutter-font-fix --remove-all
```

---

## 📖 命令参考

### 主要命令

| 命令 | 功能说明 |
|------|---------|
| `sudo flutter-font-fix -e <exe>` | 修复非 Snap 应用（支持精确+相似版本）<br>Repair non-Snap apps (exact + similar versions) |
| `sudo flutter-font-fix -a <app>` | 修复 Snap 应用（仅精确版本，回退字体映射）<br>Repair Snap apps (exact version only, fallback to font mapping) |
| `sudo flutter-font-fix -c <app>` | 自定义字体修复 Snap 应用<br>Repair Snap apps with custom fonts |
| `sudo flutter-font-fix -r <app>` | 移除/卸载映射（包括 SO 和字体）<br>Remove/unmount mappings (SO and fonts) |
| `flutter-font-fix -l \| --list` | 列出已映射应用<br>List mapped apps |
| `flutter-font-fix -d \| --detail` | 详细映射信息<br>Detail mappings |
| `sudo flutter-font-fix --remove-all` | 移除全部<br>Remove all |
| `sudo flutter-font-fix --uninstall-service` | 卸载系统服务<br>Uninstall systemd service |
| `sudo flutter-font-fix --uninstall` | 完全卸载<br>Uninstall completely |
| `sudo flutter-font-fix -i \| --install-completion` | 安装补全<br>Install completion |

### 全局参数

| 参数 | 功能说明 |
|------|---------|
| `--cdn <prefix>` | 覆盖 GitHub Raw CDN 前缀（含末尾斜杠）<br>Override GitHub Raw CDN prefix (with trailing slash) |

### 高级选项

**CDN 加速**
```bash
# 使用 CDN 镜像
sudo flutter-font-fix --cdn https://raw.staticdn.net/ -a snap-store
sudo flutter-font-fix --cdn https://ghproxy.com/https://raw.githubusercontent.com/ -e rustdesk
```

**完全卸载**
```bash
sudo flutter-font-fix --uninstall
```

### 使用示例

**修复 Snap Store**
```bash
sudo flutter-font-fix -a snap-store
```

**修复 rustdesk**
```bash
sudo flutter-font-fix -e rustdesk
```

**查看状态**
```bash
flutter-font-fix -d
# 输出：
# - snap-store [so/SO替换]
#     • Flutter Engine: libflutter_linux_gtk.so.3.38.1
# - rustdesk [so/SO替换]
#     • Flutter Engine: libflutter_linux_gtk.so.3.24.3
```

---

## 📂 文件结构

```
/etc/flutter-cjk/                      # 配置目录
├── ubuntu.conf                        # 官方模式应用列表（格式：app|so 或 app|font）
├── flutter.engine.hash.version        # Flutter Engine Hash→版本对照表缓存（7天）
└── <app_name>.conf                    # 自定义模式配置文件

/usr/local/lib/flutter-cjk/            # SO 文件本地缓存
└── libflutter_linux_gtk.so.X.Y.Z      # 下载的 SO 文件

/etc/systemd/system/
└── flutter-font-fix.service           # 系统启动服务

/etc/bash_completion.d/
└── flutter-font-fix                   # Tab 补全脚本

/usr/local/bin/
└── flutter-font-fix                   # 主执行脚本

<repository>/lib/                      # GitHub 仓库 SO 文件库
└── libflutter_linux_gtk.so.X.Y.Z      # 预编译的 SO 文件（30-40MB）
```

### 配置文件说明

**ubuntu.conf** - 应用配置列表（新格式）
```
snap-store|so              # SO 引擎替换
desktop-security-center|font   # 字体映射
rustdesk|so                # 非 Snap 应用也记录在此
old-app                    # 旧格式（兼容）
```

**flutter.engine.hash.version** - Flutter Engine Hash→版本缓存
```bash
# 格式: hash | version
2c9bc1e4b1... | 3.38.1
a7f8e9d2c3... | 3.24.3
```
> 缓存有效期 7 天，避免重复查询 Flutter GitHub 仓库

**\<app\>.conf** - 自定义模式配置示例
```bash
# Flutter Font Fix - Custom Font Configuration
# App: snap-store
# Generated: 2025-12-20 10:30:45

/snap/snap-store/current/fonts/Ubuntu-R.ttf|/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc
/snap/snap-store/current/fonts/Ubuntu-B.ttf|/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc
```

---

## 🔍 技术细节

### 实现原理
1. **Hash 精确检测**：从 SO 文件提取 Flutter Engine Hash（40 位），查询 Flutter GitHub 建立版本对照表（7 天缓存）
2. **双源查找**：本地优先，精确版本时跳过线上查询，自动下载在线版本（30-40MB，进度条）
3. **智能替换**：
   - Snap 应用：`mount --bind` 替换（仅精确版本）
   - 非 Snap 应用：直接替换系统 SO（支持相似版本，自动备份 `.bak`）
4. **字体映射兜底**：无匹配 SO 时自动回退到 Noto CJK 字体映射
5. **开机自启**：Systemd 服务 `After=snapd.service` 确保 Snap 就绪后执行

### 检测流程示例
```bash
# 1. 提取 Hash
strings libflutter_linux_gtk.so | grep -E '^[0-9a-f]{40}$'
# → 2c9bc1e4b1a7f8e9d2c3456789abcdef01234567

# 2. 匹配版本（查询 Flutter GitHub，7天缓存）
# → 3.38.1

# 3. 查找/下载 SO
# 本地: /usr/local/lib/flutter-cjk/libflutter_linux_gtk.so.3.38.1
# 线上: https://raw.githubusercontent.com/.../libflutter_linux_gtk.so.3.38.1
```

### 字重映射关系

字体映射方案（兜底）：
```
Ubuntu-R.ttf/RI  → NotoSansCJK-Regular.ttc
Ubuntu-L.ttf/LI  → NotoSansCJK-Light.ttc
Ubuntu-M.ttf/MI  → NotoSansCJK-Medium.ttc
Ubuntu-B.ttf/BI  → NotoSansCJK-Bold.ttc
```

自定义模式（`-c`）可自由选择映射关系。

### Systemd 服务配置
```ini
[Unit]
Description=Flutter Font Auto-Mount Service (System Level)
After=snapd.service
Requires=snapd.service
ConditionPathExists=/etc/flutter-cjk

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 3
ExecStart=/usr/local/bin/flutter-font-fix --startup
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

---

## 🤔 常见问题

**Q: -a 模式和 -e 模式有什么区别？**
- **-a 模式**：针对 Snap 应用，仅使用精确版本的 SO 文件，未找到时回退到字体映射
- **-e 模式**：针对非 Snap 应用（如 rustdesk），支持精确版本和相似版本选择（如 3.24.3 用于 3.24.5）

**Q: 什么是相似版本？**
- 相似版本指主版本号相同的 Flutter 版本（如 3.24.1、3.24.3、3.24.5 都属于 3.24.x）
- 在 `-e` 模式下，如果找不到精确版本，会提示选择相似版本
- Snap 应用（`-a` 模式）不使用相似版本，保证稳定性

**Q: 如何恢复原始 SO 文件？**
```bash
# 非 Snap 应用（-e 模式）会自动备份
sudo cp /path/to/libflutter_linux_gtk.so.bak /path/to/libflutter_linux_gtk.so

# Snap 应用（-a 模式）使用 mount，直接卸载即可
sudo flutter-font-fix -r snap-store
```

**Q: 修复后需要重启应用吗？**
- 通常不需要。映射立即生效，但部分应用可能需要重启以重新加载字体缓存

**Q: 会影响系统其他应用吗？**
- 不会。Snap 应用的 SO 替换仅作用于该应用内部
- 非 Snap 应用会修改系统目录中的 SO，但会自动备份原文件

**Q: 如何验证修复是否成功？**
```bash
# 检查挂载状态（Snap 应用）
mount | grep flutter

# 查看配置
flutter-font-fix -d

# 检查 SO 文件（非 Snap 应用）
ldd /usr/bin/rustdesk | grep libflutter_linux_gtk.so
ls -la /path/to/libflutter_linux_gtk.so*

# 重启应用并观察中文显示
```

**Q: 缓存文件在哪里？**
```bash
# Hash→版本对照表缓存（7天有效期）
/etc/flutter-cjk/flutter.engine.hash.version

# 下载的 SO 文件缓存
/usr/local/lib/flutter-cjk/libflutter_linux_gtk.so.*
```

---

## 🛠️ 故障排查

### 问题：修复后仍显示方框
1. 检查 Noto 字体是否已安装：
   ```bash
   dpkg -l | grep fonts-noto-cjk
   ```
2. 验证挂载点是否生效：
   ```bash
   mount | grep <app_name>
   ```
3. 尝试重启应用或重新映射

### 问题：开机后映射失效
1. 检查服务状态：
   ```bash
   sudo systemctl status flutter-font-fix.service
   ```
2. 查看服务日志：
   ```bash
   sudo journalctl -u flutter-font-fix.service
   ```
3. 手动触发服务：
   ```bash
   sudo systemctl start flutter-font-fix.service
   ```

### 问题：Tab 补全不生效
1. 重新加载补全脚本：
   ```bash
   source /etc/bash_completion.d/flutter-font-fix
   ```
2. 或重新安装：
   ```bash
   sudo flutter-font-fix -i
   ```

---

## 📄 开源协议

[MIT License](LICENSE)

---

## 🙏 致谢

本项目的核心问题研究和解决方案由 **Gemini 3** 深度分析提供，代码实现使用 **VS Code + GitHub Copilot + Claude Sonnet 4.5** 协同完成。

感谢社区中关于 Snap 字体问题的讨论和相关技术资料。

---

## 📮 反馈与贡献

欢迎通过 [Issues](https://github.com/krystic/flutter-arm-cjk-fix/issues) 报告问题或提出建议。
