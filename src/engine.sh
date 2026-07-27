detect_flutter_version_from_so() {
    local app_path=$1
    
    # 1. 查找 libflutter_linux_gtk.so
    local so_path=$(find -L "$app_path" -name "libflutter_linux_gtk.so*" 2>/dev/null | head -n1)
    if [[ -z "$so_path" || ! -f "$so_path" ]]; then
        return 1
    fi
    
    # 2. 提取 hash
    local engine_hashes
    engine_hashes=$(extract_engine_hash_from_so "$so_path") || return 1
    
    # 3. 更新 hash-version 缓存
    update_flutter_hash_version_cache 2>/dev/null || true
    
    # 4. 查找匹配的版本
    local flutter_version=""
    
    while IFS= read -r hash; do
        [[ -z "$hash" ]] && continue
        flutter_version=$(find_flutter_version_by_hash "$hash" 2>/dev/null)
        if [[ $? -eq 0 && -n "$flutter_version" ]]; then
            echo "$flutter_version"
            return 0
        fi
    done <<< "$engine_hashes"
    
    return 1
}

# --- 非 Snap 应用支持函数 ---

extract_engine_hash_from_so() {
    local so_path=$1
    
    if [[ ! -f "$so_path" ]]; then
        echo "[ERROR] SO file not found: $so_path" >&2
        return 1
    fi
    
    local hashes=$(strings "$so_path" 2>/dev/null | grep -E "^[0-9a-f]{40}$")
    
    if [[ -z "$hashes" ]]; then
        echo "[ERROR] Could not extract engine hash from SO file" >&2
        echo "        无法从 SO 文件提取引擎 hash。" >&2
        return 1
    fi
    
    echo "$hashes"
    return 0
}

# 生成或更新 Flutter hash-version 对照表缓存
update_flutter_hash_version_cache() {
    mkdir -p "$CONFIG_DIR"
    
    # 如果缓存已存在且不是很旧（7天内），直接返回
    if [[ -f "$FLUTTER_HASH_VERSION_CACHE" ]]; then
        local cache_age=$(($(date +%s) - $(stat -c %Y "$FLUTTER_HASH_VERSION_CACHE" 2>/dev/null || echo 0)))
        if [[ $cache_age -lt 604800 ]]; then
            return 0
        fi
    fi
    
    echo "[INFO] Updating Flutter hash-version cache from GitHub..." >&2
    echo "       正在从 GitHub 更新 Flutter hash-version 对照表..." >&2
    
    # 使用与 test.hash.sh 相同的逻辑
    local hash_url="$GITHUB_RAW_BASE/flutter.engine.hash.version"

    curl -sfL "$hash_url" -o "$FLUTTER_HASH_VERSION_CACHE"
    # echo "ddf47dd3ff96dbde6d9c614db0d7f019d7c7a2b7 | 3.35.3" >> "$FLUTTER_HASH_VERSION_CACHE"

    echo "[OK] Cache updated: $FLUTTER_HASH_VERSION_CACHE" >&2
    echo "     缓存已更新。" >&2
    return 0
}

