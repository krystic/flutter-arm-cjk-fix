#!/bin/bash
# 测试版本自动检测功能

APP="snap-store"
GITHUB_MAP="/etc/flutter-cjk/github-repos.conf"

echo "=== Testing Auto Flutter Version Detection ==="
echo ""

# 步骤 1: 获取 GitHub 仓库
echo "[1] Getting GitHub repository..."

# 先尝试从对照表获取
if [[ -f "$GITHUB_MAP" ]]; then
    REPO=$(grep "^$APP|" "$GITHUB_MAP" 2>/dev/null | head -n1 | cut -d'|' -f2)
    if [[ -n "$REPO" ]]; then
        echo "    ✅ Found in map: $REPO"
    fi
fi

# 如果对照表没有，尝试从 snapcraft.io 获取
if [[ -z "$REPO" ]]; then
    echo "    ⚠️  Not in map, trying snapcraft.io..."
    REPO=$(curl -sL "https://snapcraft.io/$APP" 2>/dev/null | grep -oP 'github\.com/[\w\-/]+' | head -n 1)
    if [[ -n "$REPO" ]]; then
        REPO="https://$REPO"
        echo "    ✅ Found: $REPO"
    else
        echo "    ❌ Failed to get repository"
        echo ""
        echo "📝 You can add it manually to: $GITHUB_MAP"
        echo "   Format: $APP|https://github.com/owner/repo"
        exit 1
    fi
fi

echo ""

# 步骤 2: 获取 commit ID
echo "[2] Getting commit ID from snap info..."
COMMIT=$(snap info "$APP" 2>/dev/null | grep "installed:" | grep -oP '\+git\.\K[a-f0-9]+' | head -n1)
if [[ -n "$COMMIT" ]]; then
    echo "    ✅ Commit: $COMMIT"
else
    echo "    ❌ Failed to get commit ID"
    exit 1
fi

echo ""

# 步骤 3: 获取 Flutter 版本
echo "[3] Getting Flutter version from .fvmrc..."
FVMRC_URL="${REPO}/raw/${COMMIT}/.fvmrc"
echo "    URL: $FVMRC_URL"

FLUTTER_VERSION=$(curl -sL "$FVMRC_URL" 2>/dev/null | grep -oP '"flutter"\s*:\s*"\K[0-9.]+')
if [[ -n "$FLUTTER_VERSION" ]]; then
    echo "    ✅ Flutter version: $FLUTTER_VERSION"
else
    echo "    ❌ Failed to get Flutter version"
    exit 1
fi

echo ""

# 步骤 4: 检查 SO 文件
echo "[4] Checking for SO file..."
SO_FILE="lib/libflutter_linux_gtk.so.$FLUTTER_VERSION"
if [[ -f "$SO_FILE" ]]; then
    echo "    ✅ SO file found: $SO_FILE"
    echo ""
    echo "🎉 All checks passed! You can run:"
    echo "   sudo ./flutter-font-fix -a $APP"
else
    echo "    ⚠️  SO file not found: $SO_FILE"
    echo ""
    echo "📝 Next steps:"
    echo "   1. Compile Flutter Engine $FLUTTER_VERSION with fontconfig support"
    echo "   2. Place the compiled SO file at: $SO_FILE"
    echo "   3. Run: sudo ./flutter-font-fix -a $APP"
fi

echo ""
echo "=== Test Complete ==="
