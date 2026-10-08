import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/config/app_config.dart';
import '../../../core/services/translation_service.dart';
import '../../chat/presentation/direct_chat_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final Map<String, dynamic> user;

  const UserProfileScreen({super.key, required this.user});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  bool isFollowing = false;
  bool isLiked = false;
  int followersCount = 0;
  int followingCount = 0;
  int likesCount = 0;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final dio = Dio();
      final userId = widget.user['id'] ?? widget.user['_id'];
      final res = await dio.get(
        "${AppConfig.apiBaseUrl}/users/$userId/profile",
        options: Options(headers: {
          'x-api-key': AppConfig.apiAccessKey,
          'Authorization': 'Bearer $token'
        })
      );

      if (res.data != null && res.data['profile'] != null) {
        final profile = res.data['profile'];
        final prefs = await SharedPreferences.getInstance();
        final fetchedIsLiked = prefs.getBool('liked_user_${userId}') ?? false;
        
        setState(() {
          isFollowing = profile['isFollowing'] ?? false;
          isLiked = fetchedIsLiked;
          followersCount = profile['followersCount'] ?? 0;
          followingCount = profile['followingCount'] ?? 0;
          likesCount = profile['likesCount'] ?? 0;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch profile: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> _toggleFollow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final dio = Dio();
      final userId = widget.user['id'] ?? widget.user['_id'];
      
      setState(() {
        isFollowing = !isFollowing;
        followersCount += isFollowing ? 1 : -1;
      });

      final endpoint = isFollowing ? 'follow' : 'unfollow';
      await dio.post(
        "${AppConfig.apiBaseUrl}/users/$userId/$endpoint",
        options: Options(headers: {
          'x-api-key': AppConfig.apiAccessKey,
          'Authorization': 'Bearer $token'
        })
      );
    } catch (e) {
      // Revert on error
      setState(() {
        isFollowing = !isFollowing;
        followersCount += isFollowing ? 1 : -1;
      });
    }
  }

  Future<void> _toggleLike() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final dio = Dio();
      final userId = widget.user['id'] ?? widget.user['_id'];
      
      setState(() {
        isLiked = !isLiked;
        likesCount += isLiked ? 1 : -1;
      });
      await prefs.setBool('liked_user_$userId', isLiked);

      await dio.post(
        "\${AppConfig.apiBaseUrl}/users/$userId/like",
        options: Options(headers: {
          'x-api-key': AppConfig.apiAccessKey,
          'Authorization': 'Bearer $token'
        })
      );
    } catch (e) {
      debugPrint('Failed to toggle like');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = TranslationService().t;
    final u = widget.user;
    final String avatarUrl = (u['avatar'] != null && u['avatar'].toString().isNotEmpty) 
        ? (u['avatar'].toString().startsWith('http') 
            ? u['avatar'] 
            : AppConfig.apiBaseUrl.replaceAll('/api', '') + u['avatar']) 
        : '';

    return Scaffold(
      backgroundColor: const Color(0xFF0D0E12),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(u['name'] ?? 'Guest', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Cover and Avatar
            SizedBox(
              height: 250,
              child: Stack(
                children: [
                  Container(
                    height: 180,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF0F4C75), Color(0xFF0D0E12)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 20,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: const Color(0xFF1E293B),
                          backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                          child: avatarUrl.isEmpty ? const Icon(Icons.person, size: 50, color: Colors.white54) : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E676),
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFF0D0E12), width: 3),
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: 10,
                    right: 20,
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => DirectChatScreen(partner: u)),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: const BoxDecoration(
                              color: Colors.white10,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.chat_bubble_outline, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _toggleLike,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: const BoxDecoration(
                              color: Colors.white10,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(isLiked ? Icons.favorite : Icons.favorite_border, color: Colors.pinkAccent),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _toggleFollow,
                          icon: Icon(isFollowing ? Icons.check : Icons.person_add_alt_1),
                          label: Text(isFollowing ? t('Following') : t('Follow')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isFollowing ? Colors.white10 : const Color(0xFF00E676),
                            foregroundColor: isFollowing ? Colors.white : Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        )
                      ],
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            // Info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(u['name'] ?? 'Guest', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text('@${u['name']?.toString().toLowerCase() ?? 'user'}', style: const TextStyle(color: Colors.white54, fontSize: 16)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, color: Colors.white54, size: 18),
                      const SizedBox(width: 4),
                      Text(u['country'] ?? 'Global', style: const TextStyle(color: Colors.white54)),
                      const SizedBox(width: 16),
                      Text('${u['age'] ?? 21} ${t('years old')}', style: const TextStyle(color: Colors.white54)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 16),
                  isLoading 
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
                    : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStat(followingCount.toString(), t('Following')),
                        _buildStat(followersCount.toString(), t('Followers')),
                        _buildStat(likesCount.toString(), t('Likes')),
                      ],
                    ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 24),
                  
                  // Banner
                  GestureDetector(
                    onTap: () {
                      Navigator.popUntil(context, (route) => route.isFirst);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF00E676).withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.favorite_border, color: Color(0xFF00E676), size: 32),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t('Find your next match'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                Text(t('Return to video chat'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward, color: Colors.white54),
                        ],
                      ),
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String number, String label) {
    return Column(
      children: [
        Text(number, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 14)),
      ],
    );
  }
}
