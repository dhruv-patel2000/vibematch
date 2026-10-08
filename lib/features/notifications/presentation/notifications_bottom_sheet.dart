import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../profile/presentation/user_profile_screen.dart';

class NotificationsBottomSheet extends StatefulWidget {
  const NotificationsBottomSheet({super.key});

  @override
  State<NotificationsBottomSheet> createState() => _NotificationsBottomSheetState();
}

class _NotificationsBottomSheetState extends State<NotificationsBottomSheet> {
  List<dynamic> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Future<void> _fetchNotifications() async {
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? prefs.getString('token');
      if (token == null || token.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final res = await dio.get('/notifications', options: Options(headers: {'Authorization': 'Bearer $token'}));
      if (mounted) {
        setState(() {
          _notifications = res.data['notifications'] ?? [];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAsRead(String notifId) async {
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? prefs.getString('token');
      if (token != null) {
        await dio.post('/notifications/$notifId/read', options: Options(headers: {'Authorization': 'Bearer $token'}));
      }
    } catch (_) {}
  }

  String _formatTime(dynamic ts) {
    if (ts == null) return 'now';
    final dt = DateTime.tryParse(ts.toString())?.toLocal();
    if (dt == null) return 'now';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: const BoxDecoration(
        color: Color(0xFF161821),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            width: double.infinity,
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Notifications', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),
          ),
          Expanded(
            child: _loading 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
              : _notifications.isEmpty 
                  ? const Center(child: Text('No notifications yet', style: TextStyle(color: Colors.white54, fontSize: 15)))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _notifications.length,
                      separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                      itemBuilder: (context, index) {
                        final notif = _notifications[index];
                        final avatar = notif['fromUserAvatar'] ?? notif['senderAvatar'];
                        final name = notif['fromUserName'] ?? notif['title'] ?? 'Someone';
                        final type = notif['type'] ?? 'notification';
                        final isUnread = notif['isRead'] == false;
                        final timeStr = _formatTime(notif['timestamp']);

                        String subtitleText = notif['body'] ?? '';
                        if (subtitleText.isEmpty) {
                          if (type == 'follow') {
                            subtitleText = 'started following you';
                          } else if (type == 'gift') {
                            subtitleText = 'sent you a gift 🎁';
                          } else {
                            subtitleText = 'sent you a notification';
                          }
                        }

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          tileColor: isUnread ? const Color(0xFF00E676).withOpacity(0.06) : Colors.transparent,
                          leading: UserAvatar(avatarUrl: avatar, radius: 24),
                          title: RichText(
                            text: TextSpan(
                              style: const TextStyle(fontSize: 14, color: Colors.white),
                              children: [
                                TextSpan(text: '$name ', style: const TextStyle(fontWeight: FontWeight.bold)),
                                TextSpan(text: subtitleText, style: const TextStyle(color: Colors.white70)),
                              ],
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(timeStr, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                              if (isUnread) ...[
                                const SizedBox(width: 8),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF00E676),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          onTap: () {
                            if (isUnread && notif['id'] != null) {
                              _markAsRead(notif['id'].toString());
                              setState(() {
                                notif['isRead'] = true;
                              });
                            }

                            final partnerId = notif['fromUserId']?.toString();
                            if (partnerId != null && partnerId.isNotEmpty) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => UserProfileScreen(
                                    user: {
                                      'id': partnerId,
                                      'name': name,
                                      'avatar': avatar,
                                      'username': notif['fromUserUsername'] ?? '',
                                    },
                                  ),
                                ),
                              );
                            }
                          },
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
