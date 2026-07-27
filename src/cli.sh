show_usage() {
    echo "Usage:"
    echo "  sudo $(basename "$0") -a <app_name>       Repair Snap app with Flutter Engine or fonts"
    echo "                                            使用引擎修复或字体映射 (Snap 应用)"
    echo "  sudo $(basename "$0") -c <app_name>       Repair with custom fonts / 自定义字体修复"
    echo "  sudo $(basename "$0") -r <app_name>       Remove/unmount mappings / 移除/卸载映射"
    echo "  $(basename "$0") -l | --list              List mapped apps / 列出已映射应用"
    echo "  $(basename "$0") -d | --detail            Detail mappings / 详细映射信息"
    echo "  sudo $(basename "$0") --remove-all        Remove all / 移除全部"
    echo ""
    echo "  sudo $(basename "$0") -e <exe_path>       Repair non-Snap app by executable path"
    echo "                                            通过可执行文件路径修复非 Snap 应用"
    echo ""
    echo "  sudo $(basename "$0") -i | --install-completion  Install completion / 安装补全"
    echo "  sudo $(basename "$0") --install-service          Install systemd service / 安装系统服务"
    echo ""
    echo "  sudo $(basename "$0") --uninstall-service Uninstall systemd service / 卸载系统服务"
    echo "  sudo $(basename "$0") --uninstall         Uninstall completely / 完全卸载"
    echo ""
    echo "Examples / 示例:"
    echo "  $(basename "$0") -a snap-store                    # Snap app"
    echo "  $(basename "$0") -e /usr/bin/rustdesk             # Non-Snap app"
}

# 自动安装补全（如果尚未安装且有 root 权限）
auto_install_completion() {
    if [[ ! -f "$COMPLETION_FILE" ]] && [[ $EUID -eq 0 ]]; then
        echo ""
        echo "[INFO] Shell completion not found, installing..."
        echo "       未找到补全脚本，正在安装..."
        install_completion
    fi
}

