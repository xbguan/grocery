#!/bin/zsh
# 构建并打包「OpenAI API 仪表盘」（无需完整 Xcode，Command Line Tools 即可）
#
#   ./build.sh              只编译本机架构（快，日常开发用）
#   ./build.sh --universal  编译 arm64 + x86_64 通用二进制（发给别的 Mac 用）
set -euo pipefail
cd "$(dirname "$0")"

EXEC_NAME="OpenAIBar"                # 二进制名（Info.plist 的 CFBundleExecutable）
APP_NAME="OpenAI API 仪表盘"          # 显示名 / .app 文件名
APP_BUNDLE="${APP_NAME}.app"
DEPLOY_TARGET="14.0"

UNIVERSAL=0
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --universal) UNIVERSAL=1 ;;
    --install) INSTALL=1 ;;
    *) echo "未知参数: $arg" >&2; exit 1 ;;
  esac
done

if [[ $UNIVERSAL -eq 1 ]]; then
  echo "==> 编译 (release, arm64 + x86_64)"
  # 不能直接用 `swift build --arch a --arch b`：多架构路径依赖 xcbuild，
  # 只装 Command Line Tools 时没有 xcbuild。改为分别交叉编译再 lipo 合并。
  swift build -c release --disable-sandbox \
    --triple "x86_64-apple-macosx${DEPLOY_TARGET}" --scratch-path .build/x86_64
  swift build -c release --disable-sandbox \
    --triple "arm64-apple-macosx${DEPLOY_TARGET}" --scratch-path .build/arm64

  mkdir -p .build/universal
  BIN_PATH=".build/universal/${EXEC_NAME}"
  lipo -create ".build/x86_64/release/${EXEC_NAME}" \
               ".build/arm64/release/${EXEC_NAME}" \
         -output "$BIN_PATH"
  echo "    架构: $(lipo -archs "$BIN_PATH")"
else
  echo "==> 编译 (release, 本机架构)"
  # --disable-sandbox: 宿主环境不允许 sandbox-exec 时必需
  swift build -c release --disable-sandbox
  BIN_PATH=".build/release/${EXEC_NAME}"
fi

if [[ ! -f "$BIN_PATH" ]]; then
  echo "编译产物不存在: $BIN_PATH" >&2
  exit 1
fi

echo "==> 生成应用图标"
# 图标由 Logo.swift 直接绘制，保证和菜单栏、面板里的 logo 是同一份几何
swiftc -O Sources/OpenAIBar/Logo.swift Tools/icongen/main.swift -o .build/icongen
rm -rf .build/icon.iconset Resources/AppIcon.icns
.build/icongen .build/icon.iconset >/dev/null
iconutil -c icns .build/icon.iconset -o Resources/AppIcon.icns

echo "==> 组装 App Bundle"
# 先在 .build 里从零组装（那里可以随意清理），再同步到项目根，
# 避免对根目录下已有的 .app 做删除操作。
BUNDLE_DIR=".build/bundle/${APP_BUNDLE}"
rm -rf ".build/bundle"
mkdir -p "${BUNDLE_DIR}/Contents/MacOS" "${BUNDLE_DIR}/Contents/Resources"
cp "$BIN_PATH" "${BUNDLE_DIR}/Contents/MacOS/${EXEC_NAME}"
cp Resources/Info.plist "${BUNDLE_DIR}/Contents/Info.plist"
cp Resources/AppIcon.icns "${BUNDLE_DIR}/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "${BUNDLE_DIR}/Contents/PkgInfo"

echo "==> Ad-hoc 签名"
xattr -cr "$BUNDLE_DIR" 2>/dev/null || true
codesign --force --deep --sign - "$BUNDLE_DIR" 2>&1 | sed 's/^/    /'

echo "==> 校验"
codesign --verify --verbose=2 "$BUNDLE_DIR" 2>&1 | sed 's/^/    /'
echo "    架构: $(lipo -archs "${BUNDLE_DIR}/Contents/MacOS/${EXEC_NAME}")"

# 不再往项目根拷 .app：该路径已被宿主安全策略保护（连写入都被拒），
# 而且 DMG 打包与安装都直接用 .build/bundle 里的原件，不需要根目录副本。
if [[ $INSTALL -eq 1 ]]; then
  echo "==> 安装到 /Applications"
  pkill -f "${APP_BUNDLE}/Contents/MacOS/${EXEC_NAME}" 2>/dev/null || true
  [[ -e "/Applications/${APP_BUNDLE}" ]] && mv "/Applications/${APP_BUNDLE}" \
    "$HOME/.Trash/${APP_NAME}-旧版本-$(date +%s).app" 2>/dev/null || true
  ditto "$BUNDLE_DIR" "/Applications/${APP_BUNDLE}"
  echo "    已安装: /Applications/${APP_BUNDLE}"
fi

echo ""
echo "完成: $(pwd)/${BUNDLE_DIR}"
echo "安装: ./build.sh --install   （拷贝到 /Applications）"
echo "启动: open \"$(pwd)/${BUNDLE_DIR}\""
