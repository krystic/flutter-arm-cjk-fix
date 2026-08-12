# GitHub Actions 工作流说明

本仓库包含三个工作流，用于检查 Shell 代码质量、维护 Flutter Engine
版本映射，并构建启用了 Fontconfig 的 Linux ARM64 Engine。

## 工作流

### 1. Shell 质量检查

文件：`quality.yml`

当主脚本、安装器、测试或质量工作流变化时，在 Push 和 Pull Request 上运行，
也支持手动触发。工作流依次执行：

1. 对入口、安装器、`src/*.sh` 和测试执行 `bash -n` 语法检查；
2. 对相同文件执行 ShellCheck 静态分析；
3. `tests/run-tests.sh` 无 root 模拟测试。

### 2. 检查 Flutter 版本

文件：`check-flutter-version.yml`

触发方式：

- 每 6 小时定时运行；
- 可从 Actions 页面手动运行。

主要任务：

1. 从 `flutter/flutter` 的稳定版 Git Tag 中确定最新版本；
2. 解析该 Tag 对应的 Flutter 提交；
3. 如果版本为 Flutter 3.50.0 或更新版本，认为官方 ARM64 Linux Desktop
   Fontconfig 修复已经可用，不再自动构建自定义 SO；
4. 对 Flutter 3.50.0 之前的版本，检查
   `lib/libflutter_linux_gtk.so.<version>` 是否已经存在；
5. 缺少时通过 `repository_dispatch` 触发构建工作流；
6. 遍历稳定版 Tag，读取 `bin/internal/engine.version`，重新生成
   `flutter.engine.hash.version`；
7. 自动提交版本映射变化；工作流失败时创建 Issue 供维护者处理。

注意：即使 Flutter 3.50.0 之后不再自动构建 SO，版本检查工作流仍会维护
`flutter.engine.hash.version`。运行时需要这个映射来识别 3.50.0+ 应用并安全跳过修复。

### 3. 构建 Flutter Engine

文件：`build-flutter-engine.yml`

触发方式：

- 接收版本检查工作流发出的 `build-flutter-engine` 仓库事件；
- 可从 Actions 页面手动运行，并输入 Flutter 版本和可选的 Flutter 提交。

构建环境为 GitHub 托管的 `ubuntu-latest` Runner，超时限制为 6 小时。
工作流会：

1. 解析或使用指定的 Flutter 提交；
2. 获取 `depot_tools` 和 Flutter Engine 源码；
3. 使用以下关键参数生成 Linux ARM64 Release 构建：

   ```bash
   ./flutter/tools/gn \
     --target-os linux \
     --linux-cpu arm64 \
     --runtime-mode release \
     --enable-fontconfig \
     --no-goma \
     --no-prebuilt-dart-sdk
   ```

4. 使用 Ninja 编译 Engine；
5. 通过 `readelf -d` 验证产物确实链接 `libfontconfig.so`；
6. 重新生成 `lib/SHA256SUMS` 并校验仓库中的全部 SO；
7. 上传构建 Artifact；
8. 更新 `lib/README.md`，提交 SO 和校验清单到 `main`；
9. 创建包含 SO 与 `SHA256SUMS` 的 `flutter-<version>` GitHub Release。

## 手动构建

1. 打开仓库的 Actions 页面；
2. 选择 `Build Flutter Engine (with Cache)`；
3. 点击 `Run workflow`；
4. 输入不带 `v` 前缀的 Flutter 版本，例如 `3.44.8`；
5. 可选填写该 Tag 对应的 Flutter 提交 SHA；
6. 运行并检查 `Extract and verify SO file` 步骤。

## 资源与故障排查

- 首次同步源码和编译可能耗时数小时，并需要大量磁盘空间；
- 工作流会清理 GitHub Runner 中不需要的预装组件；
- `depot_tools` 使用 Actions Cache，Flutter 源码当前不做持久化缓存；
- 构建超时：检查是否超过 6 小时，必要时手动重试；
- 磁盘不足：查看 `Free up disk space` 和各阶段的 `df -h` 输出；
- Tag 解析失败：检查 `Resolve Flutter revision` 的 GitHub API 响应；
- Fontconfig 验证失败：检查 GN 参数和 `readelf` 输出，不应发布该产物；
- SHA-256 验证失败：检查产物是否完整，禁止手工绕过清单验证；
- 推送冲突：检查 `Commit and push` 中的 rebase 和 push 日志。

## 权限与安全

- 版本检查需要 `contents: write` 和 `issues: write`；
- 构建使用仓库提供的 `GITHUB_TOKEN` 推送产物并创建 Release；
- 工作流仅应构建可验证的 Flutter Tag 或明确指定的可信提交；
- Release 前必须保留 Fontconfig 动态链接验证步骤。

相关资料：

- [Flutter Engine 编译指南](https://github.com/flutter/flutter/wiki/Compiling-the-engine)
- [GitHub Actions 文档](https://docs.github.com/en/actions)
- [根本原因调查](../../FONTCONFIG_BUG_INVESTIGATION.md)
