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
        echo "错误: 此操作需要 sudo 权限。"
        exit 1
    fi
}

# 自动创建系统级服务
setup_system_service() {
    if [ ! -f "$SERVICE_FILE" ]; then
        echo "正在初始化系统级自启服务..."
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
        echo "Systemd 服务已创建并设为开机自启。"
    fi
}

# 执行全量卸载 (保留配置文件/服务的逻辑在 do_unmount_all 之外处理)
do_unmount_all() {
    echo "--- 开始全量卸载当前所有字体映射 ---"
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
                echo "[$app] 映射已释放"
            fi
        done
    else
        echo "未发现任何已修复的应用记录。"
    fi
}

# 挂载逻辑
do_mount() {
    local APP=$1
    local IS_STARTUP=$2

    local SNAP_PATH="/snap/$APP/current/"
    [ ! -d "$SNAP_PATH" ] && return 1
    local TARGET_DIR=$(find -L "$SNAP_PATH" -name "Ubuntu-R.ttf" -printf '%h\n' | head -n 1)
    [ -z "$TARGET_DIR" ] && return 1

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
    echo "[$APP] 映射修复成功。"
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
    echo "[$APP] 映射已撤销并移除配置。"
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
        echo "管理器已彻底卸载。"
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
    echo "用法:"
    echo "  修复应用: sudo $0 -a <app_name>"
    echo "  取消修复: sudo $0 -u -a <app_name>"
    echo "  全量释放: sudo $0 --unmount-all"
    echo "  彻底移除: sudo $0 --remove-service"
    exit 1
fi

if [[ "$COMMAND" == "mount" ]]; then
    [ ! -f "$NOTO_REG" ] && apt update && apt install -y fonts-noto-cjk
    do_mount "$APP_NAME" "false"
else
    do_unmount "$APP_NAME"
fi