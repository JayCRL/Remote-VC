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
        backgroundColor: const Color(0xFF222222),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Color(0xFFFFB300)),
            SizedBox(width: 12),
            Text("AI 权限审批", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(payload['prompt'] ?? "AI 需要您的操作确认才能继续。", style: const TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () {
              context.read<AgentClientProvider>().sendAction("${payload['ai']}.confirm", {"approve": false});
              Navigator.pop(ctx);
            },
            child: Text("拒绝执行", style: TextStyle(color: Colors.red.shade300)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFB300),
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              context.read<AgentClientProvider>().sendAction("${payload['ai']}.confirm", {"approve": true});
              Navigator.pop(ctx);
            },
            child: const Text("确认批准", style: TextStyle(fontWeight: FontWeight.bold)),
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
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF2D2D2D), Color(0xFF121212)],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  const SizedBox(height: 80),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB300).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.coffee_rounded, size: 72, color: Color(0xFFFFB300)),
                  ),
                  const SizedBox(height: 32),
                  const Text("Vibe Control", style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                  const Text("您的私人 AI 编程指挥官", style: TextStyle(color: Colors.white54, fontSize: 16)),
                  const SizedBox(height: 64),
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
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("指挥台", style: TextStyle(fontWeight: FontWeight.w900)),
        centerTitle: true,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: IconButton(
              icon: const Icon(Icons.sync_rounded),
              onPressed: () => provider.sendAction("fs.list", {}),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 温暖色调的终端
          Container(
            height: 220,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF000000),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFFFB300).withOpacity(0.2)),
              boxShadow: [
                BoxShadow(color: const Color(0xFFFFB300).withOpacity(0.05), blurRadius: 20, spreadRadius: 5),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Column(
                children: [
                  Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    color: const Color(0xFF2D2D2D),
                    child: Row(
                      children: [
                        const Icon(Icons.circle, size: 8, color: Colors.redAccent),
                        const SizedBox(width: 6),
                        const Icon(Icons.circle, size: 8, color: Colors.orangeAccent),
                        const SizedBox(width: 6),
                        const Icon(Icons.circle, size: 8, color: Colors.greenAccent),
                        const SizedBox(width: 12),
                        const Text("CONSOLE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1, color: Colors.white38)),
                        const Spacer(),
                        Text(provider.isConnected ? "LIVE" : "OFFLINE", style: const TextStyle(fontSize: 10, color: Color(0xFFFFB300))),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: _logScroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: provider.logs.length,
                      itemBuilder: (ctx, i) => Text(
                        provider.logs[i],
                        style: const TextStyle(color: Color(0xFFFFCC80), fontSize: 12, fontFamily: 'monospace', height: 1.4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 功能卡片
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
        padding: const EdgeInsets.all(28.0),
        child: Column(
          children: [
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.wifi_tethering_rounded, color: Color(0xFFFFB300)),
                labelText: "服务器 IP",
                hintText: "127.0.0.1",
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _tokenController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.key_rounded, color: Color(0xFFFFB300)),
                labelText: "授权 Token",
                hintText: "vibe-666888",
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFB300),
                  foregroundColor: Colors.black,
                  elevation: 0,
                ),
                onPressed: () => provider.connect(_ipController.text, 9999, token: _tokenController.text),
                child: const Text("连接控制台", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel(dynamic panel) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: ExpansionTile(
          initiallyExpanded: true,
          shape: const RoundedRectangleBorder(side: BorderSide.none),
          iconColor: const Color(0xFFFFB300),
          title: Text(panel['title'] ?? "", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 0.5)),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: (panel['items'] as List).map(_buildItem).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(dynamic item) {
    final id = item['id'];
    final type = item['type'];

    if (type == 'button') {
      bool isDanger = id.toString().contains('stop') || id.toString().contains('kill');
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isDanger ? Colors.red.withOpacity(0.1) : const Color(0xFF333333),
            foregroundColor: isDanger ? Colors.red.shade300 : const Color(0xFFFFCC80),
            elevation: 0,
            side: BorderSide(color: isDanger ? Colors.red.withOpacity(0.3) : Colors.transparent),
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
        padding: const EdgeInsets.only(top: 16),
        child: TextField(
          controller: _inputControllers[controllerKey],
          maxLines: type == 'textarea' ? 4 : 1,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            labelText: item['label'],
            hintText: item['placeholder'],
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
            isDense: true,
            alignLabelWithHint: true,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
