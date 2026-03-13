# RemoteVC Agent 🛰️

`remotevc-agent` 是一个轻量级的后端代理工具，旨在通过移动端或远程 UI 高效控制本地开发环境，实现真正的 **Vibecoding** (AI 辅助编程) 体验。

它将复杂的本地操作（进程管理、PTY 终端、文件系统、AI CLI）抽象为简单的流式 JSON 协议，让您可以躺在沙发上指挥电脑上的 Claude 或 Gemini 编写代码。

---

## ✨ 核心特性

- 🤖 **双 AI 引擎**: 深度集成 `claude` CLI 与 `gemini-cli`，支持流式输出与自动权限审批。
- 暖色调控制台: 针对移动端优化的暖色调 UI，复古琥珀色终端，极佳的夜间使用体验。
- 🔔 **主动推送通知**: 关键节点（需要审批、任务完成）通过 Webhook (如 Bark) 实时推送到手机。
- 🔒 **安全加固**: 内置 Token 鉴权机制与心跳检测，掉线自动回收资源，防止进程跑飞。
- 📟 **真·终端体验**: 支持 PTY (伪终端)，完美保留 ANSI 颜色，可运行 `vim`, `python` 等交互命令。
- 📂 **安全文件管理**: 受限的文件系统访问，严格防止目录穿越攻击。

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
2. 修改 `lib/vibe_screen.dart` 中的默认 IP（可选）。
3. 运行 `flutter run`。

---

## 📱 移动端交互说明

- **连接**: 填入电脑局域网 IP 与 Token 即可连接。
- **审批**: AI 需要读取文件或运行脚本时，手机会收到推送并弹出确认窗口。
- **终端**: 顶部琥珀色视窗实时显示 AI 的思考过程与控制台输出。
- **面板**: 动态加载后端功能，支持一键发送重构指令、搜索文件、探测项目类型。

---

## ⚙️ 环境变量

| 变量名 | 说明 |
| :--- | :--- |
| `REMOTEVC_NOTIFY_URL` | Webhook 通知地址 (如 Bark URL) |
| `REMOTEVC_CLAUDE_CMD` | 自定义 Claude 命令路径 |
| `REMOTEVC_CONFIRM_RULES` | 自动审批规则 JSON 路径 |

---

## 🏗️ 架构设计

- **Backend**: Go (Framed JSON over TCP/Stdio)
- **Frontend**: Flutter (Provider 状态管理 + 动态 UI 渲染)
- **Protocol**: 4-byte Length Header + JSON Payload
