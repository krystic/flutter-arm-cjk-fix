encode_config_value() {
    printf '%s' "$1" | base64 | tr -d '\n'
}

decode_config_value() {
    printf '%s' "$1" | base64 -d 2>/dev/null
}

get_non_snap_record_path() {
    local exe_path=$1
    local record_id
    record_id=$(printf '%s' "$exe_path" | sha256sum | awk '{print $1}')
    echo "$NON_SNAP_CONFIG_DIR/$record_id.conf"
}

read_non_snap_record() {
    local record_file=$1
    [[ -f "$record_file" ]] || return 1

    local format encoded_exe encoded_so encoded_backup original_version replacement_version original_sha replacement_sha
    IFS='|' read -r format encoded_exe encoded_so encoded_backup original_version replacement_version original_sha replacement_sha < "$record_file"
    [[ "$format" == "1" ]] || return 1

    NON_SNAP_EXE_PATH=$(decode_config_value "$encoded_exe") || return 1
    NON_SNAP_SO_PATH=$(decode_config_value "$encoded_so") || return 1
    NON_SNAP_BACKUP_PATH=$(decode_config_value "$encoded_backup") || return 1
    NON_SNAP_ORIGINAL_VERSION="$original_version"
    NON_SNAP_REPLACEMENT_VERSION="$replacement_version"
    NON_SNAP_ORIGINAL_SHA="$original_sha"
    NON_SNAP_REPLACEMENT_SHA="$replacement_sha"
}

write_non_snap_record() {
    local exe_path=$1
    local so_path=$2
    local backup_path=$3
    local original_version=$4
    local replacement_version=$5
    local original_sha=$6
    local replacement_sha=$7
    local record_file temp_file

    mkdir -p "$NON_SNAP_CONFIG_DIR"
    record_file=$(get_non_snap_record_path "$exe_path")
    temp_file="${record_file}.tmp.$$"

    printf '1|%s|%s|%s|%s|%s|%s|%s\n' \
        "$(encode_config_value "$exe_path")" \
        "$(encode_config_value "$so_path")" \
        "$(encode_config_value "$backup_path")" \
        "$original_version" "$replacement_version" \
        "$original_sha" "$replacement_sha" > "$temp_file" || {
            rm -f "$temp_file"
            return 1
        }
    chmod 600 "$temp_file"
    mv "$temp_file" "$record_file"
}

