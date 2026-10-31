# 项目规约 · OpenAI API 仪表盘

本文件是本项目的强制约定，任何代码改动都必须遵守。

---

## 1. 交付规约：每次改动都要出新版本 DMG

**任何优化、修复、新功能，最终交付物一律是新版本 DMG。**
不接受"代码改完了但没打包"，也不接受复用旧版本的 DMG。

固定收尾流程：

1. 修改 `Resources/Info.plist` 里的版本号：
   - 修 bug / 小优化 → `CFBundleShortVersionString` 末位 +1（1.1.0 → 1.1.1）
   - 新功能 / 界面重做 → 次位 +1（1.1.x → 1.2.0）
   - `CFBundleVersion`（构建号）每次都必须 +1，只增不减
2. 执行 `./make-dmg.sh --rebuild`
3. 校验：`hdiutil verify` 通过、`codesign --verify` 通过、架构含 `x86_64` 与 `arm64`
4. 产物必须留在 `dist/`，历史版本不删除

## 2. 架构规约：必须同时支持 Intel 与 M 芯片

**发布的 DMG 必须是通用二进制（universal binary），包含 `x86_64` + `arm64` 两个架构。**

- 禁止发布单架构包；不允许要求用户安装 Rosetta
- 两个架构必须是**各自独立交叉编译**后 `lipo -create` 合并，不能是同一份拷贝两次
- 最低系统版本 `LSMinimumSystemVersion = 14.0`（macOS Sonoma），`minos` 需与此一致
- 每次打包后必须检查：
  ```bash
  lipo -archs "dist/.../OpenAI API 仪表盘.app/Contents/MacOS/OpenAIBar"
  # 期望输出：x86_64 arm64
  ```
- 依赖只能来自 `/usr/lib`、`/System/Library`；`otool -L` 中 `@rpath` 依赖数必须为 0

构建方式（本机只有 Command Line Tools，`swift build --arch a --arch b` 不可用）：

```bash
swift build -c release --disable-sandbox --triple x86_64-apple-macosx14.0 --scratch-path .build/x86_64
swift build -c release --disable-sandbox --triple arm64-apple-macosx14.0  --scratch-path .build/arm64
lipo -create .build/x86_64/release/OpenAIBar .build/arm64/release/OpenAIBar -output .build/universal/OpenAIBar
```

## 3. 界面规范（Liquid Glass）

视觉语言统一为 macOS 26 / iOS 26 起的 Liquid Glass，新增界面一律沿用，不要混回扁平分隔线风格。

- 三层结构：`PanelBackground`（底色渐变 + 顶部柔光）→ 玻璃卡片 → 内容
- 卡片一律走 `.glassCard(radius:elevated:)`：上亮下暗的填充 + 左上白亮、右下收暗的镜面描边 + 双层柔影
- 大圆角：面板 24 / 小卡片 20 / 输入框 10；卡片之间用 `UI.gap` 留缝靠阴影分层，*不用分隔线切块*
- 数字用 `design: .rounded` + `monospacedDigit()`；主数字 38pt，KPI 17pt，正文 11.5–12.5pt
- 颜色只从 `Color.brand(_:)` / `Glass.*` 取，不散写十六进制
- 浅色与深色必须分别看一遍截图再交付

### 交互规范

- *菜单面板与设置窗口互斥*：打开设置前调 `MenuBarPanel.closeIfOpen()`；面板出现时调 `SettingsWindow.close()`
- 设置里点「保存」= 写配置 + 关窗（`SettingsWindow.close()`），不再留在页面上弹"已保存"
- 面板内容超过屏幕可视高度时靠测量自动变滚动（`BodyHeightKey` + `UI.maxBodyHeight`），不允许被窗口裁掉

### 图标规范

- 菜单栏图标三种状态 *共用同一套几何*（开口环 + 指针 + 轴点），只改指针，不换图形
- 正常 55°；未配置不画指针；出错指针压到 270°
- *禁止*用 `exclamationmark.triangle` 之类的 SF Symbol 顶替状态 —— 图标在菜单栏上跳变很刺眼
- 状态对照图：`swiftc -O Sources/OpenAIBar/Logo.swift Tools/menubardemo/main.swift -o .build/membardemo && .build/membardemo docs/menubar.png`

## 4. 安全规约

- **绝不把 API Key 写进代码、配置或仓库**。Key 只存 macOS 钥匙串（service = `com.xbguan.openai-api-dashboard`，account = `openai-admin-key`）
- 配置文件只允许保存非敏感项（备注名、项目 ID、刷新间隔）
- 卸载必须能清干净：用 `./uninstall.sh`

