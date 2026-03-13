import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'agent_client.dart';

class VibeScreen extends StatefulWidget {
  const VibeScreen({super.key});

  @override
  _VibeScreenState createState() => _VibeScreenState();
}

class _VibeScreenState extends State<VibeScreen> {
  final Map<String, TextEditingController> _inputControllers = {};
  final TextEditingController _ipController = TextEditingController(text: '127.0.0.1');
  final TextEditingController _tokenController = TextEditingController();
  final ScrollController _logScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listenForConfirms();
    });
  }

  void _listenForConfirms() {
    final provider = context.read<AgentClientProvider>();
    provider.confirmRequests.listen((payload) {
      _showConfirmDialog(payload);
    });
  }

  void _showConfirmDialog(Map<String, dynamic> payload) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.security, color: Colors.orangeAccent),
            SizedBox(width: 8),
            Text("安全审批请求", style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(payload['prompt'] ?? "AI 正在等待您的确认权限。", style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () {
              context.read<AgentClientProvider>().sendAction("${payload['ai']}.confirm", {"approve": false});
              Navigator.pop(ctx);
            },
            child: const Text("拒绝执行", style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FF41)),
            onPressed: () {
              context.read<AgentClientProvider>().sendAction("${payload['ai']}.confirm", {"approve": true});
              Navigator.pop(ctx);
            },
            child: const Text("批准执行", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AgentClientProvider>();

    if (!provider.isConnected) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0A0A0A), Color(0xFF1E1E1E)],
            ),
          ),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.rocket_launch, size: 80, color: Color(0xFF00FF41)),
                  const SizedBox(height: 24),
                  const Text("Vibe 指挥中心", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.white)),
                  const SizedBox(height: 8),
                  const Text("随时随地指挥您的 AI 进行 Vibecoding", style: TextStyle(color: Colors.white38)),
                  const SizedBox(height: 48),
                  _buildLoginCard(provider),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.hub, size: 20, color: Color(0xFF00FF41)),
            const SizedBox(width: 8),
            const Text("指挥中心", style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF00FF41).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF00FF41).withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.circle, size: 8, color: Color(0xFF00FF41)),
                  SizedBox(width: 4),
                  Text("已连接", style: TextStyle(fontSize: 10, color: Color(0xFF00FF41))),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "刷新目录",
            onPressed: () => provider.sendAction("fs.list", {}),
          ),
        ],
      ),
      body: Column(
        children: [
          // 终端视窗
          Container(
            height: 200,
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.terminal, size: 14, color: Colors.white38),
                      SizedBox(width: 8),
                      Text("实时日志回显 (stdout)", style: TextStyle(fontSize: 10, color: Colors.white38)),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _logScroll,
                    padding: const EdgeInsets.all(8),
                    itemCount: provider.logs.length,
                    itemBuilder: (ctx, i) => Text(
                      provider.logs[i],
                      style: const TextStyle(color: Color(0xFF00FF41), fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 动态功能面板
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: provider.panels.length,
              itemBuilder: (ctx, i) => _buildPanel(provider.panels[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginCard(AgentClientProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.computer),
                labelText: "Agent IP 地址",
                hintText: "局域网 IP (如 192.168.1.5)",
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _tokenController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.key),
                labelText: "鉴权 Token",
                hintText: "查看电脑后台输出的 vibe-xxxx",
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FF41),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => provider.connect(_ipController.text, 9999, token: _tokenController.text),
                child: const Text("建立安全连接", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel(dynamic panel) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        initiallyExpanded: true,
        iconColor: const Color(0xFF00FF41),
        collapsedIconColor: Colors.white38,
        title: Text(panel['title'] ?? "", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: (panel['items'] as List).map(_buildItem).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(dynamic item) {
    final id = item['id'];
    final type = item['type'];

    if (type == 'button') {
      bool isDanger = id.toString().contains('stop') || id.toString().contains('kill');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isDanger ? Colors.redAccent.withOpacity(0.1) : const Color(0xFF2A2A2A),
            foregroundColor: isDanger ? Colors.redAccent : const Color(0xFF00FF41),
            side: BorderSide(color: isDanger ? Colors.redAccent.withOpacity(0.3) : const Color(0xFF00FF41).withOpacity(0.2)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          onPressed: () {
            final params = <String, dynamic>{};
            _inputControllers.forEach((key, controller) {
              if (key.startsWith(id)) {
                params[key.split('.').last] = controller.text;
              }
            });
            context.read<AgentClientProvider>().sendAction(id, params);
          },
          child: Text(item['label'] ?? "", style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      );
    } else if (type == 'input' || type == 'textarea') {
      final controllerKey = "${id}.${item['id']?.toString().split('.').last ?? 'text'}";
      _inputControllers.putIfAbsent(controllerKey, () => TextEditingController());
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: TextField(
          controller: _inputControllers[controllerKey],
          maxLines: type == 'textarea' ? 4 : 1,
          style: const TextStyle(fontSize: 14, color: Colors.white),
          decoration: InputDecoration(
            labelText: item['label'],
            hintText: item['placeholder'],
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
            isDense: true,
            labelStyle: const TextStyle(color: Colors.white60),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
