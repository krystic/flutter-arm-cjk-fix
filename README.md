# Flutter ARM CJK Font Fix

[![缩略图](images/snap-store-screenshot-thumb.png)](images/snap-store-screenshot.png)

**Ubuntu ARM 平台下 Flutter Snap 应用 CJK 字体显示修复工具**

针对在 Ubuntu ARM 架构上运行的 Flutter Snap 应用出现 CJK（中日韩）字符显示为方框（豆腐块）的问题，提供系统级自动修复方案。

> **适用范围**：本工具主要针对 Ubuntu ARM 系统上以 Snap 方式分发的 Flutter 应用。虽非通用方案，但其实现思路可为类似问题提供参考。
>
> **Scope**: Primarily targets Flutter apps packaged as Snap on Ubuntu ARM systems. While not universal, the approach may help similar issues.

---

## 📝 背景与原理

### 问题现象
在 ARM 架构（树莓派、飞腾、RK3588、Parallels 虚拟机等）运行 Ubuntu 时，许多由 Flutter 引擎构建并通过 Snap 分发的应用（如 `snap-store`、`desktop-security-center`）会出现 CJK 字符显示为方框。

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
* 🎯 **智能双模式修复**
  - **根治模式**：自动检测 Flutter 版本，使用启用 Fontconfig 的自编译 SO 文件替换官方引擎
  - **兜底模式**：如无匹配 SO 文件，自动回退到 Noto CJK 字体映射方案
* 🔍 **版本智能检测**
  - 自动从 Snap 包元数据和 GitHub 源码仓库检测 Flutter 版本
  - 支持版本缓存机制，避免重复网络请求（启动速度提升 54%）
* 📦 **多字重支持**：完整映射 Regular, Bold, Light, Medium 等 8 种字重（含斜体）
* 🔄 **开机自启**：自动创建 Systemd 服务，系统重启后静默恢复所有映射
* 🛠️ **智能管理**
  - 自动安装字体依赖（`fonts-noto-cjk`）
  - 冲突检测（SO 替换与字体映射模式智能切换）
  - 配置持久化（`/etc/flutter-cjk/`）
  - Tab 自动补全（应用名称）

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

#### 1. 官方模式修复（推荐）
自动检测应用版本和 Flutter 版本，优先使用 Flutter Engine SO 替换，否则回退到字体映射：
```bash
# 修复单个应用
sudo flutter-font-fix -a snap-store

# 自动检测流程：
# 1. 从 snapcraft.io 获取 GitHub 仓库地址
# 2. 从 snap info 获取当前 commit ID
# 3. 从 GitHub .fvmrc 文件获取 Flutter 版本
# 4. 检查 lib/ 目录是否有对应版本的 SO 文件

# 如果找到匹配的 SO 文件：
# [OK] [snap-store] Root cause fixed with Flutter Engine replacement!
#      根本问题已通过 Flutter 引擎替换解决！

# 如果没有 SO 文件，自动回退到字体映射：
# [OK] [snap-store] Font mapping applied (workaround).
#      字体映射已应用（临时方案）。

# 修复后自动加入开机启动列表
# 支持 Tab 补全应用名（需先运行 -i 安装补全）
```

**智能版本检测**：
- 优先从 `github-repos.conf` 对照表查找准确的仓库地址
- 对照表没有时自动从 snapcraft.io 获取
- 自动从应用源码获取准确的 Flutter 版本
- 支持所有开源的 Ubuntu Flutter Snap 应用

**添加新应用到对照表**：
```bash
# 编辑配置文件
sudo nano /etc/flutter-cjk/github-repos.conf

# 添加一行（格式：应用名|GitHub地址）
app-name|https://github.com/owner/repo
```

#### 2. 自定义字体修复
交互式选择应用内的字体文件并映射：
```bash
sudo flutter-font-fix -c snap-store

# 脚本会：
# 1. 搜索应用内所有字体文件
# 2. 显示编号列表供选择（支持逗号分隔多选，'a' 全选）
# 3. 为每个字体选择目标 Noto 字重（Regular/Bold/Light/Medium）
# 4. 保存配置并立即应用
```

