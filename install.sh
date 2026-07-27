#!/usr/bin/env bash
set -euo pipefail

# flutter-arm-cjk-fix installer
# Usage: curl -fsSL https://raw.githubusercontent.com/krystic/flutter-arm-cjk-fix/main/install.sh | sudo bash

REPO_REF="${FLUTTER_CJK_REPO_REF:-main}"
REPO_RAW="${FLUTTER_CJK_REPO_RAW:-https://raw.githubusercontent.com/krystic/flutter-arm-cjk-fix/$REPO_REF}"
TARGET_BIN="${FLUTTER_CJK_TARGET_BIN:-/usr/local/bin/flutter-font-fix}"
TARGET_MODULE_DIR="${FLUTTER_CJK_TARGET_MODULE_DIR:-/usr/local/lib/flutter-font-fix}"
SO_LIB_DIR="${FLUTTER_CJK_SO_LIB_DIR:-/usr/local/lib/flutter-cjk}"
TARGET_PATHS_FILE="${TARGET_BIN}.paths"
CONFIG_DIR="${FLUTTER_CJK_CONFIG_DIR:-/etc/flutter-cjk}"
SERVICE_FILE="${FLUTTER_CJK_SERVICE_FILE:-/etc/systemd/system/flutter-font-fix.service}"

log() { printf "[INST] %s\n" "$*"; }
warn() { printf "[warn] %s\n" "$*"; }
err() { printf "[error] %s\n" "$*"; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "Root privileges required. Please run with sudo: sudo bash"
    echo "       需要 root 权限，请使用 sudo 运行：sudo bash"
    exit 1
  fi
}

check_platform() {
  local os
  os=$(uname -s)
  if [[ "$os" != "Linux" ]]; then
    warn "Non-Linux OS detected. This tool targets ARM Linux only."
    echo "       当前系统不是 Linux。此工具针对 ARM Linux 修复，暂不需要安装。"
    exit 0
  fi
}

check_architecture() {
  local arch
  arch=$(uname -m | tr '[:upper:]' '[:lower:]')
  case "$arch" in
    aarch64|aarch|arm|arm64)
      log "Detected ARM architecture: $arch"
      echo "       检测到 ARM 架构: $arch"
      ;;
    *)
      warn "Non-ARM architecture detected: $arch"
      echo "       检测到非 ARM 架构: $arch"
      echo ""
      echo "This script is specifically designed to fix Flutter CJK font fallback issues on ARM platforms."
      echo "此脚本专为修复 ARM 平台上的 Flutter CJK 字体回退问题而设计。"
      echo ""
      echo "Your current architecture ($arch) does not require this fix."
      echo "您当前的架构 ($arch) 不需要此修复。"
      exit 0
      ;;
  esac
}

install_dependencies() {
  # 安装 bash-completion 与字体（fonts-noto-cjk）
  if command -v apt-get >/dev/null 2>&1; then
    log "Installing required components (bash-completion, fonts-noto-cjk)..."
    echo "       安装必要组件（bash-completion, fonts-noto-cjk）..."
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y bash-completion fonts-noto-cjk >/dev/null 2>&1 || true
  fi
}

install_binary() {
  mkdir -p "$(dirname "$TARGET_BIN")"
  if [[ -f "./flutter-font-fix" ]]; then
    log "Found local script, installing to $TARGET_BIN"
    echo "       发现本地脚本，安装到 $TARGET_BIN"
    cp ./flutter-font-fix "$TARGET_BIN"
  else
    log "Downloading main script to $TARGET_BIN"
    echo "       下载主脚本到 $TARGET_BIN"
    curl -fsSL "$REPO_RAW/flutter-font-fix" -o "$TARGET_BIN"
  fi
  chmod +x "$TARGET_BIN"
  printf 'module_dir=%s\nso_lib_dir=%s\nrepo_ref=%s\n' \
    "$TARGET_MODULE_DIR" "$SO_LIB_DIR" "$REPO_REF" > "$TARGET_PATHS_FILE"
  chmod 644 "$TARGET_PATHS_FILE"
}