## 5. 目录与路径

- 项目根：`/Users/xbguan/project/grocery/code/OpenAI API 仪表盘`
- 源码：`Sources/OpenAIBar/`；工具：`Tools/`；产物：`.build/bundle/*.app`、`dist/*.dmg`
- 文档以 `README.adoc` 为源，改完渲染：`asciidoctor README.adoc -o docs/README.html -a imagesdir=.`

## 6. 本机构建环境的坑（已踩过，别重踩）

| 现象 | 原因 / 对策 |
|---|---|
| `xcbuild executable does not exist` | 多架构参数走 xcbuild，CLT 没有。用 `--triple` 分别编译 |
| 项目根下 `.app` 写入被拒（`Operation not permitted`） | 宿主安全策略保护 `.app` 路径。**不要往项目根拷 .app**，直接用 `.build/bundle/*.app` |
| `ditto` 往 DMG 里拷 App 失败，报 `.BC.T_xxx` file-delete 被拒 | ditto 走"临时文件 + rename"。改用 `cp -R`，直接写入不出临时文件 |
| `hdiutil create -size 40m -format UDRW` 报 `-format requires -srcfolder` | 给了 `-size` 就是空读写镜像，去掉 `-format` |
| AppleScript 操作 Finder 一律 `-10004` | 自动化权限未授予，`create-dmg` 一类工具不可用。DMG 窗口布局用 `Tools/dmg-layout.py` 手写 `.DS_Store` |
| 打包/编译在沙箱内失败 | 项目在 WorkBuddy 工作区外，构建需绕过沙箱（`--disable-sandbox` / 前台越权执行） |
| 命令行访问 api.openai.com 失败 | 必须带代理：`--proxy http://127.0.0.1:7899` |

## 7. 签名与分发

- 本机只有 ad-hoc 签名（`codesign --sign -`），无 Apple 开发者证书，做不了公证
- 用户首次打开需右键 → 打开，或 `xattr -cr "/Applications/OpenAI API 仪表盘.app"`
- 这段说明已印在 DMG 背景图底部，无需额外告知

## 8. 余额读取（平台登录态）

余额是这个项目唯一一个「官方不给 API」的数据，实现约束很硬，改动前先读这一节。

**已实测的结论（2026-10-31）**

- `GET /v1/dashboard/billing/credit_grants` 用任何 API Key 都是 403：
  `must be made with a session key (that is, it can only be made from the browser)`
- `/v1/organization/credits`、`/v1/credits`、`/v1/organization/billing/credit_grants`、`spend_limits`、`limits` 全部 404
- 带平台登录态请求同一接口 → 200，返回 `total_granted / total_used / total_available`
- 结论：*换 key 类型无解*，只能用平台登录态

**实现方式（`Sources/OpenAIBar/CreditBridge.swift`）**

- 隐藏 WKWebView（挂在一个屏幕外的 borderless 窗口里，纯无窗口会被节流）打开 `platform.openai.com/settings/organization/billing/overview`
- `WKUserScript` 在 `.atDocumentStart` 注入钩子，包住 `fetch` 与 `XMLHttpRequest`，命中 `credit_grants` 就把**响应体**通过 `webkit.messageHandlers.credit` 回传
- 另有一条 DOM 兜底：正则在页面文字里找 `Credit remaining $12.34`，接口改版时不至于完全失效
- ⚠️ **不要自己发这个请求**：从页面上下文 fetch `api.openai.com` 会被 CORS 挡掉（实测 `Load failed`）。只能「截」不能「发」
- 登录由用户在独立窗口里手动完成（`CreditLoginWindow`），App *不接触* 账号密码、验证码、MFA

**存储与隐私**

- 登录态在 `~/Library/WebKit/com.xbguan.openai-api-dashboard`，由 WebKit 管理；App 不读、不导出、不上传
- 设置里「退出登录」会 `removeData(ofTypes: allWebsiteDataTypes)`；`uninstall.sh` 一并删除该目录
- 该功能默认关闭（`AppConfig.showCredit = false`），必须用户显式开启

**已知会失效的情形**

- 用户清了登录态 / 会话过期 → 卡片变成「需要登录」，点按钮重登
- OpenAI 改页面结构 → DOM 兜底失效，但接口钩子通常还在
- 接口改名 → 两条路同时失效，表现为读取超时（30s），需按新接口名更新 `hookJS` 里的 `isCreditURL`

