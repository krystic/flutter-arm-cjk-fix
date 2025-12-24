#!/usr/bin/env bash
set -euo pipefail

# flutter-arm-cjk-fix installer
# Usage: curl -fsSL https://raw.githubusercontent.com/krystic/flutter-arm-cjk-fix/main/install.sh | sudo bash

REPO_RAW="https://raw.githubusercontent.com/krystic/flutter-arm-cjk-fix/feature/so-libdir-and-auto-download"
TARGET_BIN="/usr/local/bin/flutter-font-fix"
CONFIG_DIR="/etc/flutter-cjk"
SERVICE_FILE="/etc/systemd/system/flutter-font-fix.service"

log() { printf "[install] %s\n" "$*"; }
warn() { printf "[warn] %s\n" "$*"; }
err() { printf "[error] %s\n" "$*"; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "需要 root 权限，请使用 sudo 运行：sudo bash"
    exit 1
  fi
}

check_platform() {
  local os arch
  os=$(uname -s)
  arch=$(uname -m)
  if [[ "$os" != "Linux" ]]; then
    warn "当前系统不是 Linux。此工具针对 ARM Linux 修复，暂不需要安装。"
    exit 0
  fi
  case "$arch" in
    aarch64|arm64)
      ;;
    *)
      warn "检测到架构: $arch。此脚本用于修复 ARM64 Linux 的 Flutter 字体问题，非 ARM64 无需安装。"
      exit 0
      ;;
  esac
}

install_dependencies() {
  # 安装 bash-completion 与字体（fonts-noto-cjk）
  if command -v apt-get >/dev/null 2>&1; then
    log "安装必要组件（bash-completion, fonts-noto-cjk）..."
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y bash-completion fonts-noto-cjk >/dev/null 2>&1 || true
  fi
}

install_binary() {
  mkdir -p "$(dirname "$TARGET_BIN")"
  if [[ -f "./flutter-font-fix" ]]; then
    log "发现本地脚本，安装到 $TARGET_BIN"
    cp ./flutter-font-fix "$TARGET_BIN"
  else
    log "下载主脚本到 $TARGET_BIN"
    curl -fsSL "$REPO_RAW/flutter-font-fix" -o "$TARGET_BIN"
  fi
  chmod +x "$TARGET_BIN"
}

init_config() {
  mkdir -p "$CONFIG_DIR"
  # 官方映射配置（应用列表与方法）
  [[ -f "$CONFIG_DIR/ubuntu.conf" ]] || touch "$CONFIG_DIR/ubuntu.conf"
  # GitHub 仓库映射（示例复制为默认）
  if [[ ! -f "$CONFIG_DIR/github-repos.conf" ]]; then
    if [[ -f ./github-repos.conf.example ]]; then
      cp ./github-repos.conf.example "$CONFIG_DIR/github-repos.conf"
    else
      curl -fsSL "$REPO_RAW/github-repos.conf.example" -o "$CONFIG_DIR/github-repos.conf" || true
    fi
  fi
  # 版本缓存（自动检测加速）
  [[ -f "$CONFIG_DIR/flutter-versions.cache" ]] || touch "$CONFIG_DIR/flutter-versions.cache"
}

init_so_dir() {
  local SO_DIR="/usr/local/lib/flutter-cjk"
  mkdir -p "$SO_DIR"
  # 如本地仓库已有预编译 SO，复制到系统 SO 目录
  if [[ -d ./lib ]]; then
    log "复制本地 lib/ 目录中的 SO 到系统目录..."
    cp -v ./lib/libflutter_linux_gtk.so.* "$SO_DIR/" 2>/dev/null || true
  fi
}

install_completion() {
  log "安装 Bash 自动补全..."
  # 使用主脚本的 -i 入口安装补全
  "$TARGET_BIN" -i || true
}

install_service_via_script() {
  log "调用主脚本安装 systemd 服务..."
  "$TARGET_BIN" --install-service || true
}

print_summary() {
  echo
  log "安装完成！"
  echo "- 可执行文件: $TARGET_BIN"
  echo "- 配置目录:   $CONFIG_DIR"
  echo "- 服务文件:   $SERVICE_FILE"
  echo
  echo "快速使用："
  echo "  sudo flutter-font-fix -a <app_name>    # 优先使用 SO 根因修复，回退到字体映射"
  echo "  sudo flutter-font-fix -d               # 查看修复方式与状态 (SO/font/unknown)"
  echo "  sudo systemctl start flutter-font-fix  # 按配置启动（如已配置应用）"
  echo
  echo "架构提示：非 ARM64 Linux 无需安装，此脚本仅用于修复 ARM64 平台上的 Flutter 引擎字体回退问题。"
}

main() {
  require_root
  check_platform
  install_dependencies
  install_binary
  init_config
  init_so_dir
  install_service_via_script
  install_completion
  print_summary
}

main "$@"
