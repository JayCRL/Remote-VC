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

  final StreamController<Map<String, dynamic>> _confirmController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get confirmRequests => _confirmController.stream;

  int _seq = 0;
  Timer? _heartbeatTimer;

  Future<void> connect(String host, int port, {String? token}) async {
    try {
      _socket = await Socket.connect(host, port);
      _isConnected = true;
      notifyListeners();

      _socket!.listen(_onData, onDone: _disconnect, onError: (_) => _disconnect());

      if (token != null && token.isNotEmpty) {
        sendAction('auth', {'token': token});
      }

      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(Duration(seconds: 20), (timer) {
        if (_isConnected) {
          _sendPing();
        }
      });
    } catch (e) {
      print("Connect error: $e");
    }
  }

  void _onData(Uint8List data) {
    var offset = 0;
    while (offset < data.length) {
      if (data.length - offset < 4) break;
      final len = ByteData.view(data.buffer, offset, 4).getUint32(0);
      offset += 4;
      if (data.length - offset < len) break;
      final payload = utf8.decode(data.sublist(offset, offset + len));
      offset += len;
      _handleEnvelope(jsonDecode(payload));
    }
  }

  void _sendPing() {
    if (!_isConnected) return;
    final msg = {
      'seq': ++_seq,
      'type': 'ping',
      'payload': {}
    };
    final body = utf8.encode(jsonEncode(msg));
    final header = Uint8List(4);
    ByteData.view(header.buffer).setUint32(0, body.length);
    _socket?.add(header);
    _socket?.add(body);
  }

  void _handleEnvelope(Map<String, dynamic> env) {
    final type = env['type'];
    final payload = env['payload'] ?? {};

    if (type == 'ui.render') {
      panels = payload['panels'] ?? [];
      state = payload['state'] ?? {};
      notifyListeners();
    } else if (type == 'terminal.output') {
      logs.add(payload['text'] ?? '');
      if (logs.length > 300) logs.removeAt(0);
      notifyListeners();
    } else if (type == 'ui.confirm') {
      _confirmController.add(payload);
    } else if (type == 'action.error' && payload['error'] == 'unauthorized') {
      print("Auth required!");
    }
  }

  void sendAction(String id, Map<String, dynamic> params) {
    if (!_isConnected) return;
    final msg = {
      'seq': ++_seq,
      'type': 'ui.action',
      'payload': {'id': id, 'params': params}
    };
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
