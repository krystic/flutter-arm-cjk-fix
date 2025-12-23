# Flutter Linux ARM64 中文字体显示问题调查报告

**日期**: 2025年12月21日  
**问题**: Ubuntu App Center 在 Linux ARM64 平台上中文字符显示为方块  
**状态**: 根本原因已确定，解决方案已验证

---

## 一、问题现象

在 Linux ARM64 (aarch64) 平台的 Ubuntu 系统上，使用官方 Flutter SDK 构建的桌面应用（包括 Ubuntu App Center）中，所有中文字符都显示为方块（□□□），而英文字符显示正常。

**影响范围**:
- Ubuntu App Center (Flutter 构建)
- 所有使用官方 Flutter SDK 在 Linux ARM64 上开发的桌面应用

**不受影响的平台**:
- Linux x64: 正常
- Android ARM64: 正常
- iOS: 正常
- macOS ARM64: 正常

---

## 二、根本原因分析

### 2.1 技术层面

Flutter 的文本渲染依赖以下组件链：
```
Flutter App → libflutter_linux_gtk.so → Skia → FontConfig
```

**问题定位**:
1. 官方的 `libflutter_linux_gtk.so` (ARM64) **未链接** `libfontconfig.so`
2. 通过 `readelf -d` 验证：
   ```bash
   # 官方版本
   readelf -d libflutter_linux_gtk.so | grep fontconfig
   # (无输出)
   
   # 自编译修复版
   readelf -d libflutter_linux_gtk.so | grep fontconfig
   # 0x0000000000000001 (NEEDED)  共享库：[libfontconfig.so.1]
   ```

### 2.2 构建配置缺陷

**x64 平台 (正常)**:
- 构建配置: `flutter/ci/builders/linux_host_desktop_engine.json`
- GN 参数: 包含 `--enable-fontconfig`
- 产物: 支持字体发现和渲染

**ARM64 平台 (缺陷)**:
- 构建配置: `flutter/ci/builders/linux_arm_host_engine.json`
- GN 参数: **缺少** `--enable-fontconfig`
- 产物: 无法发现系统字体，中文显示为方块

### 2.3 架构失误

官方在 ARM64 构建配置中，将**桌面目标**（`flutter_gtk`）和**嵌入式目标**（`embedder.zip`）混在同一个构建配置中，且使用了适合嵌入式的"精简"参数（无 fontconfig），导致桌面版也继承了这个缺陷。

对比 x64 平台，Google 正确地将桌面和嵌入式拆分为两个独立的构建配置：
- `linux_host_engine.json`: 嵌入式（无 fontconfig）
- `linux_host_desktop_engine.json`: 桌面（有 fontconfig）

但在 ARM64 上，只有一个 `linux_arm_host_engine.json`，尝试"一鱼两吃"，最终导致桌面版被牺牲。

---

## 三、解决方案

### 3.1 立即可用的 Workaround（已验证）

**步骤**:
1. 克隆 Flutter Engine 源码（对应你的 Flutter SDK 版本）
2. 修改 `out/linux_debug_unopt_arm64/args.gn`，添加：
   ```gn
   flutter_use_fontconfig = true
   ```
3. 重新编译：
   ```bash
   ninja -C out/linux_debug_unopt_arm64 flutter/shell/platform/linux:flutter_gtk
   ```
4. 替换官方引擎：
   ```bash
   cp out/linux_debug_unopt_arm64/libflutter_linux_gtk.so \
      ~/.cache/flutter/<version>/linux-arm64-debug/
   ```

**效果**: App Center 中文立即恢复显示。

### 3.2 官方修复方案（待提交 PR）

**修改文件**:

#### 1. 新建 `flutter/ci/builders/linux_arm_host_desktop_engine.json`
```json
{
    "builds": [
        {
            "name": "ci/linux_profile_arm64_desktop",
            "gn": [
                "--runtime-mode", "profile",
                "--enable-fontconfig",  // ← 关键
                "--target-os=linux",
                "--linux-cpu=arm64"
            ],
            "ninja": {
                "targets": ["flutter/shell/platform/linux:flutter_gtk"]
            }
        },
        // debug 和 release 同理
    ]
}
```

