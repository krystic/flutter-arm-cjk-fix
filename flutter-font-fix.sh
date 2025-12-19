#!/bin/bash

# --- 路径定义 ---
CONFIG_FILE="/etc/flutter_font_fixed_apps.conf"
SERVICE_FILE="/etc/systemd/system/flutter-font-fix.service"
SCRIPT_PATH=$(realpath "$0")

NOTO_DIR="/usr/share/fonts/opentype/noto"
NOTO_REG="$NOTO_DIR/NotoSansCJK-Regular.ttc"
NOTO_BOLD="$NOTO_DIR/NotoSansCJK-Bold.ttc"
NOTO_LIGHT="$NOTO_DIR/NotoSansCJK-Light.ttc"
NOTO_MEDIUM="$NOTO_DIR/NotoSansCJK-Medium.ttc"

# --- 辅助函数 ---

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "[ERROR] This operation requires sudo privileges. / 错误：此操作需要 sudo 权限。"
        exit 1
    fi
}

# 自动创建系统级服务
setup_system_service() {
    if [ ! -f "$SERVICE_FILE" ]; then
        echo ""
        echo "[INFO] Creating systemd service..."
        echo "       正在创建 systemd 服务..."
        cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Flutter Font Auto-Mount Service (System Level)
After=snapd.service
Requires=snapd.service
ConditionPathExists=$CONFIG_FILE

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 3
ExecStart=$SCRIPT_PATH --startup
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable flutter-font-fix.service
        echo "[OK] Systemd service installed and enabled. / Systemd 服务已创建并启用。"
    fi
}

# 执行全量卸载 (保留配置文件/服务的逻辑在 do_unmount_all 之外处理)
do_unmount_all() {
    echo ""
    echo "[INFO] Unmounting all font mappings..."
    echo "       开始全量卸载当前所有字体映射..."
    if [ -f "$CONFIG_FILE" ]; then
        # 必须先保存列表，避免循环中修改文件导致读取不全
        local APPS=$(cat "$CONFIG_FILE")
        for app in $APPS; do
            # 调用逻辑卸载，不在此处删除配置行
            local SNAP_PATH="/snap/$app/current/"
            local TARGET_DIR=$(find -L "$SNAP_PATH" -name "Ubuntu-R.ttf" -printf '%h\n' 2>/dev/null | head -n 1)
            if [ -n "$TARGET_DIR" ]; then
                for f in "$TARGET_DIR"/Ubuntu-*.ttf; do
                    umount -l "$f" 2>/dev/null
                done
                echo "[OK] [$app] Mapping released. / 映射已释放"
            fi
        done
    else
        echo ""
        echo "[INFO] No fixed apps found."
        echo "       未发现任何已修复的应用记录。"
    fi
}

# 挂载逻辑
do_mount() {
    local APP=$1
    local IS_STARTUP=$2

    local SNAP_PATH="/snap/$APP/current/"
    if [ ! -d "$SNAP_PATH" ]; then
        echo "[ERROR] Snap app not found: '$APP' / 未找到 snap 应用：'$APP'"
        return 1
    fi
    local TARGET_DIR=$(find -L "$SNAP_PATH" -name "Ubuntu-R.ttf" -printf '%h\n' | head -n 1)
    if [ -z "$TARGET_DIR" ]; then
        echo "[ERROR] No target font files found in snap app: '$APP' / 未在应用中找到目标字体文件：'$APP'"
        return 1
    fi

    declare -A MAP=(
        ["Ubuntu-R.ttf"]="$NOTO_REG"   ["Ubuntu-RI.ttf"]="$NOTO_REG"
        ["Ubuntu-L.ttf"]="$NOTO_LIGHT" ["Ubuntu-LI.ttf"]="$NOTO_LIGHT"
        ["Ubuntu-M.ttf"]="$NOTO_MEDIUM" ["Ubuntu-MI.ttf"]="$NOTO_MEDIUM"
        ["Ubuntu-B.ttf"]="$NOTO_BOLD"  ["Ubuntu-BI.ttf"]="$NOTO_BOLD"
    )

    for ttf in "${!MAP[@]}"; do
        if [ -f "$TARGET_DIR/$ttf" ]; then
            umount -l "$TARGET_DIR/$ttf" 2>/dev/null
            mount --bind "${MAP[$ttf]}" "$TARGET_DIR/$ttf"
        fi
    done

    if [[ "$IS_STARTUP" == "false" ]]; then
        grep -q "^$APP$" "$CONFIG_FILE" 2>/dev/null || echo "$APP" >> "$CONFIG_FILE"
        setup_system_service
    fi
    echo "[OK] [$APP] Font mapping repaired. / 映射修复成功。"
}

