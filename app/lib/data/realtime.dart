import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

enum RealtimeEvent { threadUpsert, threadDelete, spaceUpsert, spaceDelete, activity, reminderDue, connected, disconnected, unauthorized }

class RealtimeMessage {
  RealtimeMessage(this.event, [this.data = const {}]);
  final RealtimeEvent event;
  final Map<String, dynamic> data;
}

/// Socket.IO wrapper. The owner decides what to do with each message.
class RealtimeService {
  io.Socket? _socket;
  final StreamController<RealtimeMessage> _out = StreamController.broadcast();
  Stream<RealtimeMessage> get stream => _out.stream;

  void connect(String url, String token) {
    disconnect();
    final s = io.io(
      url,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setPath('/socket.io')
          .setAuth({'token': token})
          .enableReconnection()
          .setReconnectionDelay(1500)
          .setReconnectionDelayMax(15000)
          .disableAutoConnect()
          .build(),
    );
    void on(String name, RealtimeEvent e) {
      s.on(name, (d) {
        if (d is Map) _out.add(RealtimeMessage(e, Map<String, dynamic>.from(d)));
      });
    }

    on('thread:upsert', RealtimeEvent.threadUpsert);
    on('thread:delete', RealtimeEvent.threadDelete);
    on('space:upsert', RealtimeEvent.spaceUpsert);
    on('space:delete', RealtimeEvent.spaceDelete);
    on('activity:new', RealtimeEvent.activity);
    on('reminder:due', RealtimeEvent.reminderDue);
    s.onConnect((_) => _out.add(RealtimeMessage(RealtimeEvent.connected)));
    s.onDisconnect((_) => _out.add(RealtimeMessage(RealtimeEvent.disconnected)));
    s.onConnectError((e) {
      _out.add(RealtimeMessage(RealtimeEvent.disconnected));
      if ('$e'.contains('unauthorized')) _out.add(RealtimeMessage(RealtimeEvent.unauthorized));
    });
    _socket = s;
    s.connect();
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }
}
