import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/foundation.dart';

import '../core/config/app_config.dart';

class SocketService {
  late IO.Socket socket;
  final String serverUrl = AppConfig.socketUrl;

  void initSocket() {
    socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });
    
    socket.connect();
    
    socket.onConnect((_) {
      debugPrint('Connected to socket server');
    });
    
    socket.onDisconnect((_) {
      debugPrint('Disconnected from socket server');
    });
  }

  void joinQueue(Map<String, dynamic> preferences) {
    socket.emit('join_queue', preferences);
  }

  void onMatchFound(Function(Map<String, dynamic>) callback) {
    socket.on('match_found', (data) => callback(Map<String, dynamic>.from(data)));
  }

  // WebRTC related emits
  void sendOffer(Map<String, dynamic> data) => socket.emit('webrtc_offer', data);
  void sendAnswer(Map<String, dynamic> data) => socket.emit('webrtc_answer', data);
  void sendIceCandidate(Map<String, dynamic> data) => socket.emit('ice_candidate', data);

  // WebRTC related listeners
  void onOffer(Function(Map<String, dynamic>) callback) {
    socket.on('webrtc_offer', (data) => callback(Map<String, dynamic>.from(data)));
  }
  void onAnswer(Function(Map<String, dynamic>) callback) {
    socket.on('webrtc_answer', (data) => callback(Map<String, dynamic>.from(data)));
  }
  void onIceCandidate(Function(Map<String, dynamic>) callback) {
    socket.on('ice_candidate', (data) => callback(Map<String, dynamic>.from(data)));
  }
}