# 单个卸载逻辑
do_unmount() {
    local APP=$1
    local SNAP_PATH="/snap/$APP/current/"
    local TARGET_DIR=$(find -L "$SNAP_PATH" -name "Ubuntu-R.ttf" -printf '%h\n' | head -n 1)

    if [ -n "$TARGET_DIR" ]; then
        for f in "$TARGET_DIR"/Ubuntu-*.ttf; do
            umount -l "$f" 2>/dev/null
        done
    fi
    [ -f "$CONFIG_FILE" ] && sed -i "/^$APP$/d" "$CONFIG_FILE" 2>/dev/null
    echo "[OK] [$APP] Mapping removed and configuration updated. / 映射已撤销并移除配置。"
}

# 支持 bash 补全：在 -a/--app 后补全 snap 已安装的应用
get_snap_apps() {
    if command -v snap >/dev/null 2>&1; then
        snap list | awk 'NR>1{print $1}'
    fi
}

install_completion() {
    check_root
    local FILE="/etc/bash_completion.d/flutter-font-fix"
    cat > "$FILE" <<'EOF'
# bash completion for flutter-font-fix
_flutter_font_fix_completion() {
    local cur prev apps
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    case "$prev" in
        -a|--app)
            if command -v snap >/dev/null 2>&1; then
                apps="$(snap list | awk 'NR>1{print $1}')"
                COMPREPLY=( $(compgen -W "$apps" -- "$cur") )
            fi
            ;;
    esac
}
complete -F _flutter_font_fix_completion flutter-font-fix.sh flutter-font-fix
EOF
    echo "[OK] Bash completion installed to $FILE / 补全已安装到 $FILE"
    # 尝试在当前 shell 下生效（如果可能）
    if [ -n "$BASH_VERSION" ] && [[ $- == *i* ]]; then
        . "$FILE" 2>/dev/null || true
        echo "[OK] Completion loaded into current shell. To activate in new shells, run: source $FILE or restart the terminal. / 当前 shell 已加载补全。要让新终端生效请运行：source $FILE 或重启终端。"
    fi

    # 如果通过 sudo 调用，则为原始调用用户提供选项：自动追加到其 ~/.bashrc（交互式时询问）
    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "$(id -un)" ]; then
        USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        USER_RC="$USER_HOME/.bashrc"
        if [[ $- == *i* ]]; then
            read -r -p "检测到以 sudo 运行，原始用户为 '$SUDO_USER'。是否将 'source $FILE' 自动追加到 $USER_RC 并提示其生效？ [y/N] " ans
            case "$ans" in
                [Yy]*)
                    if [ -w "$USER_RC" ] || { [ ! -e "$USER_RC" ] && [ -w "$USER_HOME" ]; }; then
                        grep -qF "source $FILE" "$USER_RC" 2>/dev/null || echo "source $FILE" >> "$USER_RC"
                        echo "[OK] Added 'source $FILE' to $USER_RC. Ask $SUDO_USER to run 'source $USER_RC' or restart their terminal to activate. / 已将 'source $FILE' 追加到 $USER_RC。请让 $SUDO_USER 运行 'source $USER_RC' 或重启终端以生效。"
                    else
                        echo "[WARN] Cannot write to $USER_RC; please add 'source $FILE' manually. / 无法写入 $USER_RC，请手动添加 'source $FILE'。"
                    fi
                    ;;
                *)
                    echo "已取消为 $SUDO_USER 自动追加 source。请手动运行 'echo \"source $FILE\" >> $USER_RC' 来添加并使用 'source $USER_RC' 以生效。"
                    ;;
            esac
        else
            echo "提示: 以 sudo 运行安装，原始用户是 $SUDO_USER；可在其 shell 中运行 'source $FILE' 以立即生效，或把 'source $FILE' 添加到 $USER_RC 使其永久生效。"
        fi
    fi
}

