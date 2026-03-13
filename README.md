# RemoteVC Agent

`remotevc-agent` 是一个轻量级的后端代理工具，旨在通过移动端或远程 UI 高效控制本地开发环境，实现 **Vibecoding** (AI 辅助编程) 和项目管理。

它将复杂的本地操作（进程管理、PTY 终端、文件系统、AI CLI）抽象为简单的 **流式 JSON 协议**，让你可以通过手机轻松指挥电脑上的 AI 工具（如 Claude, Gemini）编写代码。

## 🚀 核心特性

- 🤖 **多 AI 引擎支持**: 同时兼容 `claude` CLI 和 `gemini-cli`。支持流式输出捕获和自动权限审批。
- 📟 **全功能 PTY 终端**: 内置伪终端 (Pseudo-Terminal) 支持。保留 ANSI 颜色、进度条，支持运行 `vim`, `top`, `python` 等交互式命令。
- 📂 **安全文件系统**: 提供受限的 `fs.read`, `fs.write`, `fs.list` 和 `fs.search` 接口。严格防止目录穿越攻击。
- 📱 **移动端优先的 UI 协议**: 采用声明式 UI 架构。Agent 告诉客户端该显示哪些按钮和输入框，客户端只需渲染，无需关心底层命令。
- 🔔 **主动权限通知**: 当 AI 需要执行敏感操作（如删除文件）时，Agent 会通过 Webhook (如 Bark) 向手机发送系统级推送通知。
- 🏗️ **项目感知**: 自动探测项目类型 (Go, Node, Python, Rust)，并动态调整控制面板。

## 🛠️ 协议说明

Agent 使用标准输入输出 (stdin/stdout) 进行通信，采用 **Framed JSON** 格式：
- **Header**: 4 字节大端序整数，代表 Payload 长度。
- **Payload**: JSON 编码的 `Envelope` 对象。

### 示例 Envelope
```json
{
  "seq": 1,
  "type": "ui.action",
  "payload": {
    "id": "claude.start",
    "params": {}
  }
}
```

## ⚙️ 环境变量

- `REMOTEVC_NOTIFY_URL`: 推送服务 URL (例如: `https://api.day.app/yourkey/`)。
- `REMOTEVC_CLAUDE_CMD`: 自定义 Claude CLI 命令路径。
- `REMOTEVC_CONFIRM_RULES`: 自动审批规则 JSON 文件的路径。

## 📦 安装与运行

1. 确保已安装 Go 1.22+。
2. 确保 `claude` 和 `gemini` 已在 PATH 中。
3. 编译并运行：
```bash
go build -o remotevc-agent ./cmd/remotevc-agent
./remotevc-agent --stdio
```

---

## 📱 移动端实现 (Flutter 逻辑预览)

配套的 Flutter 客户端需要实现以下逻辑：
1. **Socket 连接**: 连接到 Agent 的标准输入输出。
2. **帧解码器**: 读取前 4 字节，然后读取对应长度的 JSON。
3. **动态渲染器**: 循环 `ui.render` 事件中的 `panels` 列表，将其映射为 `ElevatedButton`, `TextField` 等组件。
# Remote-VC
