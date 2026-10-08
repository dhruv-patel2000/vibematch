import 'widgets/gift_image.dart';
import '../../../core/widgets/user_avatar.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:video_player/video_player.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/services/ad_service.dart';
import '../../../core/config/app_config.dart';
import 'direct_chat_screen.dart';

class ChatScreen extends StatefulWidget {
  final String userId;
  final String myGender;
  final String targetGender;
  final String targetRegion;
  final bool superMatch;

  const ChatScreen({
    super.key,
    required this.userId,
    required this.myGender,
    required this.targetGender,
    this.targetRegion = 'all',
    this.superMatch = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final SocketService _socketService = SocketService();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  VideoPlayerController? _demoVideoController;

  MediaStream? _localStream;
  RTCPeerConnection? _peerConnection;
  String? _partnerSocketId;
  Map<String, dynamic>? _partnerInfo;
  bool _isVideoMuted = false;
  bool _isAudioMuted = false;
  bool _isLiked = false;
  bool _isFollowing = false;
  int _likesCount = 0;
  List<Map<String, String>> _messages = [];
  final TextEditingController _messageController = TextEditingController();
  bool _showInVideoChatInput = false;

  bool get _isMatched => _partnerInfo != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initAll();
    });
  }

  Future<void> _initAll() async {
    await _initRenderers();
    await _initWebRTCAndSocket();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  String _countryCodeToEmoji(String countryCode) {
    if (countryCode.length != 2) return '🌐';
    try {
      final int firstLetter = countryCode.toUpperCase().codeUnitAt(0) - 0x41 + 0x1F1E6;
      final int secondLetter = countryCode.toUpperCase().codeUnitAt(1) - 0x41 + 0x1F1E6;
      return String.fromCharCode(firstLetter) + String.fromCharCode(secondLetter);
    } catch (_) {
      return '🌐';
    }
  }

  Future<void> _initWebRTCAndSocket() async {
    try {
      try {
        var camStatus = await Permission.camera.status;
        if (!camStatus.isGranted) {
          await Permission.camera.request();
        }
        var micStatus = await Permission.microphone.status;
        if (!micStatus.isGranted) {
          await Permission.microphone.request();
        }
      } catch (e) {
        debugPrint("Permission request in chat error: $e");
      }
      // 1. Get User Media with fallback
      try {
        final Map<String, dynamic> mediaConstraints = {
          'audio': true,
          'video': {
            'mandatory': {
              'minWidth': '640',
              'minHeight': '480',
              'minFrameRate': '30',
            },
            'facingMode': 'user',
            'optional': [],
          }
        };
        _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      } catch (e) {
        try {
          _localStream = await navigator.mediaDevices.getUserMedia({
            'audio': true,
            'video': {'facingMode': 'user'}
          });
        } catch (_) {
          _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': true});
        }
      }
      _localRenderer.srcObject = _localStream;
      if (mounted) setState(() {});

      String effectiveUserId = widget.userId;
      if (effectiveUserId.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final userStr = prefs.getString('user');
        if (userStr != null) {
          try {
            final u = jsonDecode(userStr);
            effectiveUserId = u['id'] ?? u['_id'] ?? '';
          } catch (_) {}
        }
      }

      // 2. Init Socket Connection
      _socketService.initSocket();
      _socketService.registerUser(effectiveUserId);
      _socketService.joinQueue(effectiveUserId, widget.myGender, widget.targetGender, widget.targetRegion, widget.superMatch);

      // 3. Socket Callbacks
      _socketService.onMatchFound = (data) async {
        _partnerSocketId = data['socketId'];
        _partnerInfo = data['partner'];
        _isLiked = false;
        _isFollowing = false;
        _likesCount = _partnerInfo?['likesCount'] ?? 0;
        _messages = [];

        if (mounted) setState(() {});

        // Demo User handling
        if (_partnerInfo?['isDemo'] == true) {
          String rawUrl = _partnerInfo?['videoUrl'] ?? '';
          if (rawUrl.isEmpty || rawUrl.contains('.m3u8') || rawUrl.contains('converter')) {
            rawUrl = _partnerInfo?['gender'] == 'male' ? '/videos/demo-male.mp4' : '/videos/demo-female.mp4';
          }
          final String finalUrl = rawUrl.startsWith('http')
              ? rawUrl
              : '${AppConfig.apiBaseUrl.replaceAll('/api', '')}$rawUrl';

          _demoVideoController?.dispose();
          _demoVideoController = VideoPlayerController.networkUrl(Uri.parse(finalUrl));
          try {
            await _demoVideoController!.initialize();
            _demoVideoController!.setLooping(true);
            _demoVideoController!.play();
          } catch (e) {
            debugPrint("Demo video initialize error: $e. Trying fallback...");
            try {
              final fallbackUrl = _partnerInfo?['gender'] == 'male'
                  ? '${AppConfig.apiBaseUrl.replaceAll('/api', '')}/videos/demo-male.mp4'
                  : '${AppConfig.apiBaseUrl.replaceAll('/api', '')}/videos/demo-female.mp4';
              if (finalUrl != fallbackUrl) {
                _demoVideoController?.dispose();
                _demoVideoController = VideoPlayerController.networkUrl(Uri.parse(fallbackUrl));
                await _demoVideoController!.initialize();
                _demoVideoController!.setLooping(true);
                _demoVideoController!.play();
              }
            } catch (fallbackErr) {
              debugPrint("Fallback demo video error: $fallbackErr");
            }
          }
          if (mounted) setState(() {});
          return;
        }

        // Real User WebRTC handling
        if (_partnerSocketId != null) {
          await _createPeerConnection(_partnerSocketId!);
          if (data['initiator'] == true) {
            RTCSessionDescription offer = await _peerConnection!.createOffer();
            await _peerConnection!.setLocalDescription(offer);
            _socketService.sendSignal(_partnerSocketId!, {'type': 'offer', 'sdp': offer.toMap()});
          }
        }
      };

      _socketService.onSignal = (data) async {
        if (_peerConnection == null) return;
        final signal = data['signal'];
        if (signal == null) return;

        final type = signal['type'];
        if (type == 'offer') {
          final sdpMap = Map<String, dynamic>.from(signal['sdp']);
          await _peerConnection!.setRemoteDescription(RTCSessionDescription(sdpMap['sdp'], sdpMap['type']));
          RTCSessionDescription answer = await _peerConnection!.createAnswer();
          await _peerConnection!.setLocalDescription(answer);
          _socketService.sendSignal(data['from'], {'type': 'answer', 'sdp': answer.toMap()});
        } else if (type == 'answer') {
          final sdpMap = Map<String, dynamic>.from(signal['sdp']);
          await _peerConnection!.setRemoteDescription(RTCSessionDescription(sdpMap['sdp'], sdpMap['type']));
        } else if (type == 'candidate') {
          final candMap = Map<String, dynamic>.from(signal['candidate']);
          await _peerConnection!.addCandidate(RTCIceCandidate(
            candMap['candidate'],
            candMap['sdpMid'],
            candMap['sdpMLineIndex'],
          ));
        }
      };

      _socketService.onReceiveMessage = (data) {
        if (mounted) {
          setState(() {
            _messages.add({
              'sender': 'partner',
              'text': data['text'] ?? '',
              'giftImage': data['giftImage'] ?? '',
            });
          });
        }
      };

      _socketService.onPartnerLiked = (data) {
        if (mounted && data['newLikesCount'] != null) {
          setState(() {
            _likesCount = data['newLikesCount'];
          });
        }
      };

      _socketService.onMatchError = (data) {
        debugPrint('Match error received: $data');
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted && _partnerInfo == null) {
            _socketService.joinQueue(effectiveUserId, widget.myGender, widget.targetGender, widget.targetRegion, widget.superMatch);
          }
        });
      };

      _socketService.onPeerLeft = () {
        _cleanupPeerConnection();
        _demoVideoController?.dispose();
        _demoVideoController = null;
        if (mounted) {
          setState(() {
            _partnerInfo = null;
          });
        }
        _socketService.joinQueue(widget.userId, widget.myGender, widget.targetGender, widget.targetRegion, widget.superMatch);
      };
    } catch (e) {
      debugPrint('WebRTC / Socket Init Error: $e');
    }
  }

  Future<void> _createPeerConnection(String toSocketId) async {
    List<dynamic> iceServers = [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ];

    try {
      final dio = Dio();
      final res = await dio.get('${AppConfig.apiBaseUrl}/webrtc/ice-servers');
      if (res.statusCode == 200 && res.data['iceServers'] != null) {
        final dynamic servers = res.data['iceServers'];
        if (servers is List && servers.isNotEmpty) {
          iceServers = servers;
        }
      }
    } catch (_) {}

    final Map<String, dynamic> configuration = {
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    };

    _peerConnection = await createPeerConnection(configuration);

    _localStream?.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    _peerConnection!.onIceCandidate = (candidate) {
      _socketService.sendSignal(toSocketId, {
        'type': 'candidate',
        'candidate': candidate.toMap(),
      });
    };

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty && mounted) {
        setState(() {
          _remoteRenderer.srcObject = event.streams[0];
        });
      }
    };
  }

  void _cleanupPeerConnection() {
    _peerConnection?.close();
    _peerConnection = null;
    _remoteRenderer.srcObject = null;
  }

  void _toggleVideo() {
    if (_localStream != null) {
      final videoTrack = _localStream!.getVideoTracks().firstOrNull;
      if (videoTrack != null) {
        videoTrack.enabled = !videoTrack.enabled;
        setState(() {
          _isVideoMuted = !videoTrack.enabled;
        });
      }
    }
  }

  void _toggleAudio() {
    if (_localStream != null) {
      final audioTrack = _localStream!.getAudioTracks().firstOrNull;
      if (audioTrack != null) {
        audioTrack.enabled = !audioTrack.enabled;
        setState(() {
          _isAudioMuted = !audioTrack.enabled;
        });
      }
    }
  }

  int _skipCount = 0;
  void _skip() {
    _skipCount++;
    if (_skipCount % 3 == 0) {
      AdService.showInterstitialAd();
    }
    _demoVideoController?.pause();
    _demoVideoController?.dispose();
    _demoVideoController = null;
    _cleanupPeerConnection();
    _socketService.skipMatch();
    setState(() {
      _partnerInfo = null;
      _messages.clear();
      _showInVideoChatInput = false;
    });
    _socketService.joinQueue(widget.userId, widget.myGender, widget.targetGender, widget.targetRegion, widget.superMatch);
  }

  Future<void> _toggleLike() async {
    if (_partnerInfo == null) return;
    setState(() {
      _isLiked = !_isLiked;
      _likesCount = _isLiked ? _likesCount + 1 : (_likesCount > 0 ? _likesCount - 1 : 0);
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? prefs.getString('token');
      final dio = Dio();
      await dio.post(
        '${AppConfig.apiBaseUrl}/users/${_partnerInfo!['id']}/like',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
        data: {'action': _isLiked ? 'like' : 'unlike'},
      );
    } catch (_) {}
  }

  Future<void> _toggleFollow() async {
    if (_partnerInfo == null) return;
    setState(() {
      _isFollowing = !_isFollowing;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? prefs.getString('token');
      final dio = Dio();
      final action = _isFollowing ? 'follow' : 'unfollow';
      await dio.post(
        '${AppConfig.apiBaseUrl}/users/${_partnerInfo!['id']}/$action',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isFollowing ? 'Followed ${_partnerInfo!['name']}!' : 'Unfollowed ${_partnerInfo!['name']}'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (_) {}
  }

  void _showReportDialog() {
    if (_partnerInfo == null) return;
    final List<String> reasons = [
      'Inappropriate video / nudity',
      'Harassment or hate speech',
      'Spam or fake profile',
      'Underage user',
      'Other reason'
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Report User', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: reasons
              .map((r) => ListTile(
                    title: Text(r, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    onTap: () async {
                      Navigator.pop(context);
                      try {
                        final prefs = await SharedPreferences.getInstance();
                        final token = prefs.getString('auth_token') ?? prefs.getString('token');
                        final dio = Dio();
                        await dio.post(
                          '${AppConfig.apiBaseUrl}/reports',
                          options: Options(headers: {'Authorization': 'Bearer $token'}),
                          data: {
                            'reportedUserId': _partnerInfo!['id'],
                            'reportedUserName': _partnerInfo!['name'],
                            'reportedUserAvatar': _partnerInfo!['avatar'],
                            'reason': r,
                            'details': 'Reported from mobile video chat'
                          },
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Report submitted. Thank you for keeping VibeMatch safe!')),
                          );
                        }
                      } catch (_) {}
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  String _getGiftEmoji(String name) {
    final n = name.toLowerCase();
    if (n.contains('helicopter')) return '🚁';
    if (n.contains('airplane') || n.contains('plane')) return '✈️';
    if (n.contains('cruise') || n.contains('ship')) return '🚢';
    if (n.contains('handshake')) return '🤝';
    if (n.contains('lipstick')) return '💄';
    if (n.contains('wand')) return '🪄';
    if (n.contains('credit') || n.contains('card')) return '💳';
    if (n.contains('money') || n.contains('bag')) return '💰';
    if (n.contains('cake')) return '🎂';
    if (n.contains('champagne')) return '🍾';
    if (n.contains('beer')) return '🍺';
    if (n.contains('cocktail')) return '🍸';
    if (n.contains('lollipop')) return '🍭';
    if (n.contains('party') || n.contains('hopper')) return '🎈';
    return '🎁';
  }

  void _showGiftSheet() async {
    try {
      final dio = Dio();
      final res = await dio.get('${AppConfig.apiBaseUrl}/gifts');
      final List gifts = res.data['gifts'] ?? [];

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF0F172A),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (context) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.55,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Send a Gift 🎁', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (gifts.isEmpty)
                  const Expanded(
                    child: Center(child: Text('No gifts available currently', style: TextStyle(color: Colors.white54))),
                  )
                else
                  Expanded(
                    child: GridView.builder(
                      physics: const BouncingScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.75,
                      ),
                      itemCount: gifts.length,
                      itemBuilder: (context, index) {
                        final g = gifts[index];
                        final name = g['name'] ?? '';
                        final emoji = _getGiftEmoji(name);
                        String? imgPath = g['imagePath']?.toString();
                        if (imgPath != null && !imgPath.startsWith('/')) imgPath = '/$imgPath';
                        final imgUrl = imgPath == null || imgPath.isEmpty
                            ? ''
                            : (imgPath.startsWith('http')
                                ? imgPath
                                : '${AppConfig.apiBaseUrl.replaceAll('/api', '')}$imgPath');

                        return GestureDetector(
                          onTap: () async {
                            Navigator.pop(context);
                            try {
                              final prefs = await SharedPreferences.getInstance();
                              final token = prefs.getString('auth_token') ?? prefs.getString('token');
                              final dio = Dio();
                              await dio.post(
                                '${AppConfig.apiBaseUrl}/gifts/send',
                                options: Options(headers: {'Authorization': 'Bearer $token'}),
                                data: {'cost': g['price']},
                              );

                              if (_partnerSocketId != null) {
                                _socketService.sendMessage(_partnerSocketId!, 'Sent you $name! $emoji', imgUrl);
                              }

                              if (mounted) {
                                setState(() {
                                  _messages.add({
                                    'sender': 'me',
                                    'text': 'You sent $name! $emoji',
                                    'giftImage': imgUrl,
                                  });
                                });
                              }
                            } catch (_) {}
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white10),
                            ),
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                GiftImage(imageUrl: imgUrl, giftName: name, width: 36, height: 36, emojiSize: 28),
                                const SizedBox(height: 4),
                                Text(name, style: const TextStyle(color: Colors.white, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.diamond, color: Colors.cyanAccent, size: 10),
                                    const SizedBox(width: 2),
                                    Text('${g['price']}', style: const TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ],
                                )
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      );
    } catch (_) {}
  }

  void _toggleInVideoChatInput() {
    setState(() {
      _showInVideoChatInput = !_showInVideoChatInput;
    });
  }

  void _sendLiveMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    if (_partnerSocketId != null) {
      _socketService.sendMessage(_partnerSocketId!, text);
    }
    setState(() {
      _messages.add({'sender': 'me', 'text': text});
      _messageController.clear();
      _showInVideoChatInput = false;
    });
  }

  void _showChatSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                top: 16,
                left: 16,
                right: 16,
              ),
              child: SizedBox(
                height: 350,
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text('Live Chat', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isMe = msg['sender'] == 'me';
                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isMe ? const Color(0xFF00E676) : const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (msg['giftImage'] != null && msg['giftImage']!.isNotEmpty)
                                    Padding(padding: const EdgeInsets.only(bottom: 4), child: GiftImage(imageUrl: msg['giftImage'], giftName: msg['text'] ?? '', width: 40, height: 40)),
                                  Text(
                                    msg['text'] ?? '',
                                    style: TextStyle(color: isMe ? Colors.black : Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Type a message...',
                              hintStyle: const TextStyle(color: Colors.white38),
                              filled: true,
                              fillColor: const Color(0xFF1E293B),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.send, color: Color(0xFF00E676)),
                          onPressed: () {
                            final text = _messageController.text.trim();
                            if (text.isEmpty) return;
                            _messageController.clear();
                            if (_partnerSocketId != null) {
                              _socketService.sendMessage(_partnerSocketId!, text);
                            }
                            setState(() {
                              _messages.add({'sender': 'me', 'text': text});
                            });
                            setSheetState(() {});
                          },
                        )
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showPartnerProfile() {
    if (_partnerInfo == null) return;
    
    final String partnerName = _partnerInfo?['name'] ?? 'Partner';
    final String partnerUsername = _partnerInfo?['username'] ?? 'user_${DateTime.now().millisecondsSinceEpoch}';
    final String partnerCountry = _partnerInfo?['country'] ?? 'World';
    final String partnerCountryCode = _partnerInfo?['countryCode'] ?? '';
    final String? partnerAvatar = _partnerInfo?['avatar'];
    final int likesCount = _partnerInfo?['likesCount'] ?? 0;
    
    final String avatarUrl = partnerAvatar != null && partnerAvatar.isNotEmpty
        ? (partnerAvatar.startsWith('http') ? partnerAvatar : '${AppConfig.apiBaseUrl.replaceAll('/api', '')}$partnerAvatar')
        : '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.65,
        decoration: const BoxDecoration(
          color: Color(0xFF1E1F28),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Stack(
          children: [
            // Green Header Background
            Container(
              height: 120,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF0F4C75), Color(0xFF135A4F)]),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
            ),
            
            // Close Button
            Positioned(
              top: 16,
              right: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.3), shape: BoxShape.circle),
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),

            // Profile Info
            Column(
              children: [
                const SizedBox(height: 50),
                // Avatar
                Center(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF1E1F28), width: 4),
                    ),
                    child: UserAvatar(avatarUrl: avatarUrl, radius: 60),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Name
                Text(
                  partnerName,
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                
                // Username
                Text(
                  '@$partnerUsername',
                  style: const TextStyle(color: Color(0xFF00E676), fontSize: 16, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                
                // Country
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('BY ', style: TextStyle(color: Colors.white54, fontSize: 14)), // just a static prefix as in design
                    Text(_countryCodeToEmoji(partnerCountryCode), style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Text(
                      partnerCountry,
                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 40),
                  child: Divider(color: Colors.white10),
                ),
                const SizedBox(height: 16),
                
                // Stats
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Column(
                      children: [
                        const Icon(Icons.favorite, color: Color(0xFFFF2A6D), size: 24),
                        const SizedBox(height: 4),
                        Text('$likesCount', style: const TextStyle(color: Color(0xFFFF2A6D), fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        const Text('LIKES', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
                      ],
                    ),
                    Column(
                      children: [
                        const Icon(Icons.people_outline, color: Colors.blueAccent, size: 24),
                        const SizedBox(height: 4),
                        const Text('1', style: TextStyle(color: Colors.blueAccent, fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        const Text('FOLLOWERS', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
                      ],
                    ),
                    Column(
                      children: [
                        const Icon(Icons.person_add_outlined, color: Colors.purpleAccent, size: 24),
                        const SizedBox(height: 4),
                        const Text('0', style: TextStyle(color: Colors.purpleAccent, fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        const Text('FOLLOWING', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
                      ],
                    ),
                  ],
                ),
                
                const SizedBox(height: 30),
                
                // Buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _toggleFollow();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00E676),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 8,
                            shadowColor: const Color(0xFF00E676).withOpacity(0.4),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(_isFollowing ? Icons.check : Icons.person_add_alt_1, size: 20),
                              const SizedBox(width: 8),
                              Text(_isFollowing ? 'Following' : 'Follow', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            if (_partnerInfo != null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => DirectChatScreen(partner: _partnerInfo!)),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF334155),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text('Message', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _demoVideoController?.dispose();
    _cleanupPeerConnection();
    _localStream?.getTracks().forEach((track) => track.stop());
      _localStream?.dispose();
      _localStream = null;
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _socketService.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String partnerName = _partnerInfo?['name'] ?? 'Partner';
    final String partnerAge = _partnerInfo?['age']?.toString() ?? '22';
    final String partnerCountry = _partnerInfo?['country'] ?? 'World';
    final String partnerCountryCode = _partnerInfo?['countryCode'] ?? '';
    final String? partnerAvatar = _partnerInfo?['avatar'];

    final String avatarUrl = partnerAvatar != null && partnerAvatar.isNotEmpty
        ? (partnerAvatar.startsWith('http') ? partnerAvatar : '${AppConfig.apiBaseUrl.replaceAll('/api', '')}$partnerAvatar')
        : '';

    return Scaffold(
      backgroundColor: const Color(0xFF0D0E12),
      body: Stack(
        children: [
          // 1. Remote Video / Demo Video / Searching View
          Positioned.fill(
            child: _partnerInfo != null
                ? (_demoVideoController != null && _demoVideoController!.value.isInitialized
                    ? GestureDetector(
                        onHorizontalDragEnd: (details) {
                          if (details.primaryVelocity != null && details.primaryVelocity!.abs() > 300) _skip();
                        },
                        child: SizedBox.expand(
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: _demoVideoController!.value.size.width,
                              height: _demoVideoController!.value.size.height,
                              child: VideoPlayer(_demoVideoController!),
                            ),
                          ),
                        ),
                      )
                    : _remoteRenderer.srcObject != null
                        ? GestureDetector(
                            onHorizontalDragEnd: (details) {
                              if (details.primaryVelocity != null && details.primaryVelocity!.abs() > 300) _skip();
                            },
                            child: RTCVideoView(
                              _remoteRenderer,
                              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                            ),
                          )
                        : GestureDetector(
                            onHorizontalDragEnd: (details) {
                              if (details.primaryVelocity != null && details.primaryVelocity!.abs() > 300) _skip();
                            },
                            child: Container(
                              color: const Color(0xFF0D0E12),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    UserAvatar(avatarUrl: avatarUrl, radius: 65),
                                    const SizedBox(height: 20),
                                    Text(
                                      '$partnerName, $partnerAge',
                                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(_countryCodeToEmoji(partnerCountryCode), style: const TextStyle(fontSize: 16)),
                                        const SizedBox(width: 6),
                                        Text(
                                          partnerCountry,
                                          style: const TextStyle(color: Colors.white70, fontSize: 16),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 24),
                                    const CircularProgressIndicator(color: Color(0xFF00E676)),
                                  ],
                                ),
                              ),
                            ),
                          ))
                : Container(
                    color: const Color(0xFF0D0E12),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            height: 250,
                            child: MatchingPulseWidget(),
                          ),
                          const SizedBox(height: 30),
                          ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                            ).createShader(bounds),
                            child: const Text(
                              'Finding your next match...',
                              style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.public, color: Colors.white70, size: 16),
                                const SizedBox(width: 8),
                                const Text(
                                  'Connecting globally',
                                  style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 60),
                          InkWell(
                            onTap: () => Navigator.pop(context),
                            borderRadius: BorderRadius.circular(30),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(30),
                                gradient: LinearGradient(
                                  colors: [Colors.redAccent.withOpacity(0.15), Colors.red.withOpacity(0.05)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                border: Border.all(color: Colors.redAccent.withOpacity(0.5), width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.redAccent.withOpacity(0.1),
                                    blurRadius: 15,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Text(
                                'Cancel Search',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
          ),

            // --- OVERLAYS FOR MATCHED STATE (EXACTLY AS IN SCREENSHOT) ---
          if (_isMatched && _partnerInfo != null) ...[
            // Top Left Partner Info Pill
            Positioned(
              top: 55,
              left: 16,
              child: GestureDetector(
                onTap: _showPartnerProfile,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white12, width: 1),
                  ),
                  child: Row(
                    children: [
                      UserAvatar(avatarUrl: avatarUrl, radius: 18),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Text(
                                '$partnerName, $partnerAge',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              const SizedBox(width: 5),
                              const Icon(Icons.check_circle, color: Color(0xFF00E676), size: 16),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(_countryCodeToEmoji(partnerCountryCode), style: const TextStyle(fontSize: 13)),
                              const SizedBox(width: 6),
                              Text(
                                partnerCountry,
                                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ],
                          )
                        ],
                      )
                    ],
                  ),
                ),
              ),
            ),

            // Right Vertical Control Buttons (Add friend, Heart/Like, Shield/Report, Close)
            Positioned(
              top: 55,
              right: 16,
              child: Column(
                children: [
                  _buildCircleBtn(
                    _isFollowing ? Icons.person_remove : Icons.person_add_alt_1,
                    active: _isFollowing,
                    activeColor: const Color(0xFF00E676),
                    onTap: _toggleFollow,
                  ),
                  const SizedBox(height: 14),
                  _buildCircleBtn(
                    _isLiked ? Icons.favorite : Icons.favorite_border,
                    active: _isLiked,
                    activeColor: const Color(0xFFFF2A6D),
                    onTap: _toggleLike,
                  ),
                  const SizedBox(height: 14),
                  _buildCircleBtn(
                    Icons.shield_outlined,
                    onTap: _showReportDialog,
                  ),
                  const SizedBox(height: 14),
                  _buildCircleBtn(
                    Icons.close,
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Live Message floating toast
            if (_messages.isNotEmpty)
              Positioned(
                bottom: 120,
                left: 20,
                child: Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.55),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_messages.last['giftImage'] != null && _messages.last['giftImage']!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Image.network(
                            _messages.last['giftImage']!,
                            width: 24,
                            height: 24,
                            errorBuilder: (_, __, ___) => const Text('🎁', style: TextStyle(fontSize: 18)),
                          ),
                        ),
                      Flexible(
                        child: Text(
                          _messages.last['text'] ?? '',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Bottom-Right Local Camera PIP
            Positioned(
              bottom: 110,
              right: 16,
              width: 120,
              height: 160,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white24, width: 2),
                  color: Colors.black,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: RTCVideoView(
                    _localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),
            ),

            // Floating Live Chat Input Row (Only when chat button tapped)
            if (_showInVideoChatInput)
              Positioned(
                bottom: 95,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF15161C).withOpacity(0.95),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: const Color(0xFF00E676).withOpacity(0.6), width: 1.5),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 12),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          autofocus: true,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: const InputDecoration(
                            hintText: 'Type a message...',
                            hintStyle: TextStyle(color: Colors.white54, fontSize: 14),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _sendLiveMessage(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send_rounded, color: Color(0xFF00E676)),
                        onPressed: _sendLiveMessage,
                      ),
                    ],
                  ),
                ),
              ),

            // Bottom Action Bar: Chat, Mic, Cam, Gift, Skip >
            Positioned(
              bottom: 35,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  _buildBottomBtn(
                    Icons.chat_bubble_outline,
                    onTap: _toggleInVideoChatInput,
                    active: _showInVideoChatInput,
                    color: _showInVideoChatInput ? const Color(0xFF00E676) : Colors.white,
                  ),
                  const SizedBox(width: 10),
                  _buildBottomBtn(
                    _isAudioMuted ? Icons.mic_off : Icons.mic_none,
                    onTap: _toggleAudio,
                    active: !_isAudioMuted,
                  ),
                  const SizedBox(width: 10),
                  _buildBottomBtn(
                    _isVideoMuted ? Icons.videocam_off : Icons.videocam_outlined,
                    onTap: _toggleVideo,
                    active: !_isVideoMuted,
                  ),
                  const SizedBox(width: 10),
                  _buildBottomBtn(
                    Icons.card_giftcard,
                    color: const Color(0xFF00E676),
                    bgColor: const Color(0xFF00E676).withOpacity(0.18),
                    borderColor: const Color(0xFF00E676).withOpacity(0.4),
                    onTap: _showGiftSheet,
                  ),

                  const Spacer(),

                  // Skip > Pill Button
                  GestureDetector(
                    onTap: _skip,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 15),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B).withOpacity(0.9),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white24, width: 1),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8),
                        ],
                      ),
                      child: const Row(
                        children: [
                          Text('Skip', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_ios, color: Colors.white, size: 14),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCircleBtn(IconData icon, {VoidCallback? onTap, bool active = false, Color activeColor = Colors.white}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: active ? activeColor.withOpacity(0.25) : Colors.black.withOpacity(0.6),
          shape: BoxShape.circle,
          border: Border.all(color: active ? activeColor : Colors.white12, width: 1),
        ),
        child: Icon(icon, color: active ? activeColor : Colors.white, size: 20),
      ),
    );
  }

  Widget _buildBottomBtn(
    IconData icon, {
    VoidCallback? onTap,
    bool active = true,
    Color color = Colors.white,
    Color? bgColor,
    Color? borderColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: bgColor ?? (active ? Colors.black.withOpacity(0.6) : Colors.red.withOpacity(0.2)),
          shape: BoxShape.circle,
          border: Border.all(color: borderColor ?? (active ? Colors.white24 : Colors.red), width: 1),
        ),
        child: Icon(icon, color: active ? color : Colors.red, size: 22),
      ),
    );
  }
}

class MatchingPulseWidget extends StatefulWidget {
  const MatchingPulseWidget({super.key});

  @override
  State<MatchingPulseWidget> createState() => _MatchingPulseWidgetState();
}

class _MatchingPulseWidgetState extends State<MatchingPulseWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Ripples
            ...List.generate(3, (index) {
              final delay = index * 0.33;
              var value = _controller.value - delay;
              if (value < 0) value += 1.0;
              return Transform.scale(
                scale: 1.0 + (value * 2.5),
                child: Opacity(
                  opacity: (1.0 - value).clamp(0.0, 1.0),
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF00E676), width: 1.5),
                      color: const Color(0xFF00E676).withOpacity(0.15),
                    ),
                  ),
                ),
              );
            }),
            // Center Profile
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00E676).withOpacity(0.4),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: ClipOval(
                  child: const Center(child: Text('🌍', style: TextStyle(fontSize: 60))),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}