# 处理系统级命令（--startup, --uninstall, --install-service, --install-completion 等）
handle_system_commands() {
    case "$1" in
        --startup)
            [ ! -f "$CONFIG_FILE" ] && {
                mount_all_custom_fonts
                exit 0
            }
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                # 解析格式：app|method 或 app（旧格式）
                app=""
                if [[ "$line" == *"|"* ]]; then
                    app="${line%%|*}"
                else
                    app="$line"
                fi
                if [ -n "$app" ]; then
                    if ! do_mount "$app" "true"; then
                        echo "[WARN] Failed to mount fonts for: $app, skipping."
                        echo "       跳过该应用的字体挂载。"
                    fi
                fi
            done < "$CONFIG_FILE"
            # 也加载并挂载自定义字体配置
            mount_all_custom_fonts
            exit 0
            ;;
        -e|--executable)
            check_root
            if [ -z "$2" ]; then
                echo "用法 / Usage: $0 -e <executable_path_or_name>"
                echo "Example: $0 -e /usr/bin/rustdesk"
                echo "Example: $0 -e rustdesk"
                exit 1
            fi

            local exe_path="$2"
            # 如果不是绝对路径，尝试通过 which 查找
            if [[ "$exe_path" != /* ]]; then
                local resolved_path=$(which "$exe_path" 2>/dev/null)
                if [[ -n "$resolved_path" ]]; then
                    echo "[INFO] Resolved '$exe_path' to: $resolved_path"
                    echo "       解析 '$exe_path' 为：$resolved_path"
                    exe_path="$resolved_path"
                else
                    echo "[ERROR] Executable not found: $exe_path" >&2
                    echo "        未找到可执行文件。" >&2
                    exit 1
                fi
            fi

            handle_executable_app "$exe_path"
            exit $?
            ;;
        -c|--custom)
            check_root
            if [ -z "$2" ]; then
                echo "用法 / Usage: $0 -c <app_name>"
                exit 1
            fi
            do_custom_fonts "$2"
            exit 0
            ;;
        -l|--list)
            list_mapped_apps
            exit 0
            ;;
        -d|--detail)
            list_mapped_apps_detail
            exit 0
            ;;
        --remove-all)
            check_root
            do_unmount_all
            exit $?
            ;;
        --uninstall-service)
            check_root
            if ! do_unmount_all; then
                echo "[ERROR] Service uninstall stopped because some files could not be restored." >&2
                echo "        部分文件无法安全恢复，已停止卸载服务。" >&2
                exit 1
            fi
            rm -f "$CONFIG_FILE"
            remove_system_service
            echo "[OK] Systemd service uninstalled and config cleared."
            echo "     系统服务已卸载，配置已清理。"
            exit 0
            ;;
        --uninstall)
            check_root
            do_uninstall
            exit $?
            ;;
        --install-service)
            check_root
            setup_system_service
            exit 0
            ;;
        -i|--install-completion)
            check_root
            install_completion
            exit 0
            ;;
        -a|--app|-r|--remove)
            # 这些是应用级命令，不在这里处理，返回给 parse_and_execute_command
            return 0
            ;;
        -*)
            # 未知选项
            echo "[ERROR] Unknown option / 未知选项: $1" >&2
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

# 解析全局参数（如 --cdn）

# 解析参数并执行应用级命令
parse_and_execute_command() {
    local COMMAND="mount"
    local APP_NAME=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--remove) COMMAND="unmount"; APP_NAME="$2"; shift 2 ;;
            -a|--app) APP_NAME="$2"; shift 2 ;;
            -l|--list) COMMAND="list"; shift ;;
            -d|--detail) COMMAND="detail"; shift ;;
            -*)
                echo "[ERROR] Unknown option / 未知选项: $1" >&2
                echo ""
                show_usage
                exit 1
                ;;
            *) APP_NAME="$1"; shift ;;
        esac
    done

    if [ -z "$APP_NAME" ] && [[ "$COMMAND" != "list" && "$COMMAND" != "detail" ]]; then
        show_usage
        prompt_install_completion
        exit 1
    fi

    if [[ "$COMMAND" == "mount" ]]; then
        [ ! -f "$NOTO_REG" ] && apt update && apt install -y fonts-noto-cjk
        if ! do_mount "$APP_NAME" "false"; then
            echo "[ERROR] App not found or no target fonts: $APP_NAME"
            echo "        未找到应用或未找到可替换字体。"
            prompt_install_completion
            exit 1
        fi
    elif [[ "$COMMAND" == "list" ]]; then
        list_mapped_apps
        exit 0
    elif [[ "$COMMAND" == "detail" ]]; then
        list_mapped_apps_detail
        exit 0
    else
        unmount_app "$APP_NAME"
    fi
}

# --- 主入口 ---

# 先从参数中提取 --cdn 全局参数
parse_global_params() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cdn)
                if [[ -z "$2" ]]; then
                    echo "[ERROR] --cdn requires a prefix argument"
                    echo "        --cdn 需要一个前缀参数"
                    echo ""
                    echo "Usage: $(basename "$0") --cdn <prefix> <command> [args]"
                    echo "Examples:"
                    echo "  $(basename "$0") --cdn https://raw.staticdn.net/ -a snap-store"
                    echo "  $(basename "$0") --cdn https://ghproxy.com/https://raw.githubusercontent.com/ -a snap-store"
                    exit 1
                fi
                RAW_CDN_PREFIX="$2"
                # 从 GITHUB_RAW_BASE 中提取 owner/repo/branch/path 部分并重建
                local repo_path="${GITHUB_RAW_BASE#https://raw.githubusercontent.com/}"
                GITHUB_RAW_BASE="${RAW_CDN_PREFIX}${repo_path}"
                GITHUB_RAW_LIB="${GITHUB_RAW_BASE}/lib"
                shift 2
                ;;
            *)
                # 不是全局参数，会退出并返回剩余的参数
                break
                ;;
        esac
    done
    # 输出剩余的参数（用于 eval 恢复）
    for arg in "$@"; do
        printf '%s\n' "$arg"
    done
}

main() {
    # 检查并自动安装补全（非 --startup 和 --install-completion 命令时执行）
    if [[ "${1:-}" != "--startup" && "${1:-}" != "-i" && "${1:-}" != "--install-completion" ]]; then
        auto_install_completion
    fi

    # 先解析全局参数（--cdn 等），然后处理剩余的命令
    local params=()
    mapfile -t params < <(parse_global_params "$@")
    set -- "${params[@]}"

    # 处理系统级命令（直接 exit）
    # 包括：--startup, -c, -l, -d, --remove-all, --uninstall-service, --uninstall, --install-service, -i
    if [[ $# -gt 0 ]]; then
        handle_system_commands "$@"
    fi

    # 如果没有参数，显示用法并退出（不需要 root 权限）
    if [[ $# -eq 0 ]]; then
        show_usage
        prompt_install_completion
        return 1
    fi

    # 到此处说明是交互模式，需要 root 权限
    check_root

    # 解析参数并执行应用级命令
    parse_and_execute_command "$@"
}
