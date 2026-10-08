import 'widgets/gift_image.dart';
import '../../../core/widgets/user_avatar.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../../../core/config/app_config.dart';

class DirectChatScreen extends StatefulWidget {
  final Map<String, dynamic> partner;

  const DirectChatScreen({super.key, required this.partner});

  @override
  State<DirectChatScreen> createState() => _DirectChatScreenState();
}

class _DirectChatScreenState extends State<DirectChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<dynamic> _messages = [];
  bool _isLoading = true;
  String? _myUserId;
  String? _token;
  IO.Socket? _socket;

  @override
  void initState() {
    super.initState();
    _loadUserAndMessages();
  }

  Future<void> _loadUserAndMessages() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token') ?? prefs.getString('token');
    final userStr = prefs.getString('user');
    if (userStr != null) {
      try {
        final u = jsonDecode(userStr);
        _myUserId = u['id'] ?? u['_id'];
      } catch (_) {}
    }

    _initSocket();

    final partnerId = widget.partner['id'] ?? widget.partner['_id'] ?? widget.partner['partnerId'];
    if (partnerId != null && _token != null) {
      try {
        final dio = Dio();
        final res = await dio.get(
          '${AppConfig.apiBaseUrl}/messages/$partnerId',
          options: Options(headers: {'Authorization': 'Bearer $_token'}),
        );
        if (res.statusCode == 200 && mounted) {
          setState(() {
            _messages = res.data['messages'] ?? [];
            _isLoading = false;
          });
          _scrollToBottom();
        }
      } catch (e) {
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _initSocket() {
    if (_myUserId == null) return;
    _socket = IO.io(
      AppConfig.socketUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .build(),
    );
    _socket?.onConnect((_) {
      _socket?.emit('register_user', _myUserId);
    });
    _socket?.on('new_message_notification', (data) {
      final partnerId = widget.partner['id'] ?? widget.partner['_id'] ?? widget.partner['partnerId'];
      if (data != null && data['senderId'] == partnerId && mounted) {
        setState(() {
          _messages.add(data);
        });
        _scrollToBottom();
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _getGiftEmoji(String name) {
    final n = name.toLowerCase();
    if (n.contains('helicopter')) return '🚁';
    if (n.contains('airplane') || n.contains('plane')) return '✈️';
    if (n.contains('yacht') || n.contains('ship')) return '🚢';
    if (n.contains('handshake') || n.contains('deal')) return '🤝';
    if (n.contains('makeup') || n.contains('lipstick')) return '💄';
    if (n.contains('magic') || n.contains('wand')) return '🪄';
    if (n.contains('credit') || n.contains('card')) return '💳';
    if (n.contains('money') || n.contains('bag')) return '💰';
    if (n.contains('cake') || n.contains('birthday')) return '🎂';
    if (n.contains('champagne') || n.contains('bottle')) return '🍾';
    if (n.contains('beer') || n.contains('drink')) return '🍺';
    if (n.contains('martini') || n.contains('glass')) return '🍸';
    if (n.contains('lollipop') || n.contains('candy')) return '🍭';
    if (n.contains('balloon')) return '🎈';
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
        backgroundColor: Colors.transparent,
        builder: (context) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.5,
            decoration: const BoxDecoration(
              color: Color(0xFF161821),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Send a Gift 🎁', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (gifts.isEmpty)
                  const Expanded(
                    child: Center(child: Text('No gifts available currently', style: TextStyle(color: Colors.white54))),
                  )
                else
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
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
                              // Send gift message via chat
                              _sendMessage(text: 'Sent you $name! $emoji', isGift: true, giftImage: imgUrl, giftType: name, giftAmount: g['price']);
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not enough gems for this gift!')));
                            }
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF222531),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: Center(
                                    child: GiftImage(imageUrl: imgUrl, giftName: name, width: 50, height: 50, emojiSize: 36),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                              Row(
                                children: [
                                  const Icon(Icons.diamond, color: Colors.cyanAccent, size: 12),
                                  const SizedBox(width: 4),
                                  Text('${g['price']}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                ],
                              ),
                            ],
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
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to load gifts')));
    }
  }

  Future<void> _sendMessage({String? text, bool isGift = false, String? giftImage, String? giftType, int? giftAmount}) async {
    final msgText = text ?? _messageController.text.trim();
    if (msgText.isEmpty) return;

    final partnerId = widget.partner['id'] ?? widget.partner['_id'] ?? widget.partner['partnerId'];
    if (partnerId == null) return;

    if (!isGift) _messageController.clear();

    final tempMsg = {
      'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
      'senderId': _myUserId,
      'receiverId': partnerId,
      'text': msgText,
      'isGift': isGift,
      'giftImage': giftImage,
      'timestamp': DateTime.now().toIso8601String(),
    };

    setState(() {
      _messages.add(tempMsg);
    });
    _scrollToBottom();

    try {
      final dio = Dio();
      final res = await dio.post(
        '${AppConfig.apiBaseUrl}/messages',
        options: Options(headers: {'Authorization': 'Bearer $_token'}),
        data: {
          'senderId': _myUserId,
          'receiverId': partnerId,
          'text': msgText,
          'isGift': isGift,
          'giftType': giftType,
          'giftAmount': giftAmount,
          'giftImage': giftImage, // Add gift image to be saved or emitted if needed
        },
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        // Sent
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m['id'] == tempMsg['id']);
        });

        final errorMsg = e.response?.data['error'] ?? 'Failed to send message';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMsg.contains('mutually follow')
                  ? '⚠️ You must mutually follow each other to chat!'
                  : 'Error: $errorMsg',
            ),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m['id'] == tempMsg['id']);
        });
      }
    }
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.partner['name'] ?? 'User';
    final username = widget.partner['username'] ?? '';
    final avatar = widget.partner['avatar'];
    final avatarUrl = avatar != null && avatar.toString().isNotEmpty
        ? (avatar.toString().startsWith('http') ? avatar : '${AppConfig.apiBaseUrl.replaceAll('/api', '')}$avatar')
        : '';

    return Scaffold(
      backgroundColor: const Color(0xFF0D0E12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF15161C),
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            UserAvatar(avatarUrl: avatarUrl, radius: 18),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                if (username.isNotEmpty)
                  Text(username.startsWith('@') ? username : '@$username', style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Messages List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
                  : _messages.isEmpty
                      ? const Center(
                          child: Text(
                            'No messages yet. Send a message!',
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            final isMe = msg['senderId'] == _myUserId;
                            final text = msg['text'] ?? msg['content'] ?? '';
                            final isGift = msg['isGift'] == true;
                            final giftImage = msg['giftImage'];

                            return Align(
                              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                decoration: BoxDecoration(
                                  color: isMe ? const Color(0xFF00E676) : const Color(0xFF1E293B),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(16),
                                    topRight: const Radius.circular(16),
                                    bottomLeft: Radius.circular(isMe ? 16 : 0),
                                    bottomRight: Radius.circular(isMe ? 0 : 16),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (isGift && giftImage != null && giftImage.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 4),
                                        child: Image.network(
                                          giftImage, 
                                          width: 40, 
                                          height: 40, 
                                          errorBuilder: (_, __, ___) => const Text('🎁', style: TextStyle(fontSize: 24))
                                        ),
                                      ),
                                    Text(
                                      text,
                                      style: TextStyle(
                                        color: isMe ? Colors.black : Colors.white,
                                        fontSize: 15,
                                        fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),

            // Message Input Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF15161C),
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _showGiftSheet,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withOpacity(0.18),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF00E676).withOpacity(0.4)),
                      ),
                      child: const Icon(Icons.card_giftcard, color: Color(0xFF00E676), size: 22),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Write a message...',
                        hintStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Color(0xFF00E676),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send_rounded, color: Colors.black, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
