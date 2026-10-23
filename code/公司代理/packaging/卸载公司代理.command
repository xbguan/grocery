#!/bin/bash
# 公司代理 · 彻底卸载
# 适用场景：App 已经被拖进废纸篓，但配置/日志/开机自启还留在系统里。
# 如果 App 还在，直接用菜单栏「卸载公司代理…」更省事。
set -uo pipefail

APP_PATH="/Applications/公司代理.app"
CONF_DIR="$HOME/.config/corp-proxy"
CODEX_ENV="$HOME/.codex/.env"

cat <<'BANNER'
========================================
  公司代理 · 彻底卸载
========================================
将要清理：
  · 关闭系统代理，把 ~/.codex/.env 改回直连
  · 停止 App 与本地中继，注销开机自启
  · 删除 ~/.config/corp-proxy（含代理账号密码）
  · 删除日志、偏好、缓存、LaunchAgent
  · 删除 /Applications/公司代理.app
BANNER
echo
printf '确认执行？(输入 y 回车) '
read -r ans
[ "$ans" = "y" ] || { echo "已取消，未做任何改动。"; exit 0; }
echo

# 1) 关闭系统代理（所有网络服务）
echo "→ 关闭系统代理"
while IFS= read -r svc; do
  [ -z "$svc" ] && continue
  case "$svc" in \**) continue ;; esac
  networksetup -setwebproxystate "$svc" off >/dev/null 2>&1
  networksetup -setsecurewebproxystate "$svc" off >/dev/null 2>&1
  networksetup -setsocksfirewallproxystate "$svc" off >/dev/null 2>&1
done < <(networksetup -listallnetworkservices 2>/dev/null | tail -n +2)

# 2) Codex 环境变量改回直连
if [ -f "$CODEX_ENV" ]; then
  echo "→ 还原 $CODEX_ENV"
  tmp=$(mktemp "${TMPDIR:-/tmp}/corpenv.XXXXXX")
  awk '
    /^#?[ \t]*(HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|http_proxy|https_proxy|all_proxy)=/ { next }
    /^# --- corp-proxy: / { next }
    { buf[NR]=$0; if (NF) last=NR }
    END { for (i=1; i<=last; i++) print buf[i] }
  ' "$CODEX_ENV" > "$tmp"
  { echo ""; echo "# --- corp-proxy: OFF -> Codex 直连，未配置代理 ---"; } >> "$tmp"
  cat "$tmp" > "$CODEX_ENV" && rm -f "$tmp"
  chmod 600 "$CODEX_ENV" 2>/dev/null
fi

# 3) 停进程、注销开机自启
echo "→ 停止 App 与本地中继"
pkill -f "公司代理.app/Contents/MacOS/CorpProxyBar" 2>/dev/null || true
pkill -f "corp-proxy-relay" 2>/dev/null || true
sleep 1

echo "→ 注销开机自启"
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/local.xbguan.corpproxy.plist" 2>/dev/null || true
osascript -e 'tell application "System Events" to delete login item "公司代理"' >/dev/null 2>&1 || true
rm -f "$HOME/Library/LaunchAgents/local.xbguan.corpproxy.plist"
rm -f "$HOME/Library/LaunchAgents/local.xbguan.corpproxy.relay.plist"

# 4) 删除文件
echo "→ 删除配置与残留文件"
rm -rf "$CONF_DIR"
rm -f  "$HOME/Library/Logs/corp-proxy-relay.log"
rm -f  "$HOME/Library/Preferences/local.xbguan.corpproxy.plist"
rm -rf "$HOME/Library/Saved Application State/local.xbguan.corpproxy.savedState"
rm -rf "$HOME/Library/Caches/local.xbguan.corpproxy"
rm -rf "$HOME/Library/HTTPStorages/local.xbguan.corpproxy"
rm -f  "$HOME/Library/HTTPStorages/local.xbguan.corpproxy.binarycookies"
rm -f  "$HOME/.local/bin/corp-proxy" "$HOME/.local/bin/corp-proxy-relay"
rm -f  "/usr/local/bin/corp-proxy"

# 5) 删除 App
if [ -d "$APP_PATH" ]; then
  echo "→ 删除 $APP_PATH"
  rm -rf "$APP_PATH"
fi

echo
echo "✓ 清理完成。"
echo "  注意：~/.zshrc 里若还有 proxy_on / proxy_status 等函数，它们会失效，请自行删除。"
echo
printf '按回车关闭此窗口… '
read -r _