find_non_snap_record() {
    local target=$1
    local target_real=""
    [[ -e "$target" ]] && target_real=$(realpath "$target" 2>/dev/null || true)
    [[ -d "$NON_SNAP_CONFIG_DIR" ]] || return 1

    local record_file match=""
    for record_file in "$NON_SNAP_CONFIG_DIR"/*.conf; do
        [[ -f "$record_file" ]] || continue
        read_non_snap_record "$record_file" || continue
        if [[ "$target" == "$NON_SNAP_EXE_PATH" ||
              -n "$target_real" && "$target_real" == "$NON_SNAP_EXE_PATH" ||
              "$target" == "$(basename "$NON_SNAP_EXE_PATH")" ]]; then
            if [[ -n "$match" ]]; then
                echo "[ERROR] Multiple non-Snap records match '$target'; use the full executable path." >&2
                echo "        多个非 Snap 记录同名，请使用完整可执行文件路径。" >&2
                return 2
            fi
            match="$record_file"
        fi
    done
    [[ -n "$match" ]] || return 1
    echo "$match"
}

restore_non_snap_record() {
    local record_file=$1
    read_non_snap_record "$record_file" || {
        echo "[ERROR] Invalid non-Snap record: $record_file" >&2
        echo "        非 Snap 配置记录无效。" >&2
        return 1
    }

    if [[ ! -f "$NON_SNAP_BACKUP_PATH" ]]; then
        echo "[ERROR] Backup not found: $NON_SNAP_BACKUP_PATH" >&2
        echo "        原始 SO 备份不存在，已保留配置记录。" >&2
        return 1
    fi

    local backup_sha current_sha
    backup_sha=$(sha256sum "$NON_SNAP_BACKUP_PATH" | awk '{print $1}')
    if [[ "$backup_sha" != "$NON_SNAP_ORIGINAL_SHA" ]]; then
        echo "[ERROR] Backup checksum mismatch: $NON_SNAP_BACKUP_PATH" >&2
        echo "        备份已发生变化，为避免损坏应用，拒绝恢复。" >&2
        return 1
    fi

    if [[ ! -f "$NON_SNAP_SO_PATH" ]]; then
        echo "[ERROR] Current SO not found: $NON_SNAP_SO_PATH" >&2
        echo "        应用可能已升级或移动，已保留配置记录。" >&2
        return 1
    fi

    current_sha=$(sha256sum "$NON_SNAP_SO_PATH" | awk '{print $1}')
    if [[ "$current_sha" == "$NON_SNAP_ORIGINAL_SHA" ]]; then
        rm -f "$record_file" "$NON_SNAP_BACKUP_PATH"
        echo "[OK] [$(basename "$NON_SNAP_EXE_PATH")] Original SO is already restored."
        echo "     原始 SO 已经恢复，记录已清理。"
        return 0
    fi
    if [[ "$current_sha" != "$NON_SNAP_REPLACEMENT_SHA" ]]; then
        echo "[ERROR] Current SO was modified after repair: $NON_SNAP_SO_PATH" >&2
        echo "        应用可能已升级或被其他程序修改，为避免覆盖新文件，拒绝恢复。" >&2
        return 1
    fi

    cp --preserve=mode,ownership,timestamps "$NON_SNAP_BACKUP_PATH" "$NON_SNAP_SO_PATH" || return 1
    current_sha=$(sha256sum "$NON_SNAP_SO_PATH" | awk '{print $1}')
    if [[ "$current_sha" != "$NON_SNAP_ORIGINAL_SHA" ]]; then
        echo "[ERROR] Restored SO verification failed: $NON_SNAP_SO_PATH" >&2
        echo "        恢复后的 SO 校验失败，配置记录已保留。" >&2
        return 1
    fi

    rm -f "$record_file" "$NON_SNAP_BACKUP_PATH"
    echo "[OK] [$(basename "$NON_SNAP_EXE_PATH")] Original Flutter Engine restored."
    echo "     非 Snap 应用的原始 Flutter Engine 已恢复。"
}

# 从可执行文件获取 libflutter_linux_gtk.so 的路径
get_so_path_from_executable() {
    local exe_path=$1

    if [[ ! -x "$exe_path" ]]; then
        echo "[ERROR] Executable not found or not executable: $exe_path" >&2
        echo "        可执行文件不存在或无执行权限。" >&2
        return 1
    fi

    local so_path=$(ldd "$exe_path" 2>/dev/null | grep libflutter_linux_gtk.so | awk '{print $3}')

    if [[ -z "$so_path" ]]; then
        echo "[ERROR] libflutter_linux_gtk.so not found in executable dependencies" >&2
        echo "        未在可执行文件依赖中找到 libflutter_linux_gtk.so。" >&2
        return 1
    fi

    if [[ ! -f "$so_path" ]]; then
        echo "[ERROR] SO file path found but file doesn't exist: $so_path" >&2
        echo "        找到 SO 路径但文件不存在。" >&2
        return 1
    fi

    echo "$so_path"
    return 0
}

# 从 SO 文件提取 Flutter Engine hash（可能有多个）
handle_executable_app() {
    local exe_path
    exe_path=$(realpath "$1")

    echo ""
    echo "[INFO] Processing executable: $exe_path"
    echo "       正在处理可执行文件..."
    echo ""

    # 步骤 1: 获取 SO 文件路径
    echo "[1/5] Finding libflutter_linux_gtk.so..."
    echo "      正在查找 libflutter_linux_gtk.so..."
    local so_path
    so_path=$(get_so_path_from_executable "$exe_path") || return 1
    echo "      Found: $so_path"
    echo ""

    # 步骤 2: 提取 Engine hash
    echo "[2/5] Extracting Flutter Engine hash..."
    echo "      正在提取 Flutter Engine hash..."
    local engine_hashes
    engine_hashes=$(extract_engine_hash_from_so "$so_path") || return 1

    # 统计 hash 数量
    local hash_count=$(echo "$engine_hashes" | wc -l)
    echo "      Found $hash_count hash(es):"
    while IFS= read -r hash; do
        echo "        - $hash"
    done <<< "$engine_hashes"
    echo ""

    # 步骤 3: 更新 hash-version 缓存
    echo "[3/5] Updating hash-version cache..."
    echo "      正在更新 hash-version 对照表..."
    update_flutter_hash_version_cache || {
        echo "[WARN] Failed to update cache, will try with existing cache" >&2
        echo "       更新缓存失败，将使用现有缓存。" >&2
    }
    echo ""

    # 步骤 4: 查找对应的 Flutter 版本（逐个 hash 尝试）
    echo "[4/5] Finding Flutter version..."
    echo "      正在查找对应的 Flutter 版本..."
    local flutter_version=""
    local matched_hash=""

    while IFS= read -r hash; do
        [[ -z "$hash" ]] && continue
        echo "      Trying hash: $hash"
        flutter_version=$(find_flutter_version_by_hash "$hash" 2>/dev/null)
        if [[ $? -eq 0 && -n "$flutter_version" ]]; then
            matched_hash="$hash"
            break
        fi
    done <<< "$engine_hashes"

    if [[ -z "$flutter_version" ]]; then
        echo ""
        echo "[ERROR] Could not determine Flutter version for any hash" >&2
        echo "        无法为任何 hash 确定 Flutter 版本。" >&2
        echo ""
        echo "[INFO] Tried hashes:" >&2
        while IFS= read -r hash; do
            echo "       - $hash" >&2
        done <<< "$engine_hashes"
        echo ""
        echo "[INFO] You may need to compile Flutter Engine manually." >&2
        echo "       您可能需要手动编译 Flutter Engine。" >&2
        echo "       See: https://github.com/krystic/flutter-arm-cjk-fix/blob/main/README.md" >&2
        return 1
    fi

    echo "      Version: $flutter_version (matched hash: ${matched_hash:0:8}...)"
    echo ""

    if is_official_fontconfig_fixed_version "$flutter_version"; then
        print_official_fontconfig_fixed_message "$flutter_version"
        return 0
    fi

    # 步骤 5: 统一查找所有可用版本（精确+相似，本地+线上）
    echo "[5/5] Checking for available SO files..."
    echo "      正在检查可用的 SO 文件..."

    local all_versions
    all_versions=$(find_all_available_versions "$flutter_version")

    if [[ $? -ne 0 || -z "$all_versions" ]]; then
        echo ""
        echo "[ERROR] No compatible versions found" >&2
        echo "        未找到兼容版本。" >&2
        echo ""
        echo "[INFO] You need to compile Flutter Engine manually." >&2
        echo "       您需要手动编译 Flutter Engine。" >&2
        echo "       See: https://github.com/krystic/flutter-arm-cjk-fix/blob/main/README.md" >&2
        return 1
    fi

    # 检查是否有精确匹配
    local exact_match=""
    while IFS='|' read -r version source is_exact; do
        if [[ "$is_exact" == "true" ]]; then
            exact_match="$version"
            break
        fi
    done <<< "$all_versions"

    local replacement_so=""

    if [[ -n "$exact_match" ]]; then
        # 找到精确版本
        echo ""
        echo "[OK] Exact version found: $exact_match"
        echo "     找到精确版本：$exact_match"
        if ! replacement_so=$(download_so_file_if_needed "$exact_match") ||
            [[ ! -f "$replacement_so" ]]; then
            echo "[ERROR] Failed to prepare a verified SO file" >&2
            echo "        无法准备通过校验的 SO 文件。" >&2
            return 1
        fi
    else
        # 未找到精确版本，显示相似版本供选择
        echo ""
        echo "[WARN] No exact version found for $flutter_version" >&2
        echo "       未找到精确版本 $flutter_version" >&2
        echo ""
        echo "[INFO] Found compatible versions (same major.minor):" >&2
        echo "       找到兼容版本（相同主版本号）：" >&2


        local version_array=()
        local source_array=()
        while IFS='|' read -r ver source is_exact; do
            if [[ -n "$ver" ]]; then
                version_array+=("$ver")
                source_array+=("$source")
            fi
        done <<< "$all_versions"

        if [[ ${#version_array[@]} -eq 0 ]]; then
            echo ""
            echo "[ERROR] No compatible versions found" >&2
            echo "        未找到兼容版本。" >&2
            return 1
        fi

        local i
        echo
        for ((i=0; i<${#version_array[@]}; i++)); do
            local source_tag=""
            if [[ "${source_array[$i]}" == "local" ]]; then
                source_tag=" [本地/local]"
            else
                source_tag=" [线上/online]"
            fi
            echo "       [$((i+1))] ${version_array[$i]}${source_tag}" >&2
        done
        echo ""
        echo "Try one of these versions? (select number or 'n' to skip) [1]: "
        read -r -p "尝试这些版本吗？（输入编号或 'n' 跳过）[1]:" choice
        choice=${choice:-1}

        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#version_array[@]} )); then
            local selected_version="${version_array[$((choice-1))]}"
            if ! replacement_so=$(download_so_file_if_needed "$selected_version") ||
                [[ ! -f "$replacement_so" ]]; then
                echo "[ERROR] Failed to prepare a verified Flutter Engine $selected_version" >&2
                echo "        无法准备通过校验的 Flutter Engine 文件。" >&2
                return 1
            fi

            if [[ -f "$replacement_so" ]]; then
                echo ""
                echo "[OK] Using version: $selected_version (instead of $flutter_version)"
                echo "     使用版本：$selected_version（代替 $flutter_version）"
                echo ""
                echo "[WARN] This is not an exact match - test carefully!"
                echo "       这不是精确匹配 - 请仔细测试！"
            else
                echo "[ERROR] SO file not found: $replacement_so" >&2
                return 1
            fi
        else
            echo ""
            echo "[INFO] Skipped. You need to compile Flutter Engine manually." >&2
            echo "       已跳过。您需要手动编译 Flutter Engine。" >&2
            echo "       See: https://github.com/krystic/flutter-arm-cjk-fix/blob/main/README.md" >&2
            return 1
        fi
    fi

    # 执行替换（统一处理精确版本和相似版本）
    if [[ -n "$replacement_so" && -f "$replacement_so" ]]; then
        echo ""

        # 备份原 SO 文件
        local backup_path="${so_path}.bak"
        local existing_record
        existing_record=$(get_non_snap_record_path "$exe_path")
        if [[ -f "$existing_record" ]]; then
            echo "[ERROR] This executable is already managed: $exe_path" >&2
            echo "        该非 Snap 应用已有修复记录。请先使用 -r 恢复后再重新修复。" >&2
            return 1
        fi
        if [[ ! -f "$backup_path" ]]; then
            echo "[INFO] Creating backup..."
            echo "       正在创建备份..."
            cp --preserve=mode,ownership,timestamps "$so_path" "$backup_path" || {
                echo "[ERROR] Failed to create backup" >&2
                echo "        备份失败。" >&2
                return 1
            }
            echo "      Backup: $backup_path"
        else
            echo "[ERROR] Unmanaged backup already exists: $backup_path" >&2
            echo "        已存在但不受本工具记录管理的备份。为避免覆盖错误版本，操作已停止。" >&2
            return 1
        fi
        echo ""

        local original_sha replacement_sha replacement_version
        original_sha=$(sha256sum "$backup_path" | awk '{print $1}')
        replacement_sha=$(sha256sum "$replacement_so" | awk '{print $1}')
        replacement_version=$(basename "$replacement_so" | sed 's/^libflutter_linux_gtk\.so\.//')

        # 替换 SO 文件
        echo "[INFO] Replacing SO file..."
        echo "       正在替换 SO 文件..."
        if ! cp "$replacement_so" "$so_path" || ! chmod +x "$so_path"; then
            echo "[ERROR] Failed to replace SO file" >&2
            echo "        替换失败。" >&2
            cp --preserve=mode,ownership,timestamps "$backup_path" "$so_path" 2>/dev/null || true
            rm -f "$backup_path"
            return 1
        fi

        if ! write_non_snap_record "$exe_path" "$so_path" "$backup_path" \
            "$flutter_version" "$replacement_version" "$original_sha" "$replacement_sha"; then
            echo "[ERROR] Failed to save repair record; restoring original SO..." >&2
            echo "        保存修复记录失败，正在恢复原始 SO..." >&2
            if cp --preserve=mode,ownership,timestamps "$backup_path" "$so_path"; then
                rm -f "$backup_path"
            fi
            return 1
        fi

        echo ""
        echo "[OK] Flutter Engine replaced successfully!"
        echo "     Flutter Engine 已成功替换！"
        echo ""
        echo "[INFO] Original: $backup_path"
        echo "       Replacement: $so_path"
        echo ""
        echo "[INFO] To restore original:"
        echo "       恢复原文件："
        echo "       sudo flutter-font-fix -r $exe_path"

        return 0
    else
        echo "[ERROR] No SO file available for replacement" >&2
        return 1
    fi
}

# 尝试下载指定版本的 SO 文件（若本地不存在）
