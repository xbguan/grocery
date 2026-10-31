#!/bin/zsh
# 把 .app 打包成可分发的 DMG 安装镜像
#
#   ./make-dmg.sh            直接打包现有 .app
#   ./make-dmg.sh --rebuild  先重新编译通用版本再打包
#
# 产物: dist/OpenAI API 仪表盘-<版本>.dmg
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="OpenAI API 仪表盘"
APP_BUNDLE="${APP_NAME}.app"
BUILT_APP=".build/bundle/${APP_BUNDLE}"   # build.sh 组装的原件，避免碰项目根下受保护的副本
EXEC_NAME="OpenAIBar"
VOL_NAME="OpenAI API 仪表盘"
DIST="dist"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
OUT="${DIST}/${APP_NAME}-${VERSION}.dmg"

# ---------- 1. 确保有通用二进制 ----------
need_build=0
[[ "${1:-}" == "--rebuild" ]] && need_build=1
[[ -d "$BUILT_APP" ]] || need_build=1

if [[ $need_build -eq 0 ]]; then
  archs=$(lipo -archs "${BUILT_APP}/Contents/MacOS/${EXEC_NAME}")
  if [[ "$archs" != *arm64* || "$archs" != *x86_64* ]]; then
    echo "!! 当前 .app 只有 [${archs}]，M 芯片 Mac 跑不了 → 重新编译通用版本"
    need_build=1
  fi
fi

if [[ $need_build -eq 1 ]]; then
  ./build.sh --universal
fi

# ---------- 2. 建空的可写镜像 ----------
# 直接往空镜像里拷 App，而不是先做一个 staging 目录：
# staging 目录里的 App 副本事后必须删掉，会撞上"禁止删除 .app 内容"的规则。
mkdir -p "$DIST"
hdiutil detach "/Volumes/${VOL_NAME}" >/dev/null 2>&1 || true
rm -f "${DIST}/rw.dmg"
echo "==> 创建可写镜像"
# 不带 -format：只要给了 -size 就是空的读写镜像（UDRW）。
# 显式写 -format UDRW 反而会报 "-format requires -srcfolder or -srcdevice"。
hdiutil create -size 40m -volname "$VOL_NAME" -fs HFS+ \
  -ov -quiet "${DIST}/rw.dmg"
hdiutil attach "${DIST}/rw.dmg" -nobrowse -noautoopen -quiet

MOUNT="/Volumes/${VOL_NAME}"
if [[ ! -d "$MOUNT" ]]; then
  echo "挂载失败: $MOUNT 不存在" >&2
  exit 1
fi

# ---------- 3. 往镜像里放内容 ----------
echo "==> 拷贝 App"
# 用 cp -R 而不是 ditto：ditto 走"写临时文件 .BC.T_xxx 再 rename 覆盖"的路径，
# 宿主安全策略不允许 .app 内部出现这类 unlink/rename，会整包拷贝失败（Operation not permitted）。
# cp -R 是直接写入目标文件，不产生临时文件，可以正常完成。
cp -R "$BUILT_APP" "${MOUNT}/"
ln -s /Applications "${MOUNT}/Applications"

echo "==> 生成窗口背景图"
mkdir -p "${MOUNT}/.background"
swiftc -O Tools/dmgbg/main.swift -o .build/dmgbg
.build/dmgbg "${MOUNT}/.background/bg.png" | sed 's/^/    /'

# ---------- 4. 写入窗口布局 ----------
echo "==> 写入窗口布局（尺寸 / 背景图 / 图标位置）"
# AppleScript 操作 Finder 在本机一律返回 -10004（自动化权限未授予），
# 所以窗口布局直接手写 .DS_Store，依赖已内嵌在 Tools/pylib。
python3 Tools/dmg-layout.py "$MOUNT" "$APP_BUNDLE" | sed 's/^/    /'
sync

# ---------- 5. 卸载并压缩 ----------
echo "==> 校验镜像内 App"
codesign --verify --deep --strict "${MOUNT}/${APP_BUNDLE}" 2>&1 | sed 's/^/    /' \
  && echo "    签名有效: $(lipo -archs "${MOUNT}/${APP_BUNDLE}/Contents/MacOS/${EXEC_NAME}")"

echo "==> 卸载"
if ! hdiutil detach "$MOUNT" -quiet 2>/dev/null; then
  echo "    卷正被占用，强制卸载"
  hdiutil detach "$MOUNT" -force -quiet
fi

echo "==> 压缩为只读镜像 (UDZO)"
rm -f "$OUT"
hdiutil convert "${DIST}/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT" -quiet
rm -f "${DIST}/rw.dmg"

# ---------- 6. 校验 ----------
echo "==> 校验镜像"
hdiutil verify "$OUT" 2>&1 | tail -2 | sed 's/^/    /'

echo ""
echo "完成: $(pwd)/${OUT}"
echo "大小: $(du -h "$OUT" | cut -f1)"
echo "App 架构: $(lipo -archs "${BUILT_APP}/Contents/MacOS/${EXEC_NAME}")"
echo ""
echo "打开查看: open \"$(pwd)/${OUT}\""