install_modules() {
  local modules=(engine non-snap snap system cli)
  local module parent_dir staging_dir backup_dir=""
  parent_dir=$(dirname "$TARGET_MODULE_DIR")
  mkdir -p "$parent_dir"
  staging_dir=$(mktemp -d "${TARGET_MODULE_DIR}.tmp.XXXXXX")

  if [[ -f "./flutter-font-fix" && -d "./src" ]]; then
    log "Installing local modules to $TARGET_MODULE_DIR"
    echo "       安装本地程序模块到 $TARGET_MODULE_DIR"
    for module in "${modules[@]}"; do
      if ! cp "./src/$module.sh" "$staging_dir/$module.sh"; then
        rm -rf "$staging_dir"
        return 1
      fi
    done
  else
    log "Downloading program modules to $TARGET_MODULE_DIR"
    echo "       下载程序模块到 $TARGET_MODULE_DIR"
    for module in "${modules[@]}"; do
      if ! curl -fsSL "$REPO_RAW/src/$module.sh" -o "$staging_dir/$module.sh"; then
        rm -rf "$staging_dir"
        return 1
      fi
    done
  fi

  if ! bash -n "$staging_dir"/*.sh; then
    err "Downloaded modules failed Bash syntax validation."
    rm -rf "$staging_dir"
    return 1
  fi
  chmod 644 "$staging_dir"/*.sh

  if [[ -e "$TARGET_MODULE_DIR" ]]; then
    backup_dir="${staging_dir}.backup"
    if ! mv "$TARGET_MODULE_DIR" "$backup_dir"; then
      rm -rf "$staging_dir"
      return 1
    fi
  fi

  if ! mv "$staging_dir" "$TARGET_MODULE_DIR"; then
    [[ -n "$backup_dir" ]] && mv "$backup_dir" "$TARGET_MODULE_DIR"
    rm -rf "$staging_dir"
    return 1
  fi
  if [[ -n "$backup_dir" ]]; then
    rm -rf "$backup_dir"
  fi
}

init_config() {
  mkdir -p "$CONFIG_DIR"
  mkdir -p "$CONFIG_DIR/executables"
  # 清理由旧版仓库映射方案遗留、当前已不再使用的配置文件
  rm -f "$CONFIG_DIR/github-repos.conf" "$CONFIG_DIR/flutter-versions.cache"
  # 官方映射配置（应用列表与方法）
  [[ -f "$CONFIG_DIR/ubuntu.conf" ]] || touch "$CONFIG_DIR/ubuntu.conf"
}

init_so_dir() {
  local SO_DIR="$SO_LIB_DIR"
  mkdir -p "$SO_DIR"
  # 如本地仓库已有预编译 SO，复制到系统 SO 目录
  if [[ -d ./lib ]]; then
    log "Copying local lib/ SO files into system directory..."
    echo "       复制本地 lib/ 目录中的 SO 到系统目录..."
    cp -v ./lib/libflutter_linux_gtk.so.* "$SO_DIR/" 2>/dev/null || true
    if [[ -f ./lib/SHA256SUMS ]]; then
      cp ./lib/SHA256SUMS "$SO_DIR/SHA256SUMS"
      log "Verifying copied SO files with SHA256SUMS..."
      echo "       正在使用 SHA256SUMS 校验复制的 SO 文件..."
      (cd "$SO_DIR" && sha256sum -c SHA256SUMS)
    fi
  fi
}


install_service_via_script() {
  log "Installing systemd service via main script..."
  echo "       调用主脚本安装 systemd 服务..."
  "$TARGET_BIN" --install-service || true
}

print_summary() {
  echo
  log "Installation completed / 安装完成!"
  echo "- 程序 / Binary:         $TARGET_BIN"
  echo "- 模块 / Modules:        $TARGET_MODULE_DIR"
  echo "- SO 库 / SO libraries:  $SO_LIB_DIR"
  echo "- 配置 / Config dir:     $CONFIG_DIR"
  echo "- 服务 / Service file:   $SERVICE_FILE"
  echo
  echo "Quick usage / 快速使用:"
  echo "  sudo flutter-font-fix -e <app_name>    # Fix via Engine SO or similar version (non-Snap)"
  echo "                                         # 允许使用相近版本 SO 修复非 Snap 分发的应用"
  echo "  sudo flutter-font-fix -a <app_name>    # Root fix via Engine SO; fallback to font mapping"
  echo "                                         # 优先使用 SO 根因修复，回退到字体映射"
  echo "  sudo flutter-font-fix -c <app_name>    # Repair with custom fonts"
  echo "                                         # 自定义字体修复"
  echo "  sudo flutter-font-fix -r <app_name>    # Remove/unmount mappings"
  echo "                                         # 移除/卸载映射"
  echo "  flutter-font-fix -l                    # List mapped apps"
  echo "                                         # 列出已映射应用"
  echo "  flutter-font-fix -d                    # Detail mappings"
  echo "                                         # 详细映射信息"

}

main() {
  check_architecture
  require_root
  check_platform
  install_dependencies
  install_modules
  install_binary
  init_config
  init_so_dir
  install_service_via_script
  print_summary
}

if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
  main "$@"
fi