# 从 hash 查找对应的 Flutter 版本
find_flutter_version_by_hash() {
    local hash=$1
    
    # 确保缓存存在
    if [[ ! -f "$FLUTTER_HASH_VERSION_CACHE" ]]; then
        update_flutter_hash_version_cache || return 1
    fi
    
    # 查找匹配的版本（可能有多个）
    local versions=$(grep "^$hash" "$FLUTTER_HASH_VERSION_CACHE" 2>/dev/null | awk -F' \\| ' '{print $2}')
    
    if [[ -z "$versions" ]]; then
        echo "[WARN] No matching Flutter version found for hash: $hash" >&2
        echo "       未找到匹配该 hash 的 Flutter 版本。" >&2
        return 1
    fi
    
    # 如果有多个版本，显示所有并让用户选择
    local version_array=()
    while IFS= read -r ver; do
        [[ -n "$ver" ]] && version_array+=("$ver")
    done <<< "$versions"
    
    if [[ ${#version_array[@]} -eq 0 ]]; then
        return 1
    elif [[ ${#version_array[@]} -eq 1 ]]; then
        echo "${version_array[0]}"
        return 0
    else
        echo "[INFO] Multiple versions found for hash $hash:" >&2
        echo "       找到多个匹配的版本：" >&2
        local i
        for ((i=0; i<${#version_array[@]}; i++)); do
            echo "  [$((i+1))] ${version_array[$i]}" >&2
        done
        echo "" >&2
        read -r -p "Select version number (选择版本编号) [1]: " choice
        choice=${choice:-1}
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#version_array[@]} )); then
            echo "${version_array[$((choice-1))]}"
            return 0
        else
            echo "[ERROR] Invalid selection" >&2
            echo "        选择无效。" >&2
            return 1
        fi
    fi
}

verify_so_file_with_manifest() {
    local so_file=$1
    local checksum_file=$2
    local so_name expected_hash actual_hash
    so_name=$(basename "$so_file")

    [[ -f "$so_file" && -f "$checksum_file" ]] || return 1
    expected_hash=$(awk -v file="$so_name" '$2 == file {print $1; exit}' "$checksum_file")
    actual_hash=$(sha256sum "$so_file" | awk '{print $1}')
    [[ "$expected_hash" =~ ^[0-9a-f]{64}$ && "$actual_hash" == "$expected_hash" ]]
}

download_checksum_manifest() {
    local checksum_file=$1
    local temp_checksum="${checksum_file}.tmp.$$"
    rm -f "$temp_checksum"

    if ! curl -fsSL "$GITHUB_RAW_LIB/SHA256SUMS" -o "$temp_checksum"; then
        rm -f "$temp_checksum"
        return 1
    fi
    mv "$temp_checksum" "$checksum_file"
}

download_so_file_if_needed() {
    local flutter_version=$1
    local so_name="libflutter_linux_gtk.so.$flutter_version"
    local so_file="$SO_LIB_DIR/$so_name"
    local checksum_file="$SO_LIB_DIR/SHA256SUMS"

    mkdir -p "$SO_LIB_DIR"

    # 任何已有缓存都必须具备清单并通过校验。旧安装缺少清单时在线补齐；
    # 禁用下载时则 fail closed，绝不绕过验证。
    if [[ -f "$so_file" ]]; then
        if [[ ! -f "$checksum_file" ]]; then
            if [[ "${FLUTTER_CJK_DISABLE_SO_DOWNLOAD:-0}" == "1" ]] ||
               ! download_checksum_manifest "$checksum_file"; then
                echo "[ERROR] SHA256 manifest unavailable for cached SO: $so_file" >&2
                echo "        本地 SO 缺少校验清单，已拒绝使用。" >&2
                return 1
            fi
        fi
        if ! verify_so_file_with_manifest "$so_file" "$checksum_file"; then
            echo "[ERROR] Cached SO checksum verification failed: $so_file" >&2
            echo "        本地 SO 校验失败，已拒绝使用。请删除该文件后重试下载。" >&2
            return 1
        fi
        echo "$so_file"
        return 0
    fi

    # 环境变量可禁用自动下载
    if [[ "${FLUTTER_CJK_DISABLE_SO_DOWNLOAD:-0}" == "1" ]]; then
        return 1
    fi

    echo "" >&2
    echo "[INFO] SO file not found locally, checking GitHub repository..." >&2
    echo "       本地未找到 SO 文件，正在检查 GitHub 仓库..." >&2

    local github_so_url="$GITHUB_RAW_LIB/$so_name"
    local checksum_url="$GITHUB_RAW_LIB/SHA256SUMS"

    echo "[INFO] Checking GitHub for prebuilt SO..." >&2
    echo "       正在检查 GitHub 预编译 SO..." >&2

    local temp_checksum="$SO_LIB_DIR/.SHA256SUMS.tmp.$$"
    local temp_so="$SO_LIB_DIR/.$so_name.tmp.$$"
    rm -f "$temp_checksum" "$temp_so"

    if ! curl -fsSL "$checksum_url" -o "$temp_checksum"; then
        echo "[ERROR] Failed to download SHA256 manifest" >&2
        echo "        无法下载 SHA256 清单，已拒绝下载 SO。" >&2
        rm -f "$temp_checksum" "$temp_so"
        return 1
    fi

    local expected_hash
    expected_hash=$(awk -v file="$so_name" '$2 == file {print $1; exit}' "$temp_checksum")
    if [[ ! "$expected_hash" =~ ^[0-9a-f]{64}$ ]]; then
        echo "[ERROR] No valid SHA256 entry found for: $so_name" >&2
        echo "        SHA256 清单中没有该 SO 的有效记录，已拒绝下载。" >&2
        rm -f "$temp_checksum" "$temp_so"
        return 1
    fi

    echo "[INFO] Starting download from GitHub (shows progress)..." >&2
    echo "       开始从 GitHub 下载，将在完成后校验 SHA256..." >&2
    echo "" >&2
    if ! curl -fL --progress-bar "$github_so_url" -o "$temp_so"; then
        echo "[ERROR] Failed to download SO file" >&2
        echo "        下载失败。" >&2
        rm -f "$temp_checksum" "$temp_so"
        return 1
    fi

    local actual_hash
    actual_hash=$(sha256sum "$temp_so" | awk '{print $1}')
    if [[ "$actual_hash" != "$expected_hash" ]]; then
        echo "[ERROR] SHA256 checksum mismatch for: $so_name" >&2
        echo "        SHA256 校验失败，下载文件已删除。" >&2
        echo "        Expected: $expected_hash" >&2
        echo "        Actual:   $actual_hash" >&2
        rm -f "$temp_checksum" "$temp_so"
        return 1
    fi

    chmod +x "$temp_so"
    mv "$temp_checksum" "$checksum_file"
    if ! mv "$temp_so" "$so_file"; then
        echo "[ERROR] Failed to install verified SO file" >&2
        echo "        无法写入已校验的 SO 文件。" >&2
        rm -f "$temp_so"
        return 1
    fi
    local size=$(du -h "$so_file" | cut -f1)
    echo "" >&2
    echo "[OK] Downloaded and SHA256 verified: $so_name" >&2
    echo "     下载并校验完成: $size" >&2
    echo "$so_file"
    return 0
}

# 查找相似版本的 SO 文件（主版本号匹配）
# 查找所有可用版本（包括精确和相似版本，本地和线上）
find_all_available_versions() {
    local target_version=$1
    
    # 提取主版本号 (major.minor)
    local major_minor=$(echo "$target_version" | grep -oE '^[0-9]+\.[0-9]+')
    
    if [[ -z "$major_minor" ]]; then
        return 1
    fi
    
    local -A version_map
    local found_exact_local=false
    
    # 1. 查找本地所有相关版本（包括精确和相似）
    if [[ -d "$SO_LIB_DIR" ]]; then
        while IFS= read -r so_file; do
            [[ -f "$so_file" ]] || continue
            local version=$(basename "$so_file" | sed 's/libflutter_linux_gtk\.so\.//')
            # 收集所有匹配主版本号的版本
            if [[ "$version" =~ ^${major_minor}\. ]]; then
                version_map["$version"]="local"
                # 检查是否找到精确匹配
                [[ "$version" == "$target_version" ]] && found_exact_local=true
            fi
        done < <(find "$SO_LIB_DIR" -name "libflutter_linux_gtk.so.*" 2>/dev/null)
    fi
    
    # 2. 查询项目 GitHub lib 目录中的所有版本（仅在本地未找到精确版本时）
    if [[ "$found_exact_local" == "false" ]]; then
        echo 
        echo "[INFO] Checking GitHub repository for available versions..." >&2
        echo "       正在检查 GitHub 仓库可用版本..." >&2
        
        # 使用 GitHub API 获取 lib 目录内容
        local github_api_url="https://api.github.com/repos/krystic/flutter-arm-cjk-fix/contents/lib"
        local github_files
        github_files=$(curl -sG --data-urlencode "ref=$REPO_REF" \
            "$github_api_url" 2>/dev/null |
            grep -oP '"name":\s*"libflutter_linux_gtk\.so\.\K[0-9]+\.[0-9]+\.[0-9]+' ||
            true)
        
        if [[ -n "$github_files" ]]; then
            while IFS= read -r version; do
                [[ -z "$version" ]] && continue
                # 收集所有匹配主版本号的版本
                if [[ "$version" =~ ^${major_minor}\. ]]; then
                    # 如果本地已有，保持 local 标记；否则标记为 online
                    if [[ -z "${version_map[$version]}" ]]; then
                        version_map["$version"]="online"
                    fi
                fi
            done <<< "$github_files"
        fi
    fi
    
    # 3. 输出所有版本（带标记），格式: version|source|is_exact
    if [[ ${#version_map[@]} -gt 0 ]]; then
        for version in $(printf '%s\n' "${!version_map[@]}" | sort -V -r); do
            local is_exact="false"
            [[ "$version" == "$target_version" ]] && is_exact="true"
            echo "$version|${version_map[$version]}|$is_exact"
        done
        return 0
    fi
    
    return 1
}

# 向后兼容：查找相似版本（调用新的统一函数）
find_similar_so_versions() {
    local target_version=$1
    find_all_available_versions "$target_version" | while IFS='|' read -r version source is_exact; do
        echo "$version|$source"
    done
}

# 挂载 SO 文件替换
