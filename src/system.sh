check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "[ERROR] This operation requires sudo privileges."
        echo "        此操作需要 sudo 权限。"
        exit 1
    fi
}

# 列出自定义配置文件（排除官方 ubuntu.conf 和系统配置文件）
list_custom_config_files() {
    [[ ! -d "$CUSTOM_FONT_CONFIG_DIR" ]] && return 0
    local official_cfg="$(realpath -m "$CONFIG_FILE" 2>/dev/null || echo "$CONFIG_FILE")"
    for cfg in "$CUSTOM_FONT_CONFIG_DIR"/*.conf; do
        [[ ! -f "$cfg" ]] && continue
        grep -qE '^[^#].*\.(ttf|ttc)(\||$)' "$cfg" 2>/dev/null || continue
        local cfg_real="$(realpath -m "$cfg" 2>/dev/null || echo "$cfg")"
        # 跳过官方配置
        if [[ -n "$official_cfg" ]] && [[ "$cfg_real" == "$official_cfg" ]]; then
            continue
        fi
        echo "$cfg"
    done
}

# 自动创建或刷新系统级服务（官方与自定义模式都可自动启动）
setup_system_service() {
    local need_write=0
    if [ ! -f "$SERVICE_FILE" ]; then
        need_write=1
    elif ! grep -q "ConditionPathExists=$CONFIG_DIR" "$SERVICE_FILE" 2>/dev/null; then
        need_write=1
    fi
    if [ $need_write -eq 1 ]; then
        echo ""
        echo "[INFO] Creating systemd service..."
        echo "       正在创建系统服务..."
        cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Flutter Font Auto-Mount Service (System Level)
After=snapd.service
Requires=snapd.service
ConditionPathExists=$CONFIG_DIR

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 3
ExecStart=$SCRIPT_PATH --startup
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload 2>/dev/null
        systemctl enable flutter-font-fix.service 2>/dev/null
        echo "[OK] Systemd service enabled."
        echo "     系统服务已启用。"
    fi
}

# 删除 systemd 服务
remove_system_service() {
    if [ -f "$SERVICE_FILE" ]; then
        systemctl disable --now flutter-font-fix.service 2>/dev/null || true
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload 2>/dev/null || true
    fi
}

# 完全卸载脚本和所有配置
do_uninstall() {
    echo "[INFO] Uninstalling flutter-font-fix..."
    echo "       正在卸载"

    # 1. 卸载所有挂载和映射
    echo "[*] Unmounting all replacements..."
    echo "    卸载所有挂载和映射..."
    if ! do_unmount_all; then
        echo "[WARN] Some applications could not be restored; continuing uninstall." >&2
        echo "       部分应用无法恢复，将跳过这些应用并继续卸载。" >&2
    fi

    # 2. 删除 SO 库目录
    if [ -d "$SO_LIB_DIR" ]; then
        echo "[*] Removing SO library directory: $SO_LIB_DIR"
        echo "    删除 SO 库目录"
        rm -rf "$SO_LIB_DIR"
    fi

    # 3. 删除配置目录
    if [ -d "$CONFIG_DIR" ]; then
        echo "[*] Removing config directory: $CONFIG_DIR"
        echo "    删除配置目录"
        rm -rf "$CONFIG_DIR"
    fi

    # 4. 删除 bash completion 文件
    if [ -f "$COMPLETION_FILE" ]; then
        echo "[*] Removing bash completion: $COMPLETION_FILE"
        echo "    删除 bash 补全文件"
        rm -f "$COMPLETION_FILE"
    fi

    # 5. 停止并删除 systemd 服务
    echo "[*] Removing systemd service"
    echo "    删除 systemd 服务"
    remove_system_service

    # 6. 删除安装的模块
    if [[ -d "$INSTALLED_MODULE_DIR" ]]; then
        echo "[*] Removing modules: $INSTALLED_MODULE_DIR"
        echo "    删除程序模块"
        rm -rf "$INSTALLED_MODULE_DIR"
    fi

    # 7. 删除安装路径元数据与脚本本身
    rm -f "$INSTALL_PATHS_FILE"
    echo "[*] Removing script: $SCRIPT_PATH"
    echo "    删除脚本"
    rm -f "$SCRIPT_PATH"

    echo "[OK] flutter-font-fix uninstalled completely."
    echo "     flutter-font-fix 已完全卸载。"
}

do_unmount_all() {
    echo ""
    echo "[INFO] Removing all SO replacements and font mappings..."
    echo "       正在移除所有 SO 替换和字体映射..."

    if [ -f "$CONFIG_FILE" ]; then
        local apps=()
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local app
            if [[ "$line" == *"|"* ]]; then
                app="${line%%|*}"
            else
                app="$line"
            fi
            [[ -n "$app" ]] && apps+=("$app")
        done < "$CONFIG_FILE"

        for app in "${apps[@]}"; do
            # 卸载 SO 替换（如有）
            unmount_so_replacement "$app" 2>/dev/null || true

            # 卸载字体映射
            local SNAP_PATH="$SNAP_ROOT/$app/current/"
            local TARGET_DIR=$(find -L "$SNAP_PATH" -name "Ubuntu-R.ttf" -printf '%h\n' 2>/dev/null | head -n 1)
            if [ -n "$TARGET_DIR" ]; then
                for f in "$TARGET_DIR"/Ubuntu-*.ttf; do
                    umount -l "$f" 2>/dev/null
                done
                echo "[OK] [$app] Removed."
                echo "     映射已移除。"
            fi
        done
        : > "$CONFIG_FILE"
    else
        echo ""
        echo "[INFO] No apps configured."
        echo "       无已配置的应用。"
    fi

    # 卸载所有自定义字体
    for config_file in $(list_custom_config_files); do
        local app_name=$(basename "$config_file" .conf)
        unmount_custom_fonts_from_config "$app_name" >/dev/null 2>&1 || true
    done

    # 安全恢复所有非 Snap 应用。任何失败都会保留对应记录并阻止完全卸载。
    local restore_failed=0
    if [[ -d "$NON_SNAP_CONFIG_DIR" ]]; then
        local record_file
        for record_file in "$NON_SNAP_CONFIG_DIR"/*.conf; do
            [[ -f "$record_file" ]] || continue
            restore_non_snap_record "$record_file" || restore_failed=1
        done
    fi

    [[ $restore_failed -eq 0 ]]
}

install_completion() {
    check_root
    local FILE="$COMPLETION_FILE"
    cat > "$FILE" <<'EOF'
# bash completion for flutter-font-fix
_flutter_font_fix_completion() {
    local cur prev apps
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    case "$prev" in
        -a|--app|-c|--custom)
            if command -v snap >/dev/null 2>&1; then
                apps="$(snap list | awk 'NR>1{print $1}')"
                COMPREPLY=( $(compgen -W "$apps" -- "$cur") )
            fi
            ;;
        -e|--executable)
            # 对本地文件进行补全
            COMPREPLY=( $(compgen -f -- "$cur") )
            ;;
        -r|--remove)
            # 补全已映射的应用
            local config_dir="/etc/flutter-cjk"
            local config_file="$config_dir/ubuntu.conf"
            local mapped_apps=()

            # 读取官方配置
            if [[ -f "$config_file" ]]; then
                while IFS= read -r line; do
                    [[ -z "$line" ]] && continue
                    # 提取应用名（去掉 |method 后缀）
                    local app="${line%%|*}"
                    [[ -n "$app" ]] && mapped_apps+=("$app")
                done < "$config_file"
            fi

            # 读取自定义配置（排除官方 ubuntu.conf）
            if [[ -d "$config_dir" ]]; then
                local official_real="$(realpath -m "$config_file" 2>/dev/null)"
                for cfg in "$config_dir"/*.conf; do
                    [[ ! -f "$cfg" ]] && continue
                    grep -qE '^[^#].*\.(ttf|ttc)(\||$)' "$cfg" 2>/dev/null || continue
                    local cfg_real="$(realpath -m "$cfg" 2>/dev/null)"
                    # 跳过官方配置
                    [[ -n "$official_real" && "$cfg_real" == "$official_real" ]] && continue
                    mapped_apps+=("$(basename "$cfg" .conf)")
                done
            fi

            # 去重并转为空格分隔
            if [[ ${#mapped_apps[@]} -gt 0 ]]; then
                local unique_apps="$(printf '%s\n' "${mapped_apps[@]}" | sort -u | tr '\n' ' ')"
                COMPREPLY=( $(compgen -W "$unique_apps" -- "$cur") )
            fi
            ;;
    esac
}
complete -F _flutter_font_fix_completion flutter-font-fix.sh flutter-font-fix
EOF
    echo "[OK] Bash completion installed."
    echo "     补全已安装到：$FILE"
    # 尝试在当前 shell 下生效（如果可能）
    if [ -n "$BASH_VERSION" ] && [[ $- == *i* ]]; then
        . "$FILE" 2>/dev/null || true
        echo "[OK] Completion loaded into current shell."
        echo "     当前 shell 已加载补全。"
        echo ""
        echo "[INFO] Completion will be enabled automatically in new terminals."
        echo "       新终端将自动启用补全。"
    fi

    # 如果通过 sudo 调用，则为原始调用用户提供提示
    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "$(id -un)" ]; then
        USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        echo ""
        echo "[INFO] Installed for user: $SUDO_USER"
        echo "       已为用户安装补全。"
        echo ""
        echo "[INFO] To enable in current terminal, run:"
        echo "       若要在当前终端立即生效，请运行："
        echo "       source $FILE"
    fi
}

prompt_install_completion() {
    # 仅在交互式 shell 中提示；非交互式环境下输出安装建议而不阻塞
    if [[ $- != *i* ]]; then
        echo ""
        echo "[INFO] To enable Tab completion, run:"
        echo "       若要启用 Tab 自动补全，请运行："
        echo "       sudo \"$SCRIPT_PATH\" -i"
        return
    fi

    local reply
    echo "Install Tab completion now? [y/N]"
    read -r -p "现在安装 Tab 自动补全吗？[y/N] " reply
    case "$reply" in
        [Yy]*)
            if [[ $EUID -eq 0 ]]; then
                install_completion
            else
                echo ""
                echo "[INFO] Requires sudo privileges, installing..."
                echo "       需要 sudo 权限，正在安装..."
                sudo "$SCRIPT_PATH" -i
            fi
            ;;
        *)
            echo ""
            echo "[INFO] Installation cancelled."
            echo "       已取消安装。"
            ;;
    esac
}

# 获取 snap 应用的路径
get_snap_app_path() {
    local app=$1
    local snap_path="$SNAP_ROOT/$app/current"
    [ -d "$snap_path" ] && echo "$snap_path" && return 0
    return 1
}

# 获取应用内所有 ttf/ttc 字体文件（包括子目录和符号链接）
get_fonts_in_app() {
    local app_path=$1
    find -L "$app_path" -type f \( -iname "*.ttf" -o -iname "*.ttc" \) 2>/dev/null | sort
}

list_mapped_apps() {
    declare -A seen=()
    echo ""
    echo "[INFO] Apps with mappings:"
    echo "       已有映射的应用："

    if [[ -f "$CONFIG_FILE" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local app
            if [[ "$line" == *"|"* ]]; then
                app="${line%%|*}"
            else
                app="$line"
            fi
            seen["$app"]=1
        done < "$CONFIG_FILE"
    fi

    for cfg in $(list_custom_config_files); do
        local app_name=$(basename "$cfg" .conf)
        seen["$app_name"]=1
    done

    if [[ -d "$NON_SNAP_CONFIG_DIR" ]]; then
        local record_file
        for record_file in "$NON_SNAP_CONFIG_DIR"/*.conf; do
            [[ -f "$record_file" ]] || continue
            if read_non_snap_record "$record_file"; then
                seen["$NON_SNAP_EXE_PATH"]=1
            fi
        done
    fi

    if [[ ${#seen[@]} -eq 0 ]]; then
        echo "  (none) / 无"
        return 0
    fi

    for app in "${!seen[@]}"; do
        echo "  - $app"
    done | sort
}

list_mapped_apps_detail() {
    declare -A has_official=()
    declare -A official_method=()
    declare -A has_custom=()
    declare -A non_snap_record=()

    if [[ -f "$CONFIG_FILE" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local app method
            if [[ "$line" == *"|"* ]]; then
                app="${line%%|*}"
                method="${line#*|}"
            else
                # 兼容旧格式（只有应用名）
                app="$line"
                method="unknown"
            fi
            has_official["$app"]=1
            official_method["$app"]="$method"
        done < "$CONFIG_FILE"
    fi

    for cfg in $(list_custom_config_files); do
        local app_name=$(basename "$cfg" .conf)
        has_custom["$app_name"]=1
    done

    if [[ -d "$NON_SNAP_CONFIG_DIR" ]]; then
        local record_file
        for record_file in "$NON_SNAP_CONFIG_DIR"/*.conf; do
            [[ -f "$record_file" ]] || continue
            if read_non_snap_record "$record_file"; then
                non_snap_record["$NON_SNAP_EXE_PATH"]="$record_file"
            fi
        done
    fi

    declare -A all=()
    for k in "${!has_official[@]}"; do all[$k]=1; done
    for k in "${!has_custom[@]}"; do all[$k]=1; done
    for k in "${!non_snap_record[@]}"; do all[$k]=1; done

    echo ""
    echo "[INFO] Detailed mappings:"
    echo "       详细映射列表："
    if [[ ${#all[@]} -eq 0 ]]; then
        echo "  (none) / 无"
        return 0
    fi

    for app in "${!all[@]}"; do
        local modes=()
        local method_note=""

        if [[ -n "${has_official[$app]}" ]]; then
            local method="${official_method[$app]}"
            case "$method" in
                so)
                    method_note=" - SO Engine Replacement (Root Fix) / SO 引擎替换（根治）"
                    ;;
                font)
                    method_note=" - Font Mapping (CJK Workaround) / 字体映射（CJK 临时）"
                    ;;
                unknown)
                    method_note=" - Method Unknown / 方法未知"
                    ;;
            esac
            modes+=("ubuntu/官方")
        fi

        [[ -n "${has_custom[$app]}" ]] && modes+=("custom/自定义")
        [[ -n "${non_snap_record[$app]}" ]] && modes+=("non-snap/非Snap")

        echo "- $app [${modes[*]}]${method_note}"

        if [[ -n "${non_snap_record[$app]}" ]] &&
           read_non_snap_record "${non_snap_record[$app]}"; then
            local state="modified/已被外部修改"
            if [[ -f "$NON_SNAP_SO_PATH" ]]; then
                local current_sha
                current_sha=$(sha256sum "$NON_SNAP_SO_PATH" | awk '{print $1}')
                if [[ "$current_sha" == "$NON_SNAP_REPLACEMENT_SHA" ]]; then
                    state="active/修复生效"
                elif [[ "$current_sha" == "$NON_SNAP_ORIGINAL_SHA" ]]; then
                    state="restored/已恢复"
                fi
            else
                state="missing/文件不存在"
            fi
            echo "    • Executable / 可执行文件: $NON_SNAP_EXE_PATH"
            echo "    • Engine SO: $NON_SNAP_SO_PATH"
            echo "    • Flutter: $NON_SNAP_ORIGINAL_VERSION -> $NON_SNAP_REPLACEMENT_VERSION"
            echo "    • Backup / 备份: $NON_SNAP_BACKUP_PATH"
            echo "    • State / 状态: $state"
        fi

        if [[ -n "${has_custom[$app]}" ]]; then
            local cfg="$CUSTOM_FONT_CONFIG_DIR/${app}.conf"
            if [[ -f "$cfg" ]]; then
                while IFS= read -r line; do
                    [[ "$line" =~ ^#.*$ ]] && continue
                    [[ -z "$line" ]] && continue
                    local font_path source_path
                    if [[ "$line" == *"|"* ]]; then
                        font_path="${line%%|*}"
                        source_path="${line#*|}"
                    else
                        font_path="$line"; source_path="$NOTO_REG"
                    fi
                    echo "    • $(basename "$font_path")  <=  $(basename "$source_path")"
                done < "$cfg"
            fi
        fi
    done
}

# 判断应用是否在官方修复列表中
app_in_official_config() {
    local app=$1
    # 兼容新格式 (app|method) 和旧格式 (app)
    grep -qE "^$app(\||$)" "$CONFIG_FILE" 2>/dev/null
}

# 卸载自定义字体（从配置文件中读取）
unmount_custom_fonts_from_config() {
    local app=$1
    local config_file="$CUSTOM_FONT_CONFIG_DIR/${app}.conf"

    # 避免误操作官方配置
    if [[ -f "$CONFIG_FILE" ]]; then
        local config_real="$(realpath -m "$config_file" 2>/dev/null || echo "$config_file")"
        local official_real="$(realpath -m "$CONFIG_FILE" 2>/dev/null || echo "$CONFIG_FILE")"
        if [[ "$config_real" == "$official_real" ]]; then
            return 1
        fi
    fi

    [[ ! -f "$config_file" ]] && return 1

    echo ""
    echo "[INFO] Unmounting custom fonts for: $app"
    echo "       正在卸载自定义字体..."

    local count=0
    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue

        local font_path=${line%%|*}
        [[ -z "$font_path" ]] && continue
        if umount -l "$font_path" 2>/dev/null; then
            ((count++))
        fi
    done < "$config_file"

    rm -f "$config_file"

    if [[ $count -gt 0 ]]; then
        echo "[OK] Custom fonts unmounted for: $app"
        echo "     自定义字体已卸载。"
        return 0
    fi
    echo "[WARN] No custom fonts found for: $app"
    echo "      未找到自定义字体。"
    return 1
}

# 统一卸载：官方映射 + 自定义映射
unmount_app() {
    local app=$1
    local found=0

    if app_in_official_config "$app"; then
        do_unmount "$app"
        found=1
    fi

    if unmount_custom_fonts_from_config "$app"; then
        found=1
    fi

    local non_snap_record
    non_snap_record=$(find_non_snap_record "$app")
    local find_record_status=$?
    if [[ $find_record_status -eq 2 ]]; then
        return 1
    fi
    if [[ -n "$non_snap_record" ]]; then
        if restore_non_snap_record "$non_snap_record"; then
            found=1
        else
            return 1
        fi
    fi

    if [[ $found -eq 0 ]]; then
        echo "[WARN] No mappings found for: $app"
        echo "       未在官方或自定义配置中找到该应用。"
        return 1
    fi
    return 0
}

# 交互式选择并保存字体配置
do_custom_fonts() {
    local app=$1

    # 检查是否已在官方配置中
    if app_in_official_config "$app"; then
        echo ""
        echo "[WARN] App '$app' is already in official mode."
        echo "       应用已在官方模式中配置。"
        echo ""
        echo "Remove from official config and use custom fonts? [y/N]"
        read -r -p "从官方配置移除并使用自定义字体？[y/N] " choice
        case "$choice" in
            [Yy]*)
                do_unmount "$app"
                echo "[OK] Removed from official config."
                echo "     已从官方配置移除。"
                ;;
            *)
                echo "[INFO] Keeping official config, operation cancelled / 保留官方配置，操作已取消"
                return 1
                ;;
        esac
    fi

    local snap_path

    snap_path=$(get_snap_app_path "$app") || {
        echo ""
        echo "[ERROR] App not found or not a Snap package: $app"
        echo "        未找到应用或非 Snap 包。"
        return 1
    }

    echo ""
    echo "[INFO] Searching for font files in:"
    echo "       $snap_path"

    # 收集所有字体文件
    local fonts=()
    while IFS= read -r font_file; do
        fonts+=("$font_file")
    done < <(get_fonts_in_app "$snap_path")

    if [[ ${#fonts[@]} -eq 0 ]]; then
        echo ""
        echo "[ERROR] No font files found in app: $app"
        echo "        未在应用中找到字体文件。"
        return 1
    fi

    echo ""
    echo "[OK] Found ${#fonts[@]} font file(s):"
    echo "     找到 ${#fonts[@]} 个字体文件："
    echo ""

    # 显示菜单
    local i
    for ((i=0; i<${#fonts[@]}; i++)); do
        local font="${fonts[$i]}"
        local font_name=$(basename "$font")
        echo "  [$((i+1))] $font_name"
    done

    echo ""
    echo "[INFO] Enter font numbers separated by commas (e.g., 1,3,5), or 'a' for all."
    echo "       输入字体编号（逗号分隔，例如 1,3,5），或输入 'a' 选择全部。"
    read -r -p "> " selection

    # 解析选择
    local selected_fonts=()
    if [[ "$selection" == "a" || "$selection" == "A" ]]; then
        selected_fonts=("${fonts[@]}")
    else
        # 用逗号分割
        IFS=',' read -ra nums <<< "$selection"
        for num in "${nums[@]}"; do
            # 去除空格
            num=$(echo "$num" | tr -d ' ')
            if [[ $num =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#fonts[@]} )); then
                selected_fonts+=("${fonts[$((num-1))]}")
            fi
        done
    fi

    if [[ ${#selected_fonts[@]} -eq 0 ]]; then
        echo ""
        echo "[WARN] No fonts selected."
        echo "       未选择任何字体。"
        return 1
    fi

    # Noto 目标路径映射
    local noto_map=("$NOTO_REG" "$NOTO_BOLD" "$NOTO_LIGHT" "$NOTO_MEDIUM")
    local noto_names=("Regular/常规" "Bold/粗体" "Light/细体" "Medium/中等")

    # 逐个为每个字体选择目标 Noto 字体
    echo ""
    echo "[INFO] Now select target Noto font for each selected font."
    echo "       现在为每个选中的字体选择目标 Noto 字体。"
    echo ""

    local pairs=()
    for font in "${selected_fonts[@]}"; do
        local font_name=$(basename "$font")
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Font: $font_name"
        echo "字体：$font_name"
        echo ""
        echo "Choose target Noto font:"
        echo "选择目标 Noto 字体："
        for ((i=0; i<${#noto_map[@]}; i++)); do
            echo "  [$((i+1))] ${noto_names[$i]}"
        done
        echo ""

        local choice=""
        while true; do
            read -r -p "Enter number (1-4): " choice
            if [[ "$choice" =~ ^[1-4]$ ]]; then
                break
            else
                echo "[ERROR] Invalid input, please enter 1-4."
                echo "        输入无效，请输入 1-4。"
            fi
        done

        local target="${noto_map[$((choice-1))]}"
        pairs+=("$font|$target")
        echo "[OK] $font_name -> ${noto_names[$((choice-1))]}"
        echo ""
    done

    # 保存配置
    mkdir -p "$CUSTOM_FONT_CONFIG_DIR"
    local config_file="$CUSTOM_FONT_CONFIG_DIR/${app}.conf"
    {
        echo "# Flutter Font Fix - Custom Font Configuration"
        echo "# App: $app"
        echo "# Generated: $(date)"
        echo ""
        for pair in "${pairs[@]}"; do
            echo "$pair"
        done
    } > "$config_file"

    # 确保系统服务存在，以便自定义模式也能随系统启动自动挂载
    mkdir -p "$CONFIG_DIR"
    setup_system_service

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[OK] Configuration saved."
    echo "     配置已保存到：$config_file"
    echo ""
    echo "[INFO] Font mappings:"
    echo "       字体映射关系："
    for pair in "${pairs[@]}"; do
        local font_path="${pair%%|*}"
        local target_path="${pair#*|}"
        echo "  • $(basename "$font_path") -> $(basename "$target_path")"
    done
    echo ""
    echo "[INFO] Applying custom font mounts..."
    echo "       正在应用自定义字体挂载..."
    if mount_custom_fonts_from_config "$app"; then
        echo "[OK] Custom fonts mounted for: $app"
        echo "     自定义字体已挂载。"
    else
        echo "[WARN] No fonts mounted, please check configuration."
        echo "       未能挂载，请检查配置。"
    fi

    return 0
}

# 从配置文件挂载自定义字体
mount_custom_fonts_from_config() {
    local app=$1
    local config_file="$CUSTOM_FONT_CONFIG_DIR/${app}.conf"

    if [[ ! -f "$config_file" ]]; then
        return 1
    fi

    echo ""
    echo "[INFO] Loading custom fonts for: $app"
    echo "       正在加载自定义字体..."

    local mounted_count=0
    local failed_count=0

    while IFS= read -r line; do
        # 跳过注释和空行
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue

        local font_path
        local source_path

        if [[ "$line" == *"|"* ]]; then
            font_path="${line%%|*}"
            source_path="${line#*|}"
        else
            font_path="$line"
            source_path="$NOTO_REG"  # 兼容旧格式，默认映射到 Regular
        fi

        if [[ ! -f "$font_path" ]]; then
            ((failed_count++))
            continue
        fi
        if [[ ! -f "$source_path" ]]; then
            ((failed_count++))
            continue
        fi

        local font_name=$(basename "$font_path")
        if mount --bind "$source_path" "$font_path" 2>/dev/null; then
            ((mounted_count++))
            echo "[OK] Mounted: $font_name -> $(basename "$source_path")"
            echo "     已挂载：$font_name -> $(basename "$source_path")"
        else
            ((failed_count++))
        fi
    done < "$config_file"

    [[ $mounted_count -gt 0 ]] && return 0
    return 1
}

# 在 --startup 时遍历所有应用配置并挂载
mount_all_custom_fonts() {
    if [[ ! -d "$CUSTOM_FONT_CONFIG_DIR" ]]; then
        return 0
    fi

    echo ""
    echo "[INFO] Loading all custom font configurations..."
    echo "       正在加载所有自定义字体配置..."

    local found=0
    for config_file in $(list_custom_config_files); do
        local app_name=$(basename "$config_file" .conf)
        if mount_custom_fonts_from_config "$app_name"; then
            found=1
        fi
    done

    if [[ $found -eq 1 ]]; then
        echo "[OK] Custom font loading completed."
        echo "     自定义字体加载完成。"
    fi

    return 0
}

# --- 主逻辑 ---

# 显示用法说明