prompt_install_completion() {
    # 仅在交互式 shell 中提示；非交互式环境下输出安装建议而不阻塞
    if [[ $- != *i* ]]; then
        echo ""
        echo "[INFO] To enable Tab completion for -a/--app, run:"
        echo "       sudo \"$SCRIPT_PATH\" -i"
        echo "       若要启用 -a/--app 的 Tab 自动补全，请在交互式 shell 中运行："
        echo "       sudo \"$SCRIPT_PATH\" -i"
        return
    fi

    local reply
    read -r -p "Install shell completion now to enable Tab completion for -a/--app? [y/N] / 现在安装 Tab 补全以启用 -a/--app 的自动补全吗？[y/N] " reply
    case "$reply" in
        [Yy]*)
            if [[ $EUID -eq 0 ]]; then
                install_completion
            else
                echo ""
                echo "[INFO] Requires sudo, attempting to install with sudo..."
                echo "       需要 sudo 权限，尝试以 sudo 安装..."
                sudo "$SCRIPT_PATH" -i
            fi
            ;;
        *)
            echo ""
            echo "[INFO] Installation cancelled."
            echo "       已取消安装补全。"
            ;;
    esac
}

# --- 主逻辑 ---

case "$1" in
    --startup)
        [ ! -f "$CONFIG_FILE" ] && exit 0
        while IFS= read -r app; do
            [ -n "$app" ] && do_mount "$app" "true"
        done < "$CONFIG_FILE"
        exit 0
        ;;
    --unmount-all)
        check_root
        do_unmount_all
        # 注意：此模式下我们选择保留配置文件，以便下次启动或手动执行 --startup 时恢复
        # 如果你想卸载的同时清空配置，请使用下面的逻辑：
        # rm -f "$CONFIG_FILE" 
        exit 0
        ;;
    --remove-service)
        check_root
        # 1. 先执行全量卸载
        do_unmount_all
        # 2. 清理配置文件
        rm -f "$CONFIG_FILE"
        # 3. 停止并注销服务
        if [ -f "$SERVICE_FILE" ]; then
            systemctl disable --now flutter-font-fix.service 2>/dev/null
            rm -f "$SERVICE_FILE"
            systemctl daemon-reload
        fi
        echo "[OK] Manager fully removed. / 管理器已彻底卸载。"
        exit 0
        ;;
    -i|--init)
        check_root
        install_completion
        exit 0
        ;;
esac

# 交互模式
check_root
COMMAND="mount"
APP_NAME=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -u|--unmount) COMMAND="unmount"; shift ;;
    -a|--app) APP_NAME="$2"; shift 2 ;;
    *) APP_NAME="$1"; shift ;;
  esac
done

if [ -z "$APP_NAME" ]; then
    echo "Usage / 用法:"
    echo "  Repair an app:      sudo $0 -a <app_name>    (修复应用)"
    echo "  Unrepair an app:    sudo $0 -u -a <app_name> (取消修复)"
    echo "  Unmount all:        sudo $0 --unmount-all    (全量释放)"
    echo "  Remove manager:     sudo $0 --remove-service (彻底移除)"
    echo "  Install completion: sudo $0 -i | --init      (Install shell completion / 安装补全)"
    prompt_install_completion
    exit 1
fi

if [[ "$COMMAND" == "mount" ]]; then
    [ ! -f "$NOTO_REG" ] && apt update && apt install -y fonts-noto-cjk
    if ! do_mount "$APP_NAME" "false"; then
        echo "[ERROR] App '$APP_NAME' not found or no target fonts to replace. / 未找到应用 '$APP_NAME' 或未找到可替换字体。"
        prompt_install_completion
        exit 1
    fi
else
    do_unmount "$APP_NAME"
fi