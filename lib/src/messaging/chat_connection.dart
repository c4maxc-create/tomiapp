import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

abstract class ChatConnection {
  Stream<Map<String, dynamic>> get events;
  int? get closeCode;
  void typing(String id, bool active);
  Future<void> close();
}

abstract class ChatActivityConnection implements ChatConnection {
  void activity(String id, bool active, String activity);
}

class WebChatConnection implements ChatActivityConnection {
  WebChatConnection(this.channel);
  final WebSocketChannel channel;
  @override
  Stream<Map<String, dynamic>> get events => channel.stream.map(
    (v) => jsonDecode(v as String) as Map<String, dynamic>,
  );
  @override
  int? get closeCode => channel.closeCode;
  @override
  void typing(String id, bool active) => channel.sink.add(
    jsonEncode({'type': 'typing', 'conversationId': id, 'active': active}),
  );
  @override
  void activity(String id, bool active, String activity) => channel.sink.add(
    jsonEncode({
      'type': 'typing',
      'conversationId': id,
      'active': active,
      'activity': activity,
    }),
  );
  @override
  Future<void> close() async {
    try {
      await channel.sink.close().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }
}