#### 3. 查看已映射应用
```bash
# 简要列表
flutter-font-fix -l

# 详细信息（显示模式和映射关系）
flutter-font-fix -d
```

#### 4. 移除映射
```bash
# 移除单个应用（官方+自定义）
sudo flutter-font-fix -r snap-store

# 临时移除所有（保留配置）
sudo flutter-font-fix --remove-all

# 完全移除（清理配置和服务）
sudo flutter-font-fix --uninstall-service
```

---

## 📖 命令参考

### 主要命令

| 命令 | 功能说明 |
|------|---------|
| `sudo flutter-font-fix -a <app>` | 修复 Ubuntu 官方应用（优先 SO 替换，回退字体映射）<br>Repair official Ubuntu apps (SO replacement first, fallback to font mapping) |
| `sudo flutter-font-fix -c <app>` | 自定义字体修复<br>Repair with custom fonts |
| `sudo flutter-font-fix -r <app>` | 移除/卸载映射（包括 SO 和字体）<br>Remove/unmount mappings (SO and fonts) |
| `flutter-font-fix -l \| --list` | 列出已映射应用<br>List mapped apps |
| `flutter-font-fix -d \| --detail` | 详细映射信息<br>Detail mappings |
| `sudo flutter-font-fix --remove-all` | 移除全部<br>Remove all |
| `sudo flutter-font-fix --uninstall-service` | 卸载系统服务<br>Uninstall systemd service |
| `sudo flutter-font-fix -i \| --install-completion` | 安装补全<br>Install completion |

### 使用示例

**场景 1：修复 Snap Store**
```bash
# 官方模式（一键修复）
sudo flutter-font-fix -a snap-store

# 自定义模式（精细控制）
sudo flutter-font-fix -c snap-store
# 按提示选择要映射的字体文件和目标字重
```

**场景 2：批量查看状态**
```bash
# 查看哪些应用已修复
flutter-font-fix -l

# 输出示例：
# [INFO] Apps with mappings:
#        已有映射的应用：
#   - snap-store
#   - desktop-security-center
```

**场景 3：查看详细配置**
```bash
flutter-font-fix -d

# 输出示例：
# [INFO] Detailed mappings:
#        详细映射列表：
# - snap-store [custom/自定义]
#     • Ubuntu-R.ttf  <=  NotoSansCJK-Regular.ttc
#     • Ubuntu-B.ttf  <=  NotoSansCJK-Bold.ttc
# - desktop-security-center [ubuntu/官方]
```

**场景 4：切换模式**
```bash
# 从官方模式切换到自定义模式
sudo flutter-font-fix -c snap-store
# 脚本会检测到冲突并提示是否移除官方配置

# 从自定义模式切换到官方模式
sudo flutter-font-fix -a snap-store
# 脚本会检测到冲突并提示是否移除自定义配置
```

---

## 📂 文件结构

```
/etc/flutter-cjk/                      # 配置目录
├── ubuntu.conf                        # 官方模式应用列表
├── github-repos.conf                  # GitHub 仓库地址对照表
└── <app_name>.conf                    # 自定义模式配置文件

/etc/systemd/system/
└── flutter-font-fix.service           # 系统启动服务

/etc/bash_completion.d/
└── flutter-font-fix                   # Tab 补全脚本

/usr/local/bin/
└── flutter-font-fix                   # 主执行脚本

<repository>/lib/                      # Flutter Engine SO 文件库
└── libflutter_linux_gtk.so.X.Y.Z      # 自编译的 SO 文件
```

### 配置文件说明

**ubuntu.conf** - 官方模式应用列表
```
snap-store
desktop-security-center
```

