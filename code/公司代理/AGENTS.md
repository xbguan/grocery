# 公司代理 · 项目规约

本文件是本项目的强制约定。改动本项目的任何代码前先读一遍，交付前逐条对照。

## 一、任务完成的定义

**只改完代码不算完成。** 每当一轮任务收尾（改了 `Sources/`、`build.sh`、`packaging/` 或图标），
必须走完下面四步，缺一步都视为任务未交付：

1. **升版本号** —— `build.sh` 里的 `VERSION="x.y.z"`（补丁位 +1；涉及界面/功能改动 +1 至次版本位）。
2. **编译 DMG** —— `./build.sh`，产物必须是**本次会话新生成**的
   `dist/公司代理-<VERSION>.dmg`。不允许沿用旧 DMG，也不允许只给出 `.app`。
3. **安装并自检** —— 把新构建装到 `/Applications` 并实际启动确认：
   - 版本号一致：`plutil -p "/Applications/公司代理.app/Contents/Info.plist" | grep -i shortversion`
   - 双架构齐全：`lipo -archs /Applications/公司代理.app/Contents/MacOS/CorpProxyBar`
   - 中继在跑：`nc -z 127.0.0.1 7899`
   - 出口可用：`curl -s -o /dev/null -w "%{http_code}" --max-time 10 -x http://127.0.0.1:7899 https://www.google.com/generate_204` → `204`
4. **提交推送** —— 提交信息写清改了什么、为什么；`git push` 后用 `git log --oneline -1 origin/main` 确认远端已更新。

交付说明里要同时给出：DMG 路径与体积、版本号、架构、提交哈希。

## 二、必须支持 Intel 与 Apple Silicon

内置的 Mac 分两种芯片，**同一个 DMG 要在两边都能原生运行**，不允许交付只含一种架构的包。

| 架构 | 对应机器 | 要求 |
|---|---|---|
| `arm64` | Apple Silicon（M1/M2/M3/M4…） | 原生运行，不依赖 Rosetta |
| `x86_64` | Intel Mac | 原生运行 |

规则：

* 二进制统一用 `swiftc -target <arch>-apple-macos13.0` 分架构编译，再 `lipo -create` 合并成 universal2。
* `build.sh` 已内置强制校验：任一架构缺失 → **直接失败退出**。
  仅在本地临时调试时可用 `ALLOW_SINGLE_ARCH=1 ./build.sh` 降级，且该产物**不得交付**。
* 交付前必须实测 `lipo -archs`，输出需同时包含 `x86_64` 与 `arm64`。
* 最低系统版本维持 `macOS 13.0`，不要为了新 API 抬高门槛；需要新 API 时按 `if #available` 做降级。
* 本机是 Intel，但 SDK 自带 arm64 slice，可直接交叉编译——**不要以"我是 Intel 机器"为理由只编 x86_64**。

## 三、代码与文件约定

* 代码根目录：`/Users/xbguan/project/grocery/code/公司代理/`（仓库根为 `grocery`，勿把源码散落到其他目录）。
* 入口清单：`Sources/*.swift` 会被 `build.sh` 全量编译，新增文件直接放入即可，无需改脚本。
* 文档一律用 **AsciiDoc**（`README.adoc`），改完可用 `asciidoctor README.adoc` 出预览。
* 禁止把编辑器的临时备份文件（如 `AppDelegate.swiftXXXXXX`、`build.shXXXX`）留在目录里。
* 界面文案用简体中文，标点用全角。

## 四、构建脚本约定

* 版本号只有 `VERSION` 一个来源；`Info.plist` 里的版本用 `__VERSION__` 占位符 + `sed` 回填
  （heredoc 不展开变量，写 `${VERSION}` 会原样留在 plist 里）。
* 签名固定 ad-hoc（`codesign --sign -`），不做公证；首次打开需右键 →「打开」。
* 任何会削弱交付质量的降级（单架构、跳过签名、跳过 `hdiutil verify`）都必须显式开关控制，
  默认走严格路径。

## 五、验证与排查提醒

* 界面改动用离屏渲染（`cacheDisplay`）先看排版，比截图快、可重复：
  参考 `/tmp/preview/`、`/tmp/mp/` 下的临时 harness（不入库）。
* 本机（Intel UHD 630 / macOS 14.8.9）`NSVisualEffectView` 的 `behindWindow` 模糊不生效，
  材质会退化成不透明灰——系统菜单同样不透明。做"玻璃"效果前先确认这一点，别反复试错。
* 后台跑测试二进制时若被 `SIGHUP` 杀掉，会触发 App 的退出清理逻辑把**系统代理关掉**；
  测试请用后台任务并 `kill -9`，事后核对 `networksetup -getwebproxy "Wi-Fi"`。
