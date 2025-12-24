# GitHub Actions 工作流说明

本仓库包含 3 个自动化构建工作流，用于自动检测和编译带 Fontconfig 支持的 Flutter Engine。

## 📋 工作流清单

### 1. 版本检查（轻量级）
**文件**: `.github/workflows/check-flutter-version.yml`

- **触发方式**: 
  - 定时任务：每 6 小时检查一次
  - 手动触发：Actions → Check Flutter Version → Run workflow
- **功能**: 检查 Flutter 是否发布新版本
- **结果**: 如果发现新版本，自动触发构建工作流
- **资源消耗**: 极低（仅 API 请求）

### 2. GitHub Runner 构建（带缓存）
**文件**: `.github/workflows/build-flutter-engine.yml`

- **触发方式**: 
  - 由版本检查工作流自动触发
  - 手动触发：Actions → Build Flutter Engine → Run workflow → 输入版本号
- **运行环境**: GitHub 托管的 Ubuntu Runner
- **特点**:
  - ✅ 使用缓存优化（depot_tools 和源码）
  - ✅ 免费使用（有时间和资源限制）
  - ⚠️ 编译时间较长（1-3 小时）
  - ⚠️ 可能受限于 GitHub Actions 配额
- **适用场景**: 偶尔构建、测试用途

### 3. 自托管 Runner 构建（推荐）
**文件**: `.github/workflows/build-flutter-engine-self-hosted.yml`

- **触发方式**:
  - 定时任务：每天 UTC 2:00（北京时间 10:00）
  - 手动触发：Actions → Build Flutter Engine (Self-Hosted) → Run workflow
- **运行环境**: 你自己的 ARM Linux 机器
- **特点**:
  - ✅ 编译速度快（原生 ARM64）
  - ✅ 无时间限制
  - ✅ 无资源配额限制
  - ✅ 可复用构建缓存
  - ⚠️ 需要配置自托管 Runner
- **适用场景**: 生产环境、频繁构建

---

## 🚀 快速开始

### 方案 A: 仅使用 GitHub Runner（免费但慢）

1. **推送工作流到仓库**
   ```bash
   git add .github/
   git commit -m "ci: add GitHub Actions workflows"
   git push
   ```

2. **等待自动检查**
   - 工作流会每 6 小时自动检查新版本
   - 发现新版本后自动触发构建

3. **或手动触发**
   - 访问 `https://github.com/YOUR_USERNAME/flutter-arm-cjk-fix/actions`
   - 选择 "Build Flutter Engine (with Cache)"
   - 点击 "Run workflow"
   - 输入 Flutter 版本号（如 `3.24.3`）
   - 点击 "Run workflow" 按钮

### 方案 B: 使用自托管 Runner（推荐）

#### 步骤 1: 准备 ARM Linux 机器

**最低要求**:
- CPU: ARM64 架构，至少 4 核
- 内存: 至少 8GB RAM
- 磁盘: 至少 50GB 可用空间
- 系统: Ubuntu 20.04+ 或其他 Linux 发行版

**推荐配置**:
- CPU: 8 核或更多
- 内存: 16GB RAM
- 磁盘: 100GB+ SSD

#### 步骤 2: 安装 GitHub Actions Runner

1. **前往仓库设置页面**
   ```
   https://github.com/YOUR_USERNAME/flutter-arm-cjk-fix/settings/actions/runners/new
   ```

2. **选择操作系统**
   - Operating System: Linux
   - Architecture: ARM64

3. **在你的 ARM 机器上执行命令**
   ```bash
   # 1. 创建目录
   mkdir actions-runner && cd actions-runner
   
   # 2. 下载 Runner（复制页面上的命令）
   curl -o actions-runner-linux-arm64-2.319.1.tar.gz \
     -L https://github.com/actions/runner/releases/download/v2.319.1/actions-runner-linux-arm64-2.319.1.tar.gz
   
   # 3. 解压
   tar xzf ./actions-runner-linux-arm64-2.319.1.tar.gz
   
   # 4. 配置 Runner（使用页面上的 token）
   ./config.sh --url https://github.com/YOUR_USERNAME/flutter-arm-cjk-fix \
     --token YOUR_REGISTRATION_TOKEN
   
   # 5. 安装为系统服务（开机自启）
   sudo ./svc.sh install
   sudo ./svc.sh start
   
   # 6. 检查状态
   sudo ./svc.sh status
   ```

4. **验证 Runner 状态**
   - 返回仓库设置页面
   - 应该看到绿色的 "Idle" 状态

#### 步骤 3: 安装编译依赖

在 ARM 机器上执行：

```bash
sudo apt-get update
sudo apt-get install -y \
  git curl unzip xz-utils zip \
  libglu1-mesa ninja-build \
  clang cmake pkg-config \
  libgtk-3-dev libblkid-dev \
  liblzma-dev libgcrypt20-dev \
  libfontconfig1-dev \
  python3 python3-pip \
  jq
```

