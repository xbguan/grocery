#!/bin/zsh
# 彻底卸载「OpenAI API 仪表盘」
#
# 只把 App 拖进废纸篓是不够的 —— 钥匙串里的 Admin Key、配置目录、
# 以及余额功能用到的平台登录态都不会跟着走，这个脚本把它们一起清干净。
#
#   ./uninstall.sh              列出将删除的内容，确认后执行
#   ./uninstall.sh --yes        跳过确认
#   ./uninstall.sh --dry-run    只看不删
set -euo pipefail

APP_NAME="OpenAI API 仪表盘"
EXEC_NAME="OpenAIBar"
BUNDLE_ID="com.xbguan.openai-api-dashboard"
ACCOUNT="openai-admin-key"
LEGACY_SERVICE="com.xbguan.openaibar"      # 早期版本用过的服务名
CONFIG_DIR="${HOME}/Library/Application Support/OpenAIApiDashboard"
WEBKIT_DIR="${HOME}/Library/WebKit/${BUNDLE_ID}"          # 平台登录态（余额功能）
CACHES_DIR="${HOME}/Library/Caches/${BUNDLE_ID}"
TRASH_DIR="${HOME}/.Trash"

ASSUME_YES=0
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    -y|--yes)     ASSUME_YES=1 ;;
    -n|--dry-run) DRY_RUN=1 ;;
    -h|--help)
      sed -n '2,11p' "$0" | sed 's/^#\{1,\} \{0,1\}//'
      exit 0 ;;
    *) echo "未知参数: $arg（可用 -y / --dry-run）" >&2; exit 1 ;;
  esac
done

# ---------- 找出 App 可能所在的每一处 ----------
typeset -a APP_PATHS
typeset -A seen
for p in "/Applications/${APP_NAME}.app" \
         "${HOME}/Applications/${APP_NAME}.app" \
         "${PWD}/${APP_NAME}.app"; do
  [[ -d "$p" ]] || continue
  real=$(cd "$(dirname "$p")" && pwd)/$(basename "$p")
  [[ -n "${seen[$real]:-}" ]] && continue
  seen[$real]=1
  APP_PATHS+=("$real")
done

# ---------- 报告 ----------
echo "将执行："
echo "  1) 退出运行中的进程（如果有）"
if [[ ${#APP_PATHS[@]} -eq 0 ]]; then
  echo "  2) App      → 没有找到已安装的 App，跳过"
else
  for p in "${APP_PATHS[@]}"; do
    echo "  2) App      → 移到废纸篓: $p"
  done
fi
echo "  3) 钥匙串   → 删除 ${BUNDLE_ID} / ${ACCOUNT}"
if [[ -d "$CONFIG_DIR" ]]; then
  echo "  4) 配置目录 → 删除 ${CONFIG_DIR}"
else
  echo "  4) 配置目录 → 不存在，跳过"
fi
if [[ -d "$WEBKIT_DIR" ]]; then
  echo "  5) 登录态   → 删除 ${WEBKIT_DIR}（余额功能的平台登录态）"
else
  echo "  5) 登录态   → 不存在，跳过"
fi

if [[ $DRY_RUN -eq 1 ]]; then
  echo ""
  echo "（--dry-run：未做任何改动）"
  exit 0
fi

if [[ $ASSUME_YES -eq 0 ]]; then
  printf "\n继续？[y/N] "
  read -r reply
  [[ "$reply" == [yY]* ]] || { echo "已取消，未做任何改动"; exit 0; }
fi

echo ""
# ---------- 1. 退出进程 ----------
if pgrep -f "${APP_NAME}.app/Contents/MacOS/${EXEC_NAME}" >/dev/null 2>&1; then
  pkill -f "${APP_NAME}.app/Contents/MacOS/${EXEC_NAME}" 2>/dev/null || true
  sleep 1
  echo "✓ 已退出进程"
else
  echo "· 进程本来就没在跑"
fi

# ---------- 2. App 移到废纸篓 ----------
for p in "${APP_PATHS[@]}"; do
  dest="${TRASH_DIR}/$(basename "$p")"
  if [[ -e "$dest" ]]; then
    dest="${dest}.$(date +%Y%m%d-%H%M%S)"
  fi
  mv "$p" "$dest"
  echo "✓ 已移到废纸篓: $p"
done

# ---------- 3. 钥匙串 ----------
for svc in "$BUNDLE_ID" "$LEGACY_SERVICE"; do
  if security delete-generic-password -s "$svc" -a "$ACCOUNT" >/dev/null 2>&1; then
    echo "✓ 已删除钥匙串条目: $svc"
  else
    echo "· 钥匙串里没有: $svc"
  fi
done

# ---------- 4. 配置目录 ----------
if [[ -d "$CONFIG_DIR" ]]; then
  rm -rf "$CONFIG_DIR"
  echo "✓ 已删除配置目录: $CONFIG_DIR"
else
  echo "· 配置目录本来就不存在"
fi

# ---------- 5. 平台登录态 / 缓存 ----------
for d in "$WEBKIT_DIR" "$CACHES_DIR"; do
  if [[ -d "$d" ]]; then
    rm -rf "$d"
    echo "✓ 已删除: $d"
  else
    echo "· 不存在: $d"
  fi
done

# ---------- 复查 ----------
echo ""
echo "复查："
if security find-generic-password -s "$BUNDLE_ID" -a "$ACCOUNT" >/dev/null 2>&1; then
  echo "  ✗ 钥匙串条目仍然存在，请到「钥匙串访问」里搜索 openai-api-dashboard 手动删除"
else
  echo "  ✓ 钥匙串：干净"
fi
if [[ -d "$CONFIG_DIR" ]]; then
  echo "  ✗ 配置目录仍然存在"
else
  echo "  ✓ 配置：干净"
fi
if [[ -d "$WEBKIT_DIR" ]]; then
  echo "  ✗ 登录态目录仍然存在"
else
  echo "  ✓ 登录态：干净"
fi

remaining=0
for p in "/Applications/${APP_NAME}.app" "${HOME}/Applications/${APP_NAME}.app"; do
  [[ -d "$p" ]] && remaining=1
done
if [[ $remaining -eq 1 ]]; then
  echo "  ✗ 仍有 App 残留在标准位置"
else
  echo "  ✓ App：干净（可在废纸篓里恢复）"
fi
