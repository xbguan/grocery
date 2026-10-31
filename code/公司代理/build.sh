#!/bin/bash
# 构建「公司代理」App 与 DMG
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="公司代理"
BIN_NAME="CorpProxyBar"
VERSION="2.2.1"
BUNDLE_ID="local.xbguan.corpproxy"

# 构建机自身架构（用于只在构建期运行的辅助工具）
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in arm64|x86_64) ;; *) HOST_ARCH="x86_64" ;; esac

# 目标架构：同时产出 Intel 与 Apple Silicon，合成通用二进制
# 项目规约：交付的 .app/.dmg 必须是 universal2，缺任一架构即构建失败。
# 只有显式声明 ALLOW_SINGLE_ARCH=1 才允许降级为单架构（仅限本地调试）。
TARGET_ARCHS="arm64 x86_64"
ALLOW_SINGLE_ARCH="${ALLOW_SINGLE_ARCH:-0}"

rm -rf build/app build/dmg build/slices dist
mkdir -p "build/app/${APP_NAME}.app/Contents/MacOS" "build/app/${APP_NAME}.app/Contents/Resources" dist build/slices

# 1. 图标
if [ ! -f build/AppIcon.icns ]; then
  mkdir -p build/AppIcon.iconset
  swiftc -O -target "${HOST_ARCH}-apple-macos13.0" -framework Cocoa -o build/icongen IconGen.swift
  ./build/icongen build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "build/app/${APP_NAME}.app/Contents/Resources/AppIcon.icns"