#### 2. 修改 `flutter/ci/builders/linux_arm_host_engine.json`
- **移除**: `flutter/shell/platform/linux:flutter_gtk` 目标
- **保留**: `flutter/build/archives:embedder` 等嵌入式目标
- **不添加**: `--enable-fontconfig` (嵌入式不需要)

#### 3. 修改 `flutter/.ci.yaml`
注册新的 Builder:
```yaml
targets:
  - name: Linux linux_arm_host_desktop_engine
    recipe: engine_v2/engine_v2
    properties:
      config_name: linux_arm_host_desktop_engine
```

**架构优势**:
- **解耦**: 桌面和嵌入式使用独立的构建配置
- **无副作用**: 嵌入式引擎恢复纯净（无 fontconfig 依赖）
- **对下游透明**: Flutter Tool 和 VS Code 无需任何修改

---

## 四、版本发布与分发流程

### 4.1 官方接受与合并
1. **提交 PR**: 向 `flutter/engine` 仓库提交 Pull Request
2. **代码审查**: Google 团队审查（预计 1-2 周）
3. **合并进 master**: 进入 Master Channel

### 4.2 Flutter 版本发布
- **Master Channel**: 立即可用（持续构建）
- **Beta Channel**: 2-4 周后
- **Stable Channel**: 下一个大版本发布时（可能 2-3 个月）
  - 如果被认定为 **Critical Bug**，可能会发布 Hotfix (如 3.27.2)

### 4.3 Ubuntu 官方更新
1. **Canonical 打包团队**发现上游修复
2. 决定是否 Backport 到当前 Ubuntu 版本的 Flutter 包
   - **快速路径**: Cherry-pick 补丁到现有版本 (如 `flutter_3.27.1-0ubuntu2`)
   - **慢速路径**: 等待下一个 Stable 版本并重新打包

**时间线预估**:
- PR 合并到 Master: 1-2 周
- 进入 Flutter Stable: 2-3 个月
- Ubuntu 官方更新推送: 取决于 Canonical 的决策，可能提前（Cherry-pick），也可能跟随 Stable

---

## 五、给开发者的建议

### 5.1 如果你现在就需要修复
使用本地编译的引擎替换官方版本（见 3.1 节）。

### 5.2 如果你可以等待
1. 关注 PR 状态: `https://github.com/flutter/engine/pulls`
2. 一旦合并，切换到 Master Channel:
   ```bash
   flutter channel master
   flutter upgrade
   ```
3. 或等待 Stable 版本并升级项目依赖

### 5.3 给 Ubuntu/Snap 开发者
联系 Canonical 团队，告知这个问题及修复方案，建议在下一次 `flutter-snap` 更新中包含这个补丁。

---

## 六、技术附录

### 6.1 构建系统关键路径
```
CI 配置 (.ci.yaml)
  ↓
Builder 定义 (ci/builders/*.json)
  ↓
GN 脚本 (flutter/tools/gn)
  ↓
BUILD.gn 文件 (各模块)
  ↓
Ninja 构建 (build.ninja)
  ↓
产物 (libflutter_linux_gtk.so)
```

### 6.2 FontConfig 在 Flutter 中的角色
- **字体发现**: 扫描系统的 `/usr/share/fonts`
- **字体匹配**: 根据字符 Unicode 范围选择合适的字体文件
- **Fallback 机制**: 当主字体不包含某字符时，自动查找替代字体

**缺少 FontConfig 的后果**:
- 只能使用 Flutter 内置字体（Roboto）
- CJK 字符无法找到对应字体 → 显示为方块

### 6.3 验证命令速查
```bash
# 检查动态链接
readelf -d libflutter_linux_gtk.so | grep fontconfig

# 检查 GN 参数
cat out/xxx/args.gn | grep fontconfig

# 重新生成构建文件
./flutter/tools/gn --enable-fontconfig --target-os=linux --linux-cpu=arm64

# 增量编译
ninja -C out/xxx flutter/shell/platform/linux:flutter_gtk
```

---

## 七、致谢

感谢所有参与调查和验证的开发者。特别感谢:
- Flutter 社区提供的构建工具链
- Ubuntu 社区对 ARM64 平台的支持
- Gemini AI 提供的初步线索（虽然是猜测，但指明了方向）

---

**文档维护者**: Krystic  
**最后更新**: 2025年12月21日
