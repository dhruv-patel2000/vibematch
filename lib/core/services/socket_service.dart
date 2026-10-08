import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../config/app_config.dart';

class SocketService {
  IO.Socket? socket;
  Function(Map<String, dynamic>)? onMatchFound;
  Function(Map<String, dynamic>)? onSignal;
  Function(Map<String, dynamic>)? onReceiveMessage;
  Function(Map<String, dynamic>)? onPartnerLiked;
  Function(Map<String, dynamic>)? onMatchError;
  Function()? onPeerLeft;

  String? _queuedUserId;
  String? _queuedTargetGender;
  String? _queuedCountry;

  void initSocket() {
    if (socket != null && socket!.connected) {
      return;
    }

    socket = IO.io(
      AppConfig.socketUrl,
      IO.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .enableAutoConnect()
          .enableReconnection()
          .build(),
    );

    socket!.onConnect((_) {
      print('Connected to Socket Server: ${socket!.id}');
      if (_queuedUserId != null && _queuedUserId!.isNotEmpty) {
        socket!.emit('register_user', _queuedUserId);
        _emitJoinQueue();
      }
    });

    socket!.onConnectError((err) => print('Socket Connect Error: $err'));
    socket!.onError((err) => print('Socket Error: $err'));

    socket!.on('match_found', (data) {
      if (onMatchFound != null) onMatchFound!(Map<String, dynamic>.from(data));
    });

    socket!.on('match_error', (data) {
      print('Socket match_error: $data');
      if (onMatchError != null) onMatchError!(data is Map ? Map<String, dynamic>.from(data) : {'message': data.toString()});
    });

    socket!.on('signal', (data) {
      if (onSignal != null) onSignal!(Map<String, dynamic>.from(data));
    });

    socket!.on('receive_message', (data) {
      if (onReceiveMessage != null) onReceiveMessage!(Map<String, dynamic>.from(data));
    });

    socket!.on('partner_liked', (data) {
      if (onPartnerLiked != null) onPartnerLiked!(Map<String, dynamic>.from(data));
    });

    socket!.on('partner_skipped', (_) {
      if (onPeerLeft != null) onPeerLeft!();
    });

    socket!.on('peer_left', (_) {
      if (onPeerLeft != null) onPeerLeft!();
    });
  }

  void registerUser(String userId) {
    _queuedUserId = userId;
    if (socket != null && socket!.connected && userId.isNotEmpty) {
      socket!.emit('register_user', userId);
    }
  }

  bool _queuedSuperMatch = false;

  void joinQueue(String userId, String myGender, String targetGender, [String country = 'all', bool superMatch = false]) {
    _queuedUserId = userId;
    final cleanGender = (targetGender == 'any' || targetGender == 'both' || targetGender.isEmpty) ? 'both' : targetGender;
    _queuedTargetGender = cleanGender;
    _queuedCountry = (country.isEmpty || country == 'All Countries') ? 'all' : country;
    _queuedSuperMatch = superMatch;

    if (socket != null && socket!.connected) {
      _emitJoinQueue();
    }
  }

  void _emitJoinQueue() {
    if (socket == null || !socket!.connected || _queuedUserId == null) return;
    socket!.emit('join_queue', {
      'userId': _queuedUserId,
      'gender': _queuedTargetGender ?? 'both',
      'country': _queuedCountry ?? 'All Countries',
      'superMatch': _queuedSuperMatch
    });
  }

  void skipMatch() {
    if (socket != null && socket!.connected) {
      socket!.emit('skip_match');
    }
  }

  void leaveQueue() {
    if (socket != null && socket!.connected) {
      socket!.emit('leave_queue');
    }
  }

  void sendSignal(String toSocketId, Map<String, dynamic> signal) {
    if (socket != null && socket!.connected) {
      socket!.emit('signal', {
        'to': toSocketId,
        'signal': signal,
      });
    }
  }

  void sendMessage(String toSocketId, String text, [String? giftImage]) {
    if (socket != null && socket!.connected) {
      socket!.emit('send_message', {
        'to': toSocketId,
        'text': text,
        'giftImage': giftImage,
      });
    }
  }

  void dispose() {
    socket?.disconnect();
    socket?.dispose();
    socket = null;
  }
}


