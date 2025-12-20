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

### 根本原因

经过与 Gemini 3 深入研究分析，推测问题的原因：

1. **Flutter Engine 编译问题**：Flutter 在 ARM Linux 平台编译时，将其统一当作嵌入式系统对待，未启用 Fontconfig 支持
   - ARM 版本的编译配置（.gn 文件）中缺少 `--enable-fontconfig` 参数
   - AMD64 版本有专门针对桌面环境的 .gn 编译文件，包含了 Fontconfig 支持
   - 导致 ARM 版本的 Flutter Engine 根本不会调用 `libfontconfig` 库

2. **Snap 沙盒限制**：即使启用了 Fontconfig，Snap 包内的 `libfontconfig` 也无法正确读取宿主系统的 `/etc/fonts` 配置

3. **字体回退机制缺失**：由于未启用 Fontconfig，Flutter Engine 在 ARM 平台上无法获取系统字体列表，导致 CJK 字符无可用字体

### 解决方案

本解决方案由 **Gemini 3** 深度研究并提供核心思路，通过 **VS Code + GitHub Copilot + Claude Sonnet 4.5** 协同编写实现。
通过 `mount --bind` 将 Noto Sans CJK 字体动态挂载到 Snap 应用内的 Ubuntu 字体路径，支持完整字重映射，并通过 Systemd 服务实现开机自动恢复。

此方案仍不完美，CJK 字体不包含的其他语言符号仍然会显示成方框或其他乱码，如需彻底解决只能找到 Flutter 准确的 BUG 原因，由 Flutter 和应用官方一起修复

---

## ✨ 特性

### 核心功能
* 🎯 **双模式修复**
  - **官方模式**：使用预设的 Ubuntu → Noto CJK 字体映射方案
  - **自定义模式**：交互式选择应用内任意字体并映射到指定 Noto 字重
* 📦 **多字重支持**：完整映射 Regular, Bold, Light, Medium 等 8 种字重（含斜体）
* 🔄 **开机自启**：自动创建 Systemd 服务，系统重启后静默恢复所有映射
* 🛠️ **智能管理**
  - 自动安装字体依赖（`fonts-noto-cjk`）
  - 冲突检测（官方/自定义模式互斥提示）
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
```bash
# 下载脚本
sudo wget https://github.com/krystic/flutter-arm-cjk-fix/raw/main/flutter-font-fix \
  -O /usr/local/bin/flutter-font-fix

# 赋予执行权限
sudo chmod +x /usr/local/bin/flutter-font-fix

# 安装 Tab 补全（可选）
sudo flutter-font-fix -i
```

### 基本用法

#### 1. 官方模式修复（推荐）
使用预设的 Ubuntu → Noto CJK 字体映射方案：
```bash
# 修复单个应用
sudo flutter-font-fix -a snap-store

# 修复后自动加入开机启动列表
# 支持 Tab 补全应用名（需先运行 -i 安装补全）
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

#### 4. 卸载映射
```bash
# 卸载单个应用（官方+自定义）
sudo flutter-font-fix -u snap-store

# 临时卸载所有（保留配置）
sudo flutter-font-fix --unmount-all

# 完全移除（清理配置和服务）
sudo flutter-font-fix --remove-service
```

---

## 📖 命令参考

### 主要命令

| 命令 | 功能说明 |
|------|---------|
| `sudo flutter-font-fix -a <app>` | 修复 Ubuntu 官方应用<br>Repair official Ubuntu apps |
| `sudo flutter-font-fix -c <app>` | 自定义字体修复<br>Repair with custom fonts |
| `sudo flutter-font-fix -u <app>` | 卸载映射<br>Unmount mappings |
| `flutter-font-fix -l \| --list` | 列出已映射应用<br>List mapped apps |
| `flutter-font-fix -d \| --detail` | 详细映射信息<br>Detail mappings |
| `sudo flutter-font-fix --unmount-all` | 卸载全部<br>Unmount all |
| `sudo flutter-font-fix --remove-service` | 移除管理器<br>Remove manager |
| `sudo flutter-font-fix -i \| --init` | 安装补全<br>Install completion |

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
└── <app_name>.conf                    # 自定义模式配置文件

/etc/systemd/system/
└── flutter-font-fix.service           # 系统启动服务

/etc/bash_completion.d/
└── flutter-font-fix                   # Tab 补全脚本

/usr/local/bin/
└── flutter-font-fix                # 主执行脚本
```

### 配置文件说明

**ubuntu.conf** - 官方模式应用列表
```
snap-store
desktop-security-center
```

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
1. **动态探测**：使用 `find -L` 自动发现 Snap 应用内的字体路径
2. **内存挂载**：通过 `mount --bind` 实现字体替换（不修改原始文件）
3. **多字重映射**：支持 8 种字重（R/RI/L/LI/M/MI/B/BI → Regular/Light/Medium/Bold）
4. **服务集成**：Systemd 服务 `After=snapd.service` 确保 Snap 挂载点就绪后执行
5. **配置持久化**：所有配置保存在 `/etc/flutter-cjk/`，支持系统重启后恢复

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
