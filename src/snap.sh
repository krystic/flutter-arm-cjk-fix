mount_so_replacement() {
    local app=$1
    local so_file=$2

    local snap_path="$SNAP_ROOT/$app/current"
    [[ ! -d "$snap_path" ]] && return 1

    # 确保 SO 文件有执行权限
    [[ -f "$so_file" ]] && chmod +x "$so_file" 2>/dev/null || true

    # 查找应用中的 libflutter_linux_gtk.so
    local target_so=$(find -L "$snap_path" -name "libflutter_linux_gtk.so*" | head -n1)
    [[ -z "$target_so" ]] && {
        echo "[ERROR] libflutter_linux_gtk.so not found in app: $app"
        return 1
    }

    echo ""
    echo "[INFO] Mounting Flutter Engine replacement..."
    echo "       正在挂载 Flutter 引擎替换文件..."
    echo "       Source: $(basename "$so_file") (size: $(du -h "$so_file" | cut -f1))"
    echo "       Target: $target_so"

    # 先卸载可能存在的映射
    umount -l "$target_so" 2>/dev/null || true

    # 挂载新的 SO 文件
    if mount --bind "$so_file" "$target_so" 2>/dev/null; then
        echo
        echo "[OK] Mounted successfully"
        echo "     挂载成功。"
        return 0
    else
        echo
        echo "[ERROR] Failed to mount SO file replacement"
        echo "        SO 文件替换挂载失败。"
        return 1
    fi
}

# 卸载 SO 文件替换
unmount_so_replacement() {
    local app=$1
    local unmounted=0

    # Try to find and unmount SO mount points for this app
    # Handle both /snap/$app/current and /snap/$app/* paths
    while IFS= read -r mount_point; do
        [[ -z "$mount_point" ]] && continue
        if umount -l "$mount_point" 2>/dev/null; then
            ((unmounted++))
            echo "[OK] [$app] Unmounted: $(basename "$mount_point")"
        fi
    done < <(mount -l 2>/dev/null | grep -E "^/.* on $SNAP_ROOT/$app/.*/.*libflutter_linux_gtk\.so" | awk '{print $3}')

    if [[ $unmounted -gt 0 ]]; then
        echo "     SO 文件替换已卸载。"
        return 0
    fi
    return 1
}

