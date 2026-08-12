# Flutter ARM CJK Font Fix

[![缩略图](images/snap-store-screenshot-thumb.png)](images/snap-store-screenshot.png)

**Ubuntu ARM 平台下 Flutter 应用 CJK 字体显示修复工具**

用于修复 Ubuntu ARM64 桌面环境中 Flutter 应用 CJK（中日韩）和部分非 ASCII 字符显示为方框的问题，支持 Snap 和非 Snap 应用。

> **适用范围**：Flutter 3.50.0 之前、未启用 Fontconfig 的 ARM64 Linux Flutter 应用。工具会通过 Engine Hash 自动识别 Flutter 版本，优先使用已校验的 SO 替换；Snap 应用无精确 SO 时可回退到字体映射。
>
> **官方修复状态**：Flutter 官方已 merge 我的 PR [flutter/flutter#180235](https://github.com/flutter/flutter/pull/180235)。从预计进入正式版的 Flutter 3.50.0 开始，ARM64 Linux Desktop Engine 会启用 Fontconfig。这个长期影响 ARM64 Linux 桌面用户的问题能在上游修复，我非常开心。检测到 Flutter 3.50.0 或之后版本时，本工具会直接跳过 SO 替换和字体映射。

---

## 📝 背景与原理

### 问题

在 Ubuntu ARM64 桌面环境（例如树莓派、飞腾、RK3588、Parallels 虚拟机等）中，部分 Flutter 应用会把 CJK 字符显示为方框。

已验证的根因是：旧版官方 ARM64 `libflutter_linux_gtk.so` 未链接 Fontconfig，Flutter Engine 无法通过系统字体配置完成字体回退。

Flutter 官方已合入我的 PR [flutter/flutter#180235](https://github.com/flutter/flutter/pull/180235)，将 ARM64 Linux Desktop 和 Embedded Engine 构建拆分，使桌面版启用 Fontconfig，同时避免影响嵌入式 Linux 构建。按照 Flutter 2026 发布窗口，这个修复预计进入 Flutter 3.50.0 正式版。

文本渲染链路：

```text
Flutter App → libflutter_linux_gtk.so → Skia → Fontconfig
```

```bash
# 旧版官方 ARM64 Engine：无输出
readelf -d libflutter_linux_gtk.so | grep fontconfig

# 启用 Fontconfig 的 Engine：应包含 libfontconfig.so.1
readelf -d libflutter_linux_gtk.so | grep fontconfig
```

详细分析见：[FONTCONFIG_BUG_INVESTIGATION.md](FONTCONFIG_BUG_INVESTIGATION.md)

### 解决方案

本项目由 **Krystic** 使用 **VS Code + Codex** 协同开发。根因定位依赖自编译 Flutter Engine 并与官方产物对比验证。

#### SO 替换

对 Flutter 3.50.0 之前的受影响应用，使用启用 Fontconfig 的 `libflutter_linux_gtk.so` 替换旧版官方 SO：

- Snap 应用：使用 `mount --bind`，不修改应用文件
- 非 Snap 应用：直接替换 SO，自动备份并记录 SHA-256，恢复时校验原文件和备份
- 在线 SO 必须通过 `SHA256SUMS` 校验后才会写入缓存

#### 官方已修复版本

从 Flutter 3.50.0 起，本工具默认认为官方 ARM64 Linux Desktop Engine 已包含 Fontconfig 修复。检测到 Flutter 3.50.0 或之后版本时，`flutter-font-fix` 会提示官方已修复并返回成功，不会替换 SO、创建备份、写入修复记录或回退字体映射。

#### 兜底方案

Snap 应用没有精确版本 SO 时，会回退到 Noto Sans CJK 字体映射。该方案只解决 CJK 字符，不能完整替代 Fontconfig。

---

## ✨ 特性

### 核心功能
* 🎯 **双应用类型支持**
  - **Snap 应用**（`-a`）：精确 SO 替换；无匹配时回退字体映射
  - **非 Snap 应用**（`-e`）：按可执行文件定位 SO，支持精确版本和相似版本选择
* 🔍 **版本智能检测**
  - 从 SO 提取 Engine Hash，匹配 Flutter 版本
  - 缓存版本对照表 7 天
  - Flutter 3.50.0+ 自动跳过修复
* 📦 **安全下载**：在线 SO 先下载到临时文件，通过 `SHA256SUMS` 校验后原子写入缓存
* 🔄 **开机自启**：systemd 服务可在重启后恢复 Snap 映射
* 🛠️ **智能管理**
  - 自动安装字体依赖（`fonts-noto-cjk`）
  - 配置持久化（`/etc/flutter-cjk/`）
  - 状态查看、移除、恢复、卸载
  - Bash 自动补全

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
- ✅ 安装功能模块到 `/usr/local/lib/flutter-font-fix/`
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

# 下载功能模块
sudo mkdir -p /usr/local/lib/flutter-font-fix
for module in engine non-snap snap system cli; do
  sudo wget \
    "https://raw.githubusercontent.com/krystic/flutter-arm-cjk-fix/main/src/${module}.sh" \
    -O "/usr/local/lib/flutter-font-fix/${module}.sh"
done

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
# [OK] [snap-store] Flutter 引擎已替换为 libflutter_linux_gtk.so.3.38.1
#      Flutter 引擎已替换，字体问题已根治。
```

#### 2. 修复非 Snap 应用
支持精确版本和相似版本选择（如 3.24.3 用于 3.24.5）：
```bash
sudo flutter-font-fix -e rustdesk
# 或
sudo flutter-font-fix -e /usr/bin/rustdesk

# 相似版本选择示例：
# [WARN] 未找到精确版本 3.24.5
# [INFO] 找到兼容版本：
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

# 恢复非 Snap 应用（名称或完整可执行文件路径）
sudo flutter-font-fix -r rustdesk
sudo flutter-font-fix -r /usr/bin/rustdesk

# 移除全部
sudo flutter-font-fix --remove-all
```

---

## 📖 命令参考

### 主要命令

| 命令 | 功能说明 |
|------|---------|
| `sudo flutter-font-fix -e <exe>` | 修复非 Snap 应用（支持精确版本和相似版本） |
| `sudo flutter-font-fix -a <app>` | 修复 Snap 应用（仅使用精确版本，未匹配时回退字体映射） |
| `sudo flutter-font-fix -c <app>` | 使用自定义字体修复 Snap 应用 |
| `sudo flutter-font-fix -r <app>` | 移除/卸载映射（包括 SO 和字体） |
| `flutter-font-fix -l \| --list` | 列出已映射应用 |
| `flutter-font-fix -d \| --detail` | 查看详细映射信息 |
| `sudo flutter-font-fix --remove-all` | 移除全部映射 |
| `sudo flutter-font-fix --uninstall-service` | 卸载 systemd 服务 |
| `sudo flutter-font-fix --uninstall` | 完全卸载 |
| `sudo flutter-font-fix -i \| --install-completion` | 安装 Bash 补全 |

### 全局参数

| 参数 | 功能说明 |
|------|---------|
| `--cdn <prefix>` | 覆盖 GitHub Raw CDN 前缀（含末尾斜杠） |

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
├── executables/                       # 非 Snap 应用修复记录
│   └── <executable-path-sha256>.conf  # 路径、版本、备份及文件校验值
└── <app_name>.conf                    # 自定义模式配置文件

/usr/local/lib/flutter-cjk/            # SO 文件本地缓存
└── libflutter_linux_gtk.so.X.Y.Z      # 下载的 SO 文件

/etc/systemd/system/
└── flutter-font-fix.service           # 系统启动服务

/etc/bash_completion.d/
└── flutter-font-fix                   # Tab 补全脚本

/usr/local/bin/
└── flutter-font-fix                   # 主执行脚本

/usr/local/lib/flutter-font-fix/        # 主程序模块
├── engine.sh                           # Engine 版本、下载与 SHA-256 校验
├── non-snap.sh                         # 非 Snap 替换、记录与安全恢复
├── snap.sh                             # Snap SO 挂载与字体映射
├── system.sh                           # 配置、服务、补全和状态管理
└── cli.sh                              # 参数解析与命令入口

<repository>/lib/                      # GitHub 仓库 SO 文件库
└── libflutter_linux_gtk.so.X.Y.Z      # 预编译的 SO 文件（30-40MB）
```

### 配置文件说明

**ubuntu.conf** - 应用配置列表（新格式）
```
snap-store|so              # SO 引擎替换
desktop-security-center|font   # 字体映射
old-app                    # 旧格式（兼容）
```

> `ubuntu.conf` 仅记录 Snap 应用。非 Snap 应用使用
> `executables/` 下的独立记录，避免同名可执行文件和包含空格的路径发生冲突。

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
   - 非 Snap 应用：直接替换系统 SO（支持相似版本，自动备份 `.bak`），并持久化记录原始与替换版本、路径和 SHA-256
4. **字体映射兜底**：无匹配 SO 时自动回退到 Noto CJK 字体映射
5. **开机自启**：Systemd 服务 `After=snapd.service` 确保 Snap 就绪后执行

下载在线 SO 时，工具会先获取 `lib/SHA256SUMS`，确认目标文件存在有效的
SHA-256 条目，再下载到临时文件。只有实际摘要与清单完全一致时才会原子移动到
`/usr/local/lib/flutter-cjk/`；清单缺失、条目无效或摘要不匹配都会终止操作并删除临时文件。

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
# 非 Snap 应用：校验当前文件和备份后安全恢复
sudo flutter-font-fix -r rustdesk
# 同名程序较多时可指定完整路径
sudo flutter-font-fix -r /usr/bin/rustdesk

# Snap 应用（-a 模式）使用 mount，直接卸载即可
sudo flutter-font-fix -r snap-store
```

如果当前 SO 在修复后被应用升级或其他程序修改，工具会拒绝用旧备份覆盖，
保留修复记录并提示人工检查。`--remove-all` 会恢复全部非 Snap 应用；
`--uninstall` 在任何非 Snap 应用无法安全恢复时会中止，以免删除恢复依据。

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

## 🧪 开发与测试

主脚本可以被安全地 `source`：只有直接执行时才进入 CLI 主函数。测试可通过
以下环境变量把所有路径切换到临时目录：

- `FLUTTER_CJK_CONFIG_DIR`
- `FLUTTER_CJK_SO_LIB_DIR`
- `FLUTTER_CJK_SNAP_ROOT`
- `FLUTTER_CJK_NOTO_DIR`
- `FLUTTER_CJK_SERVICE_FILE`

安装时设置 `FLUTTER_CJK_TARGET_MODULE_DIR` 或 `FLUTTER_CJK_SO_LIB_DIR` 后，
安装器会将实际路径记录在程序旁的 `.paths` 文件中；后续运行和卸载会自动使用
这些路径，无需再次传入环境变量。运行时显式设置环境变量仍可临时覆盖记录值。

测试尚未合并的远程分支时，可在安装阶段设置
`FLUTTER_CJK_REPO_REF=<branch>`。安装器会将分支名一并写入 `.paths`，使入口、
模块、版本映射、SO 文件、SHA-256 清单和 GitHub API 版本查询始终使用同一分支。
未设置时默认使用 `main`。

本地运行质量检查：

```bash
bash -n flutter-font-fix install.sh src/*.sh tests/run-tests.sh
shellcheck flutter-font-fix install.sh src/*.sh tests/run-tests.sh
bash tests/run-tests.sh
```

测试使用临时目录和模拟的 `curl`，不会修改 `/etc`、`/usr/local`、`/snap`，
也不会执行真实的挂载或 systemd 操作。GitHub Actions 的 `quality.yml`
会在相关文件变化时自动运行相同检查。

### 源码模块

仓库中的 `flutter-font-fix` 是轻量入口和模块加载器，实际功能位于 `src/`：

| 模块 | 职责 |
|------|------|
| `engine.sh` | Engine Hash 解析、版本匹配、在线查询、下载与摘要校验 |
| `non-snap.sh` | 非 Snap SO 替换、持久化记录和安全恢复 |
| `snap.sh` | Snap Engine 绑定挂载、字体映射及卸载 |
| `system.sh` | systemd、配置、补全、列表和自定义字体 |
| `cli.sh` | CLI 帮助、参数解析和主入口 |

本地运行时入口从同级 `src/` 加载模块；安装后从
`/usr/local/lib/flutter-font-fix/` 加载。缺少任何模块都会明确报错并停止，
不会在功能不完整的状态下继续运行。

---

## 📄 开源协议

[MIT License](LICENSE)

---

## 🙏 致谢

本项目由 **Krystic** 使用 **VS Code + Codex** 协同完成。核心问题的定位依赖自编译 Flutter Engine、`readelf` 对比验证，以及社区中关于 Snap/Flutter 字体问题的技术讨论。

感谢 Flutter 社区和相关资料对问题定位的帮助。

---

## 📮 反馈与贡献

欢迎通过 [Issues](https://github.com/krystic/flutter-arm-cjk-fix/issues) 报告问题或提出建议。
