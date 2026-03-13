import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';

// --- Protocol Layer ---

class AgentEnvelope {
  final int seq;
  final String type;
  final Map<String, dynamic> payload;

  AgentEnvelope({required this.seq, required this.type, required this.payload});

  factory AgentEnvelope.fromJson(Map<String, dynamic> json) {
    return AgentEnvelope(
      seq: json['seq'] ?? 0,
      type: json['type'] ?? '',
      payload: json['payload'] ?? {},
    );
  }

  Map<String, dynamic> toJson() => {
        'seq': seq,
        'type': type,
        'payload': payload,
      };
}

class AgentClient {
  Socket? _socket;
  int _seq = 0;
  final _controller = StreamController<AgentEnvelope>.broadcast();
  Stream<AgentEnvelope> get events => _controller.stream;

  Future<void> connect(String host, int port) async {
    _socket = await Socket.connect(host, port);
    _socket!.listen(_onData, onDone: _onDone, onError: _onError);
  }

  void _onData(Uint8List data) {
    // Protocol: 4 bytes big-endian length + JSON
    var offset = 0;
    while (offset < data.length) {
      if (data.length - offset < 4) break;
      final len = ByteData.view(data.buffer, offset, 4).getUint32(0);
      offset += 4;
      if (data.length - offset < len) break;
      final payload = utf8.decode(data.sublist(offset, offset + len));
      offset += len;
      _controller.add(AgentEnvelope.fromJson(jsonDecode(payload)));
    }
  }

  void sendAction(String id, Map<String, dynamic> params) {
    final env = AgentEnvelope(seq: ++_seq, type: 'ui.action', payload: {
      'id': id,
      'params': params,
    });
    final body = utf8.encode(jsonEncode(env.toJson()));
    final header = Uint8List(4);
    ByteData.view(header.buffer).setUint32(0, body.length);
    _socket?.add(header);
    _socket?.add(body);
  }

  void _onDone() => print("Connection closed");
  void _onError(e) => print("Socket error: $e");
}

// --- UI Layer ---

class VibeApp extends StatefulWidget {
  @override
  _VibeAppState createState() => _VibeAppState();
}

class _VibeAppState extends State<VibeApp> {
  final AgentClient client = AgentClient();
  Map<String, dynamic> uiState = {};
  List<dynamic> panels = [];
  List<String> terminalLines = [];
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _initConnection();
  }

  void _initConnection() async {
    // Replace with your computer's IP if running on a real phone
    await client.connect('127.0.0.1', 9999); 
    client.events.listen((env) {
      setState(() {
        if (env.type == 'ui.render') {
          panels = env.payload['panels'];
          uiState = env.payload['state'];
        } else if (env.type == 'terminal.output') {
          terminalLines.add(env.payload['text'] ?? '');
          if (terminalLines.length > 200) terminalLines.removeAt(0);
        } else if (env.type == 'ui.confirm') {
          _showConfirmDialog(env.payload);
        }
      });
    });
  }

  void _showConfirmDialog(Map<String, dynamic> payload) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Permission Required"),
        content: Text(payload['prompt'] ?? "Approve this action?"),
        actions: [
          TextButton(onPressed: () {
            client.sendAction("${payload['ai']}.confirm", {"approve": false});
            Navigator.pop(ctx);
          }, child: Text("Deny")),
          ElevatedButton(onPressed: () {
            client.sendAction("${payload['ai']}.confirm", {"approve": true});
            Navigator.pop(ctx);
          }, child: Text("Approve")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("RemoteVC Vibe Mode")),
      body: Column(
        children: [
          Expanded(
            flex: 1,
            child: Container(
              color: Colors.black,
              width: double.infinity,
              padding: EdgeInsets.all(8),
              child: SingleChildScrollView(
                reverse: true,
                child: Text(
                  terminalLines.join(""),
                  style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: ListView(
              padding: EdgeInsets.all(16),
              children: panels.map(_buildPanel).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanel(dynamic panel) {
    return Card(
      margin: EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(panel['title'], style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Divider(),
            ... (panel['items'] as List).map(_buildItem).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(dynamic item) {
    final id = item['id'];
    if (item['type'] == 'button') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: ElevatedButton(
          onPressed: () {
            final params = <String, dynamic>{};
            // Simplistic: if there's a corresponding input, use it as 'text' or 'q'
            if (_controllers.containsKey("${id}.input")) {
              params['text'] = _controllers["${id}.input"]!.text;
              params['q'] = _controllers["${id}.input"]!.text;
            }
            client.sendAction(id, params);
          },
          child: Text(item['label']),
        ),
      );
    } else if (item['type'] == 'input' || item['type'] == 'textarea') {
      _controllers.putIfAbsent("${id}.input", () => TextEditingController());
      return TextField(
        controller: _controllers["${id}.input"],
        decoration: InputDecoration(labelText: item['label'], hintText: item['placeholder']),
        maxLines: item['type'] == 'textarea' ? 3 : 1,
      );
    }
    return SizedBox.shrink();
  }
}

void main() => runApp(MaterialApp(home: VibeApp()));