# 2. 可执行文件 —— 逐架构编译后 lipo 合并（Intel + M 芯片通用）
BIN_OUT="build/app/${APP_NAME}.app/Contents/MacOS/${BIN_NAME}"
SLICES=""   # 用字符串而非数组：macOS 自带 bash 3.2 下空数组配 set -u 会报错
BUILT=""
MISSING=""
for ARCH in $TARGET_ARCHS; do
  OUT="build/slices/${BIN_NAME}-${ARCH}"
  if swiftc -O -target "${ARCH}-apple-macos13.0" \
      -framework Cocoa -framework SystemConfiguration -framework ServiceManagement \
      -o "$OUT" Sources/*.swift 2>"build/slices/${ARCH}.log"; then
    SLICES="$SLICES $OUT"
    BUILT="$BUILT $ARCH"
  else
    MISSING="$MISSING $ARCH"
    echo "⚠️  ${ARCH} 编译失败："
    grep -m3 "error:" "build/slices/${ARCH}.log" || tail -3 "build/slices/${ARCH}.log"
  fi
done
[ -n "$SLICES" ] || { echo "❌ 没有任何架构编译成功"; exit 1; }
lipo -create $SLICES -output "$BIN_OUT"

# 规约检查：必须是 universal2（Intel + Apple Silicon 都能原生跑）
if [ -n "$MISSING" ]; then
  if [ "$ALLOW_SINGLE_ARCH" = "1" ]; then
    echo "⚠️  构建为单架构（已显式允许）：$(lipo -archs "$BIN_OUT")，缺 ${MISSING# }"
  else
    echo "❌ 缺少架构：${MISSING# }"
    echo "   交付物必须是 universal2（arm64 + x86_64）。"
    echo "   若只是本机临时调试，请显式执行：ALLOW_SINGLE_ARCH=1 ./build.sh"
    exit 1
  fi
fi
for ARCH in $TARGET_ARCHS; do
  lipo -archs "$BIN_OUT" | grep -qw "$ARCH" || { echo "❌ 产物缺少 ${ARCH} slice"; exit 1; }
done
echo "架构: $(lipo -archs "$BIN_OUT")"

# 3. Info.plist
cat > "build/app/${APP_NAME}.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>zh_CN</string>
	<key>CFBundleExecutable</key>
	<string>CorpProxyBar</string>
	<key>CFBundleIdentifier</key>
	<string>local.xbguan.corpproxy</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>公司代理</string>
	<key>CFBundleDisplayName</key>
	<string>公司代理</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>__VERSION__</string>
	<key>CFBundleVersion</key>
	<string>__VERSION__</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<false/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>公司代理 · 公司 3proxy 一键开关</string>
</dict>
</plist>
PLIST

# heredoc 不展开变量，版本号用占位符回填
sed -i '' "s/__VERSION__/${VERSION}/g" "build/app/${APP_NAME}.app/Contents/Info.plist"

# 4. ad-hoc 签名
xattr -cr "build/app/${APP_NAME}.app" 2>/dev/null || true
codesign --force --sign - --timestamp=none "build/app/${APP_NAME}.app" >/dev/null 2>&1
codesign --verify --verbose=1 "build/app/${APP_NAME}.app"

# 5. DMG 装配
STAGE="build/dmg"
mkdir -p "$STAGE"
cp -R "build/app/${APP_NAME}.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "packaging/卸载公司代理.command" "$STAGE/"
chmod +x "$STAGE/卸载公司代理.command"
cat > "$STAGE/安装说明.txt" <<'README'
公司代理 —— 使用说明
=====================

安装
----
把「公司代理.app」拖到左侧的 Applications（应用程序）文件夹，然后从「应用程序」打开一次。
打开后菜单栏会出现一个建筑图标。默认不占程序坞；想常驻程序坞就打开
「设置…→ 外观 → 在程序坞显示图标」，或点菜单栏图标勾选「在程序坞显示」。
勾选后：点程序坞图标 = 弹出和顶部图标一样的菜单；右键程序坞图标 = 快速开关代理；
需要改配置时点菜单里的「设置…」。

首次启用前
----------
1) 先连上公司 VPN：
   · 用 HD-VPN.app 拨号（本机出现 ppp0）——适合"我换到别的网络"的场景
   · 或用路由器 L2TP 拨号（本机无需客户端）
2) 菜单栏图标 →「设置…」，填写公司 3proxy 的地址、端口、用户名、密码，
   并选择 VPN 接入方式（自动检测 / HD-VPN 客户端 / 路由器 L2TP）。
3) 点「测试连接」确认 chatgpt.com 返回 401，再点「保存并应用」。
   账号和密码都填好之后再启用；空凭据会让浏览器反复弹代理认证框。

日常使用
--------
· 「启用公司代理」：系统代理（Safari / Chrome / ChatGPT 桌面版）+ Codex CLI 一起走公司线路
· 「关闭代理（直连）」：恢复直连
· 浏览器不会弹代理登录框：系统代理指向本机中继 127.0.0.1:7899，由 App 代填认证

卸载
----
菜单栏图标 →「卸载公司代理…」。它会一并关闭系统代理、把 Codex 的 ~/.codex/.env 改回直连、
注销开机自启，并删除配置、日志、偏好、缓存与 App 本体。

如果 App 已经被你拖进废纸篓，双击本 DMG 里的「卸载公司代理.command」，
它会做同样的清理（含 ~/.config/corp-proxy 里的代理账号密码）。

首次打开提示"无法验证开发者"
------------------------------
本 App 为本地构建、ad-hoc 签名。若被 Gatekeeper 拦住：
右键点「公司代理.app」→ 打开 → 再点「打开」。只需一次。
README
cp "build/AppIcon.icns" "$STAGE/AppIcon.icns" 2>/dev/null || true
rm -f "$STAGE/AppIcon.icns"

hdiutil create -quiet -volname "${APP_NAME}" -srcfolder "$STAGE" -fs HFS+ -format UDZO \
  -ov "dist/${APP_NAME}-${VERSION}.dmg"
hdiutil verify "dist/${APP_NAME}-${VERSION}.dmg" >/dev/null

# 6. 交付自检（规约：DMG 存在 + 版本一致 + 双架构）
DMG="dist/${APP_NAME}-${VERSION}.dmg"
[ -f "$DMG" ] || { echo "❌ 未生成 ${DMG}"; exit 1; }
PLIST_VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "build/app/${APP_NAME}.app/Contents/Info.plist" 2>/dev/null || echo '')"
[ "$PLIST_VER" = "$VERSION" ] || { echo "❌ 版本不一致：plist=${PLIST_VER} VERSION=${VERSION}"; exit 1; }
DMG_ARCHS="$(lipo -archs "$BIN_OUT")"
echo "版本: ${PLIST_VER}    架构: ${DMG_ARCHS}    $(du -h "$DMG" | cut -f1)"

echo
echo "✅ 完成: ${DMG}"
ls -lh "$DMG"