**github-repos.conf** - GitHub 仓库地址对照表
```bash
# Format: snap_app_name|github_repo_url
snap-store|https://github.com/ubuntu/app-center
desktop-security-center|https://github.com/canonical/desktop-security-center
```
> 脚本优先从此对照表查找 GitHub 仓库地址，如果找不到则尝试从 snapcraft.io 自动获取

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
1. **智能版本检测**：
   - 优先从 `github-repos.conf` 对照表查找 GitHub 仓库地址
   - 如果对照表没有，尝试从 snapcraft.io 自动获取
   - 从 snap info 提取当前安装的 commit ID
   - 从 GitHub 对应 commit 的 `.fvmrc` 文件读取 Flutter 版本
   - 最小化手动维护，大部分应用可自动检测

2. **SO 文件替换**：通过 `mount --bind` 替换 `libflutter_linux_gtk.so`，从根本修复 Fontconfig 支持
3. **字体映射兜底**：如果没有匹配的 SO 文件，自动回退到 Noto CJK 字体映射
4. **动态探测**：使用 `find -L` 自动发现 Snap 应用内的字体和 SO 路径
5. **内存挂载**：通过 `mount --bind` 实现替换（不修改原始文件）
6. **多字重映射**：支持 8 种字重（R/RI/L/LI/M/MI/B/BI → Regular/Light/Medium/Bold）
7. **服务集成**：Systemd 服务 `After=snapd.service` 确保 Snap 挂载点就绪后执行
8. **配置持久化**：所有配置保存在 `/etc/flutter-cjk/`，支持系统重启后恢复

### 版本检测示例
```bash
# snap-store 为例：
# 1. 查找 GitHub 仓库（优先从对照表）
#    github-repos.conf: snap-store|https://github.com/ubuntu/app-center
#    → 获取: https://github.com/ubuntu/app-center
# 
# 2. snap info snap-store | grep installed:
#    → 获取: 0+git.1b6e6f1d (1313)
#    → 提取 commit: 1b6e6f1d
#
# 3. curl https://github.com/ubuntu/app-center/raw/1b6e6f1d/.fvmrc
#    → 获取: {"flutter": "3.38.1"}
#    → 提取版本: 3.38.1
#
# 4. 检查: lib/libflutter_linux_gtk.so.3.38.1 是否存在
```

### 字重映射关系

**官方模式**（预设方案）
```
Ubuntu-R.ttf  / Ubuntu-RI.ttf  → NotoSansCJK-Regular.ttc
Ubuntu-L.ttf  / Ubuntu-LI.ttf  → NotoSansCJK-Light.ttc
Ubuntu-M.ttf  / Ubuntu-MI.ttf  → NotoSansCJK-Medium.ttc
Ubuntu-B.ttf  / Ubuntu-BI.ttf  → NotoSansCJK-Bold.ttc
```

**自定义模式**（用户选择）
- 可映射应用内任意 .ttf/.ttc 字体
- 可自由选择目标 Noto 字重（Regular/Bold/Light/Medium）

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

**Q: 官方模式和自定义模式有什么区别？**
- **官方模式**：使用预设的 Ubuntu 字体 → Noto CJK 映射方案，适合大多数场景
- **自定义模式**：可精确控制每个字体文件的映射关系，适合特殊需求或非标准字体

**Q: 可以同时使用两种模式吗？**
- 不能。脚本会检测冲突并提示选择保留哪种模式

**Q: 修复后需要重启应用吗？**
- 通常不需要。映射立即生效，但部分应用可能需要重启以重新加载字体缓存

**Q: 会影响系统其他应用吗？**
- 不会。映射仅作用于指定的 Snap 应用内部，不影响系统全局字体

**Q: 如何验证修复是否成功？**
```bash
# 检查挂载状态
mount | grep flutter

# 查看配置
flutter-font-fix -d

# 重启应用并观察中文显示
```

**Q: 卸载后如何恢复？**
```bash
# 官方模式
sudo flutter-font-fix -a <app_name>

# 自定义模式
sudo flutter-font-fix -c <app_name>
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
