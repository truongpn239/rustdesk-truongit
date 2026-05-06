import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../common.dart';
import '../common/hbbs/hbbs.dart';
import '../login.dart';
import '../models/user_model.dart';
import '../utils/multi_window_manager.dart';

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  io.Socket? _socket;
  String? _username;

  void connect(String username, BuildContext context) {
    debugPrint('[WebSocket] Connecting for user: $username');
    _username = username;
    if (_socket != null && _socket!.connected) {
      debugPrint('[WebSocket] Disconnecting old socket before reconnect');
      _socket!.disconnect();
    }
    _socket = io.io('wss://websocket.truongit.net', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });
    _socket!.on('connect', (_) {
      _socket!.emit('register', username);
    });
    _socket!.on('license_update', (data) async {
      if (!gFFI.userModel.isLogin) return;
      if (data is Map &&
          (data['hardware_id'] == null || data['action'] == 'logout')) {
        rustDeskWinManager.closeAllSubWindows().catchError((e) {
          debugPrint('[WebSocket] Error closing remote windows (ignored): $e');
        });
        await gFFI.userModel.logOut();
        requireLogin();
      }
    });
    _socket!.connect();
  }

  void disconnect() {
    debugPrint('[WebSocket] Disconnecting socket for user: $_username');
    _socket?.disconnect();
    _socket = null;
    _username = null;
  }
}
