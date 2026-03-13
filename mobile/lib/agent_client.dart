import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

class AgentClientProvider extends ChangeNotifier {
  Socket? _socket;
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  List<dynamic> panels = [];
  Map<String, dynamic> state = {};
  List<String> logs = [];
  
  Map<String, dynamic>? lastResult;
  String aiState = "idle"; 

  final StreamController<Map<String, dynamic>> _confirmController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get confirmRequests => _confirmController.stream;

  // 统一消息通知流 (用于展示顶部 Toast)
  final StreamController<Map<String, dynamic>> _notificationController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get notifications => _notificationController.stream;

  int _seq = 0;
  Timer? _heartbeatTimer;

  Future<void> connect(String host, int port, {String? token}) async {
    try {
      _socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
      _isConnected = true;
      notifyListeners();
      _socket!.listen(_onData, onDone: _disconnect, onError: (e) => _disconnect());
      if (token != null && token.isNotEmpty) sendAction('auth', {'token': token});
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
        if (_isConnected) _sendPing();
      });
    } catch (e) {
      _notificationController.add({"type": "error", "msg": "连接失败: $e"});
    }
  }

  void _onData(Uint8List data) {
    var offset = 0;
    while (offset < data.length) {
      if (data.length - offset < 4) break;
      final len = ByteData.view(data.buffer, offset + data.offsetInBytes, 4).getUint32(0);
      offset += 4;
      if (data.length - offset < len) break;
      final payload = utf8.decode(data.sublist(offset, offset + len));
      offset += len;
      try { _handleEnvelope(jsonDecode(payload)); } catch (e) { print("JSON Error: $e"); }
    }
  }

  void _handleEnvelope(Map<String, dynamic> env) {
    final type = env['type'];
    final payload = env['payload'] ?? {};

    if (type == 'ui.render') {
      panels = payload['panels'] ?? [];
      state = payload['state'] ?? {};
      notifyListeners();
    } else if (type == 'terminal.output' || type == 'terminal.pty.output') {
      final text = payload['text'] ?? payload['raw'] ?? '';
      if (text.isNotEmpty) {
        logs.add(text);
        if (logs.length > 500) logs.removeAt(0);
        notifyListeners();
      }
    } else if (type == 'terminal.state') {
      aiState = payload['state'] ?? "idle";
      notifyListeners();
    } else if (type == 'ui.confirm') {
      aiState = "waiting_confirm";
      _confirmController.add(payload);
      notifyListeners();
    } else if (type == 'action.error') {
      _notificationController.add({"type": "error", "msg": "失败: ${payload['error']}"});
    } else if (type == 'action.result') {
      // 弹出成功提示
      _notificationController.add({"type": "success", "msg": "执行成功: ${payload['id']}"});
      
      // 仅存储具备可视化价值的数据
      if (payload['type'] == 'file_list' || payload['type'] == 'search_result' || payload['type'] == 'file_content' || payload['type'] == 'project_info') {
        lastResult = payload;
      }
      notifyListeners();
    }
  }

  void sendAction(String id, Map<String, dynamic> params) {
    if (!_isConnected) return;
    if (!id.contains('read')) lastResult = null;

    final msg = {'seq': ++_seq, 'type': 'ui.action', 'payload': {'id': id, 'params': params}};
    final body = utf8.encode(jsonEncode(msg));
    final header = Uint8List(4);
    ByteData.view(header.buffer).setUint32(0, body.length);
    _socket?.add(header);
    _socket?.add(body);
  }

  void clearResult() => { lastResult = null, notifyListeners() };

  void _sendPing() {
    if (!_isConnected) return;
    final msg = {'seq': ++_seq, 'type': 'ping', 'payload': {}};
    final body = utf8.encode(jsonEncode(msg));
    final header = Uint8List(4);
    ByteData.view(header.buffer).setUint32(0, body.length);
    _socket?.add(header);
    _socket?.add(body);
  }

  void _disconnect() {
    _isConnected = false;
    _socket = null;
    _heartbeatTimer?.cancel();
    notifyListeners();
  }
}