#### 步骤 4: 测试运行

1. **手动触发构建**
   - 访问 Actions 页面
   - 选择 "Build Flutter Engine (Self-Hosted Runner)"
   - 点击 "Run workflow"
   - 输入版本号（如 `3.24.3`）

2. **观察构建过程**
   - 在 ARM 机器上可以看到 CPU 使用率上升
   - Actions 页面可以实时查看日志
   - 预计编译时间：30 分钟到 1 小时

3. **查看结果**
   - 编译成功后会自动推送到仓库
   - 并创建 GitHub Release

---

## 🔧 故障排除

### 问题 1: GitHub Runner 构建超时

**症状**: 构建运行超过 6 小时后被终止

**解决方案**:
- 使用自托管 Runner（无时间限制）
- 或者使用 GitHub Actions 付费套餐

### 问题 2: 磁盘空间不足

**症状**: 构建失败，提示 "No space left on device"

**解决方案**:
```bash
# 检查磁盘空间
df -h

# 清理旧的构建文件
cd ~/actions-runner/_work/flutter-arm-cjk-fix/flutter-arm-cjk-fix
rm -rf flutter-engine/src/out/*/obj
rm -rf flutter-engine/src/out/*/gen

# 或完全清理后重新构建
rm -rf flutter-engine
```

### 问题 3: 自托管 Runner 离线

**症状**: Actions 页面显示 "No runners available"

**解决方案**:
```bash
# 检查 Runner 服务状态
cd ~/actions-runner
sudo ./svc.sh status

# 重启服务
sudo ./svc.sh stop
sudo ./svc.sh start

# 查看日志
sudo journalctl -u actions.runner.* -f
```

### 问题 4: 缓存问题

**症状**: 构建失败，提示代码同步错误

**解决方案**:
```bash
# 清理缓存后重试
cd ~/actions-runner/_work/flutter-arm-cjk-fix/flutter-arm-cjk-fix
rm -rf flutter-engine
rm -rf depot_tools
```

---

## 📊 性能对比

| 指标 | GitHub Runner | 自托管 Runner (8核) |
|------|---------------|-------------------|
| 编译时间 | 2-3 小时 | 30-60 分钟 |
| 并发限制 | 20 个任务* | 无限制 |
| 时间限制 | 6 小时 | 无限制 |
| 磁盘空间 | ~14GB | 自定义 |
| 成本 | 免费（有配额） | 硬件成本 |

*免费账户限制，付费账户可更高

---

## 🎯 推荐配置

### 对于个人项目（偶尔构建）
使用 **GitHub Runner** 足够：
- 简单易用
- 无需维护
- 免费使用

### 对于生产项目（频繁更新）
使用 **自托管 Runner**：
- 编译速度快 3-4 倍
- 无时间和配额限制
- 可复用构建缓存
- 一次性投入（购买 ARM 设备）

### 混合方案（最优）
- **版本检查**: GitHub Runner（轻量级）
- **实际构建**: 自托管 Runner（高性能）
- 两者配合，自动化程度最高

---

## 📝 注意事项

1. **首次构建时间长**
   - 需要下载约 10GB 源码
   - 首次编译需要 1-3 小时
   - 后续构建会利用缓存，速度更快

2. **版本号格式**
   - 确保使用正确的版本号格式
   - 示例: `3.24.3`, `3.27.0`
   - 不要添加 `v` 前缀

3. **磁盘管理**
   - 每个版本占用约 5-20MB（SO 文件）
   - 构建缓存占用约 30-50GB
   - 定期清理旧版本和缓存

4. **安全性**
   - 自托管 Runner 可以访问你的仓库
   - 确保机器安全，定期更新系统
   - 不要在生产服务器上运行 Runner

---

## 🆘 获取帮助

遇到问题？

1. 查看 [Actions 运行日志](https://github.com/YOUR_USERNAME/flutter-arm-cjk-fix/actions)
2. 查看 [Flutter Engine 编译文档](https://github.com/flutter/flutter/wiki/Compiling-the-engine)
3. 查看本仓库的 [Issues](https://github.com/YOUR_USERNAME/flutter-arm-cjk-fix/issues)
4. 创建新的 Issue 描述问题

---

## 📚 相关文档

- [GitHub Actions 文档](https://docs.github.com/en/actions)
- [自托管 Runner 配置](https://docs.github.com/en/actions/hosting-your-own-runners)
- [Flutter Engine 编译指南](https://github.com/flutter/flutter/wiki/Compiling-the-engine)
- [FONTCONFIG_BUG_INVESTIGATION.md](./FONTCONFIG_BUG_INVESTIGATION.md) - 根本原因分析