do_mount() {
    local app=$1
    local is_startup=$2

    # 检查冲突：是否已有自定义配置
    local custom_conf="$CUSTOM_FONT_CONFIG_DIR/${app}.conf"
    if [[ "$is_startup" == "false" ]] && [[ -f "$custom_conf" ]]; then
        local custom_real="$(realpath -m "$custom_conf" 2>/dev/null || echo "$custom_conf")"
        local official_real="$(realpath -m "$CONFIG_FILE" 2>/dev/null || echo "$CONFIG_FILE")"
        if [[ "$custom_real" != "$official_real" ]]; then
            echo ""
            echo "[WARN] App '$app' already has custom font configuration."
            echo "       应用已有自定义字体配置。"
            echo ""
            echo "Remove custom config and use official mapping? [y/N]"
            read -r -p "移除自定义配置并使用官方映射？[y/N] " choice
            case "$choice" in
                [Yy]*)
                    unmount_custom_fonts_from_config "$app" >/dev/null 2>&1
                    echo "[OK] Custom config removed."
                    echo "     自定义配置已移除。"
                    ;;
                *)
                    echo "[INFO] Operation cancelled."
                    echo "       操作已取消。"
                    return 1
                    ;;
            esac
        fi
    fi

    local snap_path="$SNAP_ROOT/$app/current/"
    if [ ! -d "$snap_path" ]; then
        echo "[ERROR] Snap app not found: $app"
        echo "        未找到 Snap 应用。"
        return 1
    fi

    # === 优先尝试 SO 文件替换（根治方案）===
    echo ""
    echo "[INFO] Checking for Flutter Engine SO replacement..."
    echo "       正在检查 Flutter 引擎 SO 替换文件..."

    # 使用统一的 SO hash 检测版本
    local flutter_version=$(detect_flutter_version_from_so "$snap_path")

    if [[ -n "$flutter_version" ]]; then
        echo "       Detected Flutter version: $flutter_version"
        echo "       检测到 Flutter 版本：$flutter_version"
        echo ""

        if is_official_fontconfig_fixed_version "$flutter_version"; then
            print_official_fontconfig_fixed_message "$flutter_version"
            return 0
        fi

        # 统一查找所有可用版本（精确+相似，本地+线上）
        echo "[INFO] Checking for available SO files..."
        echo "       正在检查可用的 SO 文件..."

        local all_versions
        all_versions=$(find_all_available_versions "$flutter_version")

        if [[ $? -eq 0 && -n "$all_versions" ]]; then
            # 检查是否有精确匹配
            local exact_match=""
            while IFS='|' read -r version source is_exact; do
                if [[ "$is_exact" == "true" ]]; then
                    exact_match="$version"
                    break
                fi
            done <<< "$all_versions"

            local so_file=""

            if [[ -n "$exact_match" ]]; then
                # 找到精确版本
                echo ""
                echo "[OK] Exact version found: $exact_match"
                echo "     找到精确版本：$exact_match"
                if ! so_file=$(download_so_file_if_needed "$exact_match") ||
                    [[ ! -f "$so_file" ]]; then
                    echo "[ERROR] Failed to prepare a verified SO file" >&2
                    echo "        无法准备通过校验的 SO 文件。" >&2
                    so_file=""
                fi
            else
                # -a 模式不使用相似版本，直接跳过
                echo ""
                echo "[WARN] No exact version found for $flutter_version" >&2
                echo "       未找到精确版本 $flutter_version" >&2
            fi

            # 如果找到了 SO 文件，执行挂载
            if [[ -n "$so_file" && -f "$so_file" ]]; then
                echo ""
                echo "[INFO] Found matching SO file!"
                echo "       找到匹配的 SO 文件！"
                echo "       SO file: $(basename "$so_file")"

                if mount_so_replacement "$app" "$so_file"; then
                    if [[ "$is_startup" == "false" ]]; then
                        mkdir -p "$CONFIG_DIR"
                        # 保存配置：app|so （标记使用 SO 替换）
                        sed -i "/^$app|/d" "$CONFIG_FILE" 2>/dev/null
                        sed -i "/^$app$/d" "$CONFIG_FILE" 2>/dev/null
                        echo "$app|so" >> "$CONFIG_FILE"
                        setup_system_service
                    fi
                    echo ""
                    echo "[OK] [$app] Flutter Engine replaced with $(basename "$so_file")"
                    echo "     Flutter 引擎已替换，字体问题已根治。"
                    return 0
                fi
            fi
        fi

        # 未找到任何可用版本
        echo ""
        echo "[WARN] No compatible SO file found for Flutter $flutter_version"
        echo "       未找到 Flutter $flutter_version 的兼容 SO 文件。"
        echo ""
        echo "[INFO] You can compile it yourself following:"
        echo "       您可以按照以下文档自行编译："
        echo "       https://github.com/krystic/flutter-arm-cjk-fix/blob/main/README.md"
        echo ""
    else
        echo ""
        echo "[WARN] Could not detect Flutter version from SO file"
        echo "       无法从 SO 文件检测 Flutter 版本"
    fi

    # 没有找到 SO 文件或自动检测失败
    if [[ "$is_startup" == "false" ]]; then
        echo "[INFO] Falling back to font mapping method..."
        echo "       回退到字体映射方法..."
    fi

    # === 字体映射方案（兜底） ===
    local target_dir=$(find -L "$snap_path" -name "Ubuntu-R.ttf" -printf '%h\n' | head -n 1)
    if [ -z "$target_dir" ]; then
        echo "[ERROR] No target font files found in app: $app"
        echo "        未在应用中找到目标字体文件。"
        return 1
    fi

    declare -A map=(
        ["Ubuntu-R.ttf"]="$NOTO_REG"   ["Ubuntu-RI.ttf"]="$NOTO_REG"
        ["Ubuntu-L.ttf"]="$NOTO_LIGHT" ["Ubuntu-LI.ttf"]="$NOTO_LIGHT"
        ["Ubuntu-M.ttf"]="$NOTO_MEDIUM" ["Ubuntu-MI.ttf"]="$NOTO_MEDIUM"
        ["Ubuntu-B.ttf"]="$NOTO_BOLD"  ["Ubuntu-BI.ttf"]="$NOTO_BOLD"
    )

    local mounted_count=0
    for ttf in "${!map[@]}"; do
        if [ -f "$target_dir/$ttf" ]; then
            umount -l "$target_dir/$ttf" 2>/dev/null
            if mount --bind "${map[$ttf]}" "$target_dir/$ttf" 2>/dev/null; then
                ((mounted_count++))
            fi
        fi
    done

    if [[ $mounted_count -eq 0 ]]; then
        echo "[ERROR] Failed to mount fonts for: $app"
        echo "        挂载字体失败。"
        return 1
    fi

    if [[ "$is_startup" == "false" ]]; then
        mkdir -p "$CONFIG_DIR"
        # 保存配置：app|font （标记使用字体映射）
        sed -i "/^$app|/d" "$CONFIG_FILE" 2>/dev/null
        sed -i "/^$app$/d" "$CONFIG_FILE" 2>/dev/null
        echo "$app|font" >> "$CONFIG_FILE"
        setup_system_service
    fi
    echo
    echo "[OK] [$app] Font mapping applied (workaround)."
    echo "     字体映射已应用（临时方案）。"
}

do_unmount() {
    local app=$1
    local snap_path="$SNAP_ROOT/$app/current/"

    # 尝试卸载 SO 文件替换
    unmount_so_replacement "$app"

    # 尝试卸载字体映射
    local target_dir=$(find -L "$snap_path" -name "Ubuntu-R.ttf" -printf '%h\n' | head -n 1)
    if [ -n "$target_dir" ]; then
        for f in "$target_dir"/Ubuntu-*.ttf; do
            umount -l "$f" 2>/dev/null
        done
    fi

    # 删除配置：匹配 app|method（新格式）或 app（旧格式）
    if [ -f "$CONFIG_FILE" ]; then
        sed -i "/^$app|/d; /^$app$/d" "$CONFIG_FILE" 2>/dev/null
    fi
    echo "[OK] [$app] Mapping removed."
    echo "     映射已移除。"
}
