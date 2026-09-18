# GPT流量监控

A lightweight macOS menu-bar app for checking **ChatGPT Work + Codex quota** at a glance.

> `⌛ 周 84% · 5h 54%`

**Current version:** `0.3.27` (Build 40)  
**Platform:** macOS 26+ · Apple Silicon  
**Status:** public preview

GPT流量监控常驻 macOS 菜单栏，把本周额度和滚动 5 小时额度放到一个很轻的 Hover 面板里。它使用 OpenAI 官方 Codex App Server 完成浏览器登录和额度读取，不抓 ChatGPT 网页、Cookie，也不读取聊天内容。

> This is an independent community project and is not an official OpenAI product.

## 功能 / Features

- 菜单栏直接显示 `周 xx% · 5h xx%`
- 鼠标悬浮状态栏即可打开面板，无需点击
- 分别显示本周、近 5 小时剩余额度
- 显示进度、状态、重置倒计时和具体重置时间
- OpenAI 官方浏览器登录
- 自动刷新、手动刷新、Mac 唤醒后刷新
- 刷新失败时保留上一次真实额度，不显示伪造的 `0%`
- 可选低额度系统通知
- 登录启动、菜单栏、提醒、数据等设置
- macOS 26 原生 Liquid Glass 风格

## 为什么只显示 Work + Codex？

GPT Chat 的模型限制会随套餐、模型和系统策略变化，目前没有一个稳定统一的“剩余百分比”接口。本项目不会抓网页 DOM / Cookie，也不会用估算值冒充真实额度，因此主界面只展示通过 Codex App Server 可读取到的真实额度窗口。

## 安装

### 方式一：从源码一键安装

需要：

- macOS 26 或更高
- Apple Silicon Mac
- Xcode / Apple Command Line Tools 26
- 首次构建时可访问 GitHub（只用于下载固定版本的 OpenAI Codex App Server）

```bash
git clone https://github.com/chengzi96/gpt-quota-monitor-macos.git
cd gpt-quota-monitor-macos
chmod +x 安装GPT流量监控.command
./安装GPT流量监控.command
```

安装器会：

1. 检查 macOS / Apple Silicon / Swift SDK
2. 从 OpenAI 官方 GitHub Release 下载固定的 Codex App Server `0.151.0`
3. 校验 SHA-256
4. 本机编译并 ad-hoc 签名
5. 安装到 `/Applications/GPT流量监控.app`
6. 原位替换同 Bundle ID 的旧版本，不删除已有设置和本地历史

### 方式二：只构建 App

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
```

产物在：

```text
dist/GPT流量监控.app
dist/GPT流量监控-0.3.27-macOS.zip
```

## OpenAI 组件

本项目固定使用：

- OpenAI Codex App Server `0.151.0`
- `aarch64-apple-darwin`
- SHA-256: `09193ef452f35d3558ac5bef21e14d6e3c9763edaa36e6c614126a15fca0ff57`

仓库**不直接提交该二进制压缩包**。构建脚本只从 OpenAI 官方 GitHub Release 下载，并在解压前校验 SHA-256。第三方说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 隐私

本项目不会读取：

- ChatGPT 聊天内容或 Prompt
- 浏览器 Cookie / 网页 DOM
- ChatGPT access token / refresh token
- 本地代码或 Codex workspace

登录凭据、回调和令牌刷新由 OpenAI Codex 组件管理。更多信息见 [PRIVACY.md](PRIVACY.md)。

## 稳定性

`0.3.27` 修复了一个实际崩溃问题：`UserDefaults.didChangeNotification` 可能从后台线程触发，而状态栏控制器属于 `MainActor`。现在相关 UI/状态更新统一回到主线程，避免 Swift 6 actor 检查导致菜单栏进程被 `SIGTRAP` 终止。

如遇问题，欢迎直接开 GitHub Issue。最好附上：

- macOS 版本
- Mac 芯片型号
- App 版本
- 问题出现步骤
- `~/Library/Logs/GPT流量监控/运行诊断.log`（提交前可自行检查内容）

## 开发

```bash
swift test
swift run
```

源码调试时如需手动指定本地 app-server：

```bash
AIQUOTABAR_ALLOW_CODEX_OVERRIDE=1 \
CODEX_APP_SERVER_PATH=/absolute/path/to/codex-app-server \
swift run
```

## 项目许可证

当前仓库暂未添加项目级开源许可证。源码公开用于查看、测试和反馈；第三方组件仍遵循各自许可证。

如果后续决定开放修改、再分发和二次开发权限，会单独补充项目 License。

## Third-party / Trademark notice

OpenAI, ChatGPT and Codex are trademarks of their respective owner. This project is not affiliated with, endorsed by, or sponsored by OpenAI.
