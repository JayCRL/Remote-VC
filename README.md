# RemoteVC Agent 🛰️

`remotevc-agent` 是一个轻量级的后端代理工具，旨在通过移动端或远程 UI 高效控制本地开发环境，实现真正的 **Vibecoding** (AI 辅助编程) 体验。

它将复杂的本地操作（进程管理、PTY 终端、文件系统、AI CLI）抽象为简单的流式 JSON 协议，让您可以躺在沙发上通过 **Vibe Commander** 移动端指挥电脑上的 Claude 或 Gemini 编写代码。

---

## ✨ 核心特性

- 🤖 **双 AI 引擎**: 深度集成 `claude` CLI 与 `gemini-cli`，支持流式输出与自动权限审批。
- 📱 **本地化 UI 架构**: 移动端采用全固定硬编码布局，告别动态 UI 带来的延迟与不稳定性，实现“秒开”控制体验。
- 🌅 **暖色调控制台**: 针对移动端优化的 Warm Sunset 风格 UI，复古琥珀色终端，极佳的夜间使用体验。
- 🔔 **实时状态感知**: 顶部浮动胶囊提示执行结果，支持可视化查看文件列表、源代码及项目分析报告。
- 🔒 **安全加固**: 内置 Token 鉴权机制与心跳检测，掉线自动回收资源，防止进程跑飞。
- 📟 **真·终端体验**: 支持 PTY (伪终端)，完美保留 ANSI 颜色，可运行 `vim`, `python` 等交互命令。

---

## 🛠️ 快速开始

### 1. 启动后端 (Windows/macOS/Linux)
确保已安装 Go 1.22+，在项目根目录运行：
```powershell
# 编译并启动（默认端口 9999）
go run ./cmd/remotevc-agent/main.go --tcp :9999 --token vibe-666888
```
*启动后，控制台会显示固定的或生成的 AUTH TOKEN。*

### 2. 启动移动端 (Flutter)
1. 进入 `mobile` 目录。
2. 运行 `flutter run`。
3. 在登录页填入服务器 IP 和 Token。

---

## 📱 移动端交互说明

- **仪表盘**: 屏幕中央为动态可视化中心，自动将 JSON 转换为列表或代码面板。
- **交互栏**: 底部固定 180dp 交互区，支持在 Claude, Gemini, Terminal 之间快速切换。
- **侧边栏**: 提供项目探测、全局搜索、目录浏览等高频项目管理工具。
- **通知**: 关键节点（需要审批、任务完成）通过系统级 Webhook 实时推送。

---

## 🏗️ 架构设计

- **Backend**: Go (Framed JSON over TCP/Stdio)
- **Frontend**: Flutter (Provider 状态管理 + 本地化固定布局)
- **Protocol**: 4-byte Length Header + JSON Payload
