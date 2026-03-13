import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'agent_client.dart';

class VibeScreen extends StatefulWidget {
  const VibeScreen({super.key});

  @override
  _VibeScreenState createState() => _VibeScreenState();
}

class _VibeScreenState extends State<VibeScreen> {
  final TextEditingController _ipController = TextEditingController(text: '10.0.2.2');
  final TextEditingController _tokenController = TextEditingController(text: 'vibe-666888');
  
  // 固定各个面板的输入框
  final TextEditingController _claudeInput = TextEditingController();
  final TextEditingController _geminiInput = TextEditingController();
  final TextEditingController _terminalInput = TextEditingController();
  final TextEditingController _searchQuery = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    final p = context.read<AgentClientProvider>();
    p.confirmRequests.listen((data) => _showConfirm(data));
    p.notifications.listen((n) => _showTopToast(n['msg'], n['type'] == 'success'));
  }

  void _showTopToast(String msg, bool isSuccess) {
    if (!mounted) return;
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (ctx) => Positioned(
        top: 60, left: 24, right: 24,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: isSuccess ? Colors.green.shade800 : Colors.red.shade800,
              borderRadius: BorderRadius.circular(30),
              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)],
            ),
            child: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 3), () => entry.remove());
  }

  void _showConfirm(dynamic data) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: const Text("AI 权限授权"),
        content: Text(data['prompt'] ?? "确认执行操作？"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("拒绝")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB300)),
            onPressed: () {
              context.read<AgentClientProvider>().sendAction("${data['ai']}.confirm", {"approve": true});
              Navigator.pop(ctx);
            },
            child: const Text("批准", style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AgentClientProvider>();
    if (!provider.isConnected) return _buildLogin(provider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text("VIBE COMMANDER", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.5)),
          centerTitle: true,
          bottom: const TabBar(
            indicatorColor: Color(0xFFFFB300),
            labelColor: Color(0xFFFFB300),
            tabs: [
              Tab(text: "CLAUDE"),
              Tab(text: "GEMINI"),
              Tab(text: "TERMINAL"),
            ],
          ),
        ),
        drawer: _buildFixedDrawer(provider),
        body: Column(
          children: [
            // 1. 可视化主展示区 (弹性)
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                child: provider.lastResult != null
                    ? _buildVisualization(provider)
                    : _buildWelcomePlaceholder(),
              ),
            ),
            const Divider(height: 1, color: Colors.white10),
            // 2. 交互操作区 (固定高度 180)
            Container(
              height: 180,
              color: const Color(0xFF121212),
              child: TabBarView(
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildAIPage("claude", _claudeInput, provider),
                  _buildAIPage("gemini", _geminiInput, provider),
                  _buildTerminalPage(provider),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomePlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.hub_rounded, size: 64, color: Colors.white.withOpacity(0.05)),
          const SizedBox(height: 16),
          const Text("COMMAND CENTER READY", style: TextStyle(color: Colors.white10, letterSpacing: 2, fontSize: 12)),
        ],
      ),
    );
  }

  // AI 页面骨架 (固定)
  Widget _buildAIPage(String id, TextEditingController controller, AgentClientProvider p) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              _miniBtn("启动", () => p.sendAction("$id.start", {})),
              const SizedBox(width: 8),
              _miniBtn("停止", () => p.sendAction("$id.stop", {}), isDanger: true),
            ],
          ),
          const Spacer(),
          _buildChatInput(id, controller, p),
        ],
      ),
    );
  }

  // 终端页面骨架 (固定)
  Widget _buildTerminalPage(AgentClientProvider p) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              _miniBtn("清空日志", () => p.logs.clear()),
              const SizedBox(width: 8),
              _miniBtn("进程状态", () => p.sendAction("terminal.exec", {"cmd": "ps"})),
            ],
          ),
          const Spacer(),
          _buildChatInput("terminal", _terminalInput, p, hint: "输入命令直接运行..."),
        ],
      ),
    );
  }

  Widget _miniBtn(String label, VoidCallback onPressed, {bool isDanger = false}) {
    return ActionChip(
      visualDensity: VisualDensity.compact,
      backgroundColor: isDanger ? Colors.red.withOpacity(0.1) : const Color(0xFF2A2A2A),
      side: BorderSide(color: isDanger ? Colors.red.withOpacity(0.3) : const Color(0xFFFFB300).withOpacity(0.3)),
      label: Text(label, style: TextStyle(fontSize: 10, color: isDanger ? Colors.redAccent : const Color(0xFFFFB300))),
      onPressed: onPressed,
    );
  }

  Widget _buildChatInput(String id, TextEditingController controller, AgentClientProvider p, {String? hint}) {
    return Container(
      height: 50,
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(25)),
      child: TextField(
        controller: controller,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: hint ?? "输入需求并发送...",
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          border: InputBorder.none,
          suffixIcon: IconButton(
            icon: const Icon(Icons.send_rounded, color: Color(0xFFFFB300)),
            onPressed: () {
              if (controller.text.isEmpty) return;
              final actionId = id == "terminal" ? "terminal.send" : "$id.send";
              p.sendAction(actionId, {"text": controller.text, "data": controller.text});
              controller.clear();
            },
          ),
        ),
      ),
    );
  }

  // 固定侧边栏
  Widget _buildFixedDrawer(AgentClientProvider p) {
    return Drawer(
      backgroundColor: const Color(0xFF1A1A1A),
      child: Column(children: [
        const DrawerHeader(child: Icon(Icons.rocket_launch, size: 48, color: Color(0xFFFFB300))),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchQuery,
            decoration: const InputDecoration(labelText: "搜索或路径", hintText: "main.go"),
          ),
        ),
        ListTile(title: const Text("探测项目环境"), leading: const Icon(Icons.analytics, color: Color(0xFFFFB300)), onTap: () => p.sendAction("project.detect", {})),
        ListTile(title: const Text("列出根目录"), leading: const Icon(Icons.folder, color: Color(0xFFFFB300)), onTap: () => p.sendAction("fs.list", {"path": "."})),
        ListTile(title: const Text("全局搜索"), leading: const Icon(Icons.search, color: Color(0xFFFFB300)), onTap: () => p.sendAction("fs.search", {"q": _searchQuery.text})),
        const Divider(color: Colors.white10),
        ListTile(title: const Text("读取指定文件"), leading: const Icon(Icons.file_open, color: Color(0xFFFFB300)), onTap: () => p.sendAction("fs.read", {"path": _searchQuery.text})),
      ]),
    );
  }

  Widget _buildVisualization(AgentClientProvider p) {
    final res = p.lastResult!;
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(0.05))),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.white.withOpacity(0.05),
            child: Row(children: [
              Text(res['type'].toString().toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFFFB300))),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => p.clearResult()),
            ]),
          ),
          Expanded(
            child: res['type'] == 'file_content'
                ? SingleChildScrollView(padding: const EdgeInsets.all(16), child: Text(res['content'], style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white70, height: 1.4)))
                : ListView.builder(
                    itemCount: ((res['items'] ?? res['hits'] ?? []) as List).length,
                    itemBuilder: (c, i) {
                      final item = (res['items'] ?? res['hits'])[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.file_present, size: 18, color: Colors.amber),
                        title: Text(item, style: const TextStyle(fontSize: 13)),
                        onTap: () => p.sendAction("fs.read", {"path": item}),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogin(AgentClientProvider p) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF2D2D2D), Color(0xFF121212)], begin: Alignment.topCenter)),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.hub_rounded, size: 80, color: Color(0xFFFFB300)),
              const SizedBox(height: 40),
              TextField(controller: _ipController, decoration: const InputDecoration(labelText: "服务器 IP")),
              const SizedBox(height: 16),
              TextField(controller: _tokenController, decoration: const InputDecoration(labelText: "Token")),
              const SizedBox(height: 40),
              SizedBox(width: double.infinity, height: 56, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB300), foregroundColor: Colors.black), onPressed: () => p.connect(_ipController.text.trim(), 9999, token: _tokenController.text.trim()), child: const Text("CONNECT CENTER", style: TextStyle(fontWeight: FontWeight.bold)))),
            ]),
          ),
        ),
      ),
    );
  }
}
