# GPT流量监控

A lightweight macOS menu-bar app for checking **ChatGPT Work + Codex quota** at a glance.

> `⌛ 周 84% · 5h 54%`

**当前版本：** `0.3.28` (Build 41)  
**运行要求：** macOS 13+ · Apple Silicon  
**状态：** Public Preview

GPT流量监控常驻 macOS 菜单栏，把 **本周额度** 和 **滚动 5 小时额度** 放在状态栏和 Hover 面板里。无需反复打开 ChatGPT 或 Codex，就能看到剩余额度、重置倒计时和具体重置时间。

> 本项目为独立社区项目，不是 OpenAI 官方产品。

## 下载

普通用户建议直接从 [GitHub Releases](https://github.com/chengzi96/gpt-quota-monitor-macos/releases/latest) 下载预编译版本：

`GPT流量监控-0.3.28-macOS13+.zip`

解压后将 `GPT流量监控.app` 拖到“应用程序”即可。

### 第一次打开

当前 Public Preview 使用 **ad-hoc 签名**，尚未使用 Apple Developer ID 进行公证。因此第一次打开时，macOS 可能提示无法验证开发者。

可以先在 Finder 中右键 App → **打开**。如果系统仍然拦截，可前往：

**系统设置 → 隐私与安全性 → 仍要打开**

后续如果项目进行 Developer ID 签名和 Notarization，这一步就不再需要。

## 系统兼容性

| macOS | 支持情况 | 视觉效果 |
| --- | --- | --- |
| macOS 26+ | ✅ | 原生 Liquid Glass |
| macOS 15 | ✅ | 系统 Material 毛玻璃 |
| macOS 14 | ✅ | 系统 Material 毛玻璃 |
| macOS 13 | ✅* | 系统 Material 毛玻璃 |

`*` 二进制最低部署目标设为 macOS 13；GitHub CI 会检查 App 与内置 Codex App Server 的 minOS，并在 macOS 14 ARM runner 上做启动烟测。当前没有 GitHub 托管的 macOS 13 ARM runner，因此 macOS 13 仍建议视为 Public Preview 兼容。

目前只发布 **Apple Silicon** 版本。

## 功能

- 菜单栏直接显示 `周 xx% · 5h xx%`
- 鼠标悬浮状态栏自动打开面板，不需要点击
- 显示本周剩余百分比
- 显示滚动 5 小时剩余百分比
- 显示额度重置倒计时与具体时间
- OpenAI 官方 ChatGPT 浏览器登录
- 自动刷新、手动刷新、Mac 唤醒后刷新
- 刷新失败时保留上一次真实额度，不伪造 `0%`
- 可选低额度系统通知
- 支持登录时自动启动
- macOS 26+ 使用原生 Liquid Glass
- macOS 13–15 自动降级为系统 Material 毛玻璃

## 为什么只显示 Work + Codex？

GPT Chat 的模型限制会随套餐、模型和系统策略变化，目前没有一个稳定统一的“剩余百分比”接口。

GPT流量监控不会：

- 抓取 ChatGPT 网页 DOM
- 读取浏览器 Cookie
- 根据历史使用量猜测剩余额度
- 用估算值冒充真实额度

因此主界面只展示通过 OpenAI Codex App Server 实际返回的 **Work + Codex 共享额度**。

## 隐私

GPT流量监控不会读取：

- ChatGPT 聊天内容或 Prompt
- 浏览器 Cookie / 网页 DOM
- ChatGPT access token / refresh token
- 本地代码
- Codex workspace

ChatGPT 登录、凭据保存、回调和 Token 刷新由 OpenAI 官方 Codex 组件负责。

GPT流量监控本地只保存：

- 软件设置
- 本地额度历史
- 基础运行诊断日志

诊断日志不会记录账号标识、Token、Prompt、聊天内容或代码。

详细说明见 [PRIVACY.md](PRIVACY.md)。

## OpenAI 组件

本项目固定使用：

- OpenAI Codex App Server `0.151.0`
- `aarch64-apple-darwin`
- SHA-256: `09193ef452f35d3558ac5bef21e14d6e3c9763edaa36e6c614126a15fca0ff57`

仓库不直接提交该二进制文件。

源码构建时，脚本只从 OpenAI 官方 GitHub Release 下载固定版本，并在解压前校验 SHA-256。

第三方说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 从源码构建

> 这里的“运行最低版本 macOS 13+”与“构建环境”是两回事。

由于源码同时保留 macOS 26 的 Liquid Glass API，**当前源码构建需要 Xcode / Apple Command Line Tools 26 与 macOS 26 SDK**。  
macOS 13–15 用户不需要安装 Xcode，直接下载 Releases 中的预编译 App 即可。

```bash
git clone https://github.com/chengzi96/gpt-quota-monitor-macos.git
cd gpt-quota-monitor-macos
chmod +x 安装GPT流量监控.command
./安装GPT流量监控.command
```

也可以只构建：

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
```

产物：

```text
dist/GPT流量监控.app
dist/GPT流量监控-0.3.28-macOS13+.zip
```

## 稳定性

`0.3.27` 修复了实际捕获到的状态栏崩溃问题：`UserDefaults.didChangeNotification` 可能从后台线程触发，而状态栏控制器属于 `MainActor`。相关 UI / 状态更新已统一回主线程，避免 Swift 6 actor 检查导致菜单栏进程被 `SIGTRAP` 终止。

`0.3.28` 在此基础上只扩展系统兼容性，不改变额度读取逻辑和状态栏交互。

## 遇到问题

欢迎直接开 GitHub Issue。建议附上：

- macOS 版本
- Mac 芯片型号
- GPT流量监控版本
- 问题出现步骤
- `~/Library/Logs/GPT流量监控/运行诊断.log`

提交日志前可以自行打开检查内容。

## 项目许可证

当前仓库暂未添加项目级开源许可证。源码公开用于查看、测试和反馈；第三方组件仍遵循各自许可证。

如果后续决定开放修改、再分发和二次开发权限，会单独补充项目 License。

## Third-party / Trademark notice

OpenAI, ChatGPT and Codex are trademarks of their respective owner. This project is not affiliated with, endorsed by, or sponsored by OpenAI.
