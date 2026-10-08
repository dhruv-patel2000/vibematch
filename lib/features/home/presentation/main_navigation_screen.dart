import 'package:flutter_svg/flutter_svg.dart';
import '../../../core/widgets/user_avatar.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../main.dart';
import '../../../core/config/app_config.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/translation_service.dart';
import '../../notifications/presentation/notifications_bottom_sheet.dart';
import '../../store/presentation/store_bottom_sheet.dart';
import '../../profile/presentation/edit_profile_screen.dart';
import '../../profile/presentation/settings_screen.dart';
import '../../profile/presentation/user_profile_screen.dart';
import '../../chat/presentation/chat_screen.dart';
import '../../chat/presentation/direct_chat_screen.dart';
import 'match_filter_bottom_sheet.dart';

class MainNavigationScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  const MainNavigationScreen({super.key, required this.user});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> with WidgetsBindingObserver {
  late Map<String, dynamic> _currentUser;
  
  bool get _isVip {
    return _currentUser['isVip'] == true || (_currentUser['vipExpiry'] != null && DateTime.tryParse(_currentUser['vipExpiry'].toString())?.isAfter(DateTime.now()) == true);
  }

  int _currentIndex = 0;
  DateTime? _lastPressedAt;
  String _targetGender = 'both';
  String _targetRegion = 'all';
  bool _superMatch = false;
  int _onlineUsers = 32984;
  
  List<dynamic> _history = [];
  bool _historyIsRecent = true;
  List<dynamic> _conversations = [];
  int _unreadMessagesCount = 0;
  IO.Socket? _socket;
  List<dynamic> _discoverUsers = [];

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  bool _isCameraReady = false;
  bool _isPermissionDenied = false;
  bool _isAudioMuted = false;
  bool _isVideoMuted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentUser = widget.user['user'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(widget.user['user'])
        : Map<String, dynamic>.from(widget.user);
    _fetchRealData();
    _initSocket();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initCamera();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _socket?.disconnect();
    _socket?.dispose();
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _localStream = null;
    _localRenderer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _currentIndex == 0) {
      _initCamera();
    }
  }

  Future<void> _initSocket() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? prefs.getString('token');
    
    _socket = IO.io(AppConfig.apiBaseUrl.replaceAll('/api', ''), <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'auth': {'token': token}
    });

    _socket?.connect();

    _socket?.on('connect', (_) {
      _socket?.emit('register', _currentUser['id']);
    });

    _socket?.on('new_message_notification', (data) {
      if (mounted) {
        setState(() {
          _unreadMessagesCount++;
        });
        _fetchRealData(); // refresh conversations to get updated last message
      }
    });
  }

  Future<void> _initCamera() async {
    try {
      var camStatus = await Permission.camera.status;
      if (!camStatus.isGranted) {
        camStatus = await Permission.camera.request();
      }
      var micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        micStatus = await Permission.microphone.request();
      }

      if (!camStatus.isGranted) {
        if (mounted) {
          setState(() {
            _isPermissionDenied = true;
            _isCameraReady = false;
          });
        }
        return;
      } else {
        if (mounted) {
          setState(() {
            _isPermissionDenied = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Camera permission error: $e");
    }

    try {
      if (_localRenderer.textureId == null) {
        await _localRenderer.initialize();
      }
    } catch (e) {
      debugPrint("Renderer initialize error: $e");
    }

    try {
      if (_localStream != null) {
        _localStream?.getTracks().forEach((track) => track.stop());
        await _localStream?.dispose();
        _localStream = null;
      }

      final Map<String, dynamic> mediaConstraints = {
        'audio': false,
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

      try {
        _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      } catch (_) {
        try {
          _localStream = await navigator.mediaDevices.getUserMedia({
            'audio': false,
            'video': {'facingMode': 'user'}
          });
        } catch (_) {
          _localStream = await navigator.mediaDevices.getUserMedia({'audio': false, 'video': true});
        }
      }

      _localRenderer.srcObject = _localStream;
      if (mounted) {
        setState(() {
          _isCameraReady = true;
          _isPermissionDenied = false;
        });
      }
    } catch (e) {
      debugPrint("Camera init error: $e");
      if (mounted) {
        setState(() => _isCameraReady = false);
      }
    }
  }

  Future<void> _fetchRealData() async {
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? prefs.getString('token');
      if (token != null) {
        dio.options.headers['Authorization'] = 'Bearer $token';
      }
      
      // Update User
      try {
        final userRes = await dio.get('/auth/me');
        if (userRes.statusCode == 200 && userRes.data['user'] != null && mounted) {
          setState(() {
            _currentUser = Map<String, dynamic>.from(userRes.data['user']);
          });
          await prefs.setString('user', jsonEncode(_currentUser));
        }
      } catch (e) {}

      // Discover Feed
      try {
        final discRes = await dio.get('/discover');
        if (discRes.statusCode == 200 && mounted) {
          final data = discRes.data;
          final list = List<dynamic>.from((data is Map && data['users'] is List) ? data['users'] : (data is List ? data : []));
          list.shuffle();
          setState(() {
            _discoverUsers = list;
          });
        }
      } catch (e) {}

      // History
      try {
        final histRes = await dio.get(_historyIsRecent ? '/matches/history' : '/matches/viewed-me');
        if (histRes.statusCode == 200 && mounted) {
          final data = histRes.data;
          final list = (data is Map && data['history'] is List) ? data['history'] : (data is List ? data : []);
          setState(() {
            _history = list;
          });
        }
      } catch (e) {}

      // Messages
      try {
        final msgRes = await dio.get('/messages/conversations');
        if (msgRes.statusCode == 200 && mounted) {
          final data = msgRes.data;
          final list = (data is Map && data['conversations'] is List) 
              ? data['conversations'] 
              : (data is List ? data : []);
          int unread = 0;
          for (var conv in list) {
            if (conv is Map && conv['unreadCount'] != null) {
              unread += (conv['unreadCount'] as num).toInt();
            }
          }
          setState(() {
            _conversations = list;
            _unreadMessagesCount = unread;
          });
        }
      } catch (e) {}

      // Stats
      try {
        final statsRes = await dio.get('/stats/online');
        if (statsRes.statusCode == 200 && mounted) {
          setState(() {
            _onlineUsers = statsRes.data['onlineUsers'] ?? _onlineUsers;
          });
        }
      } catch (e) {}

    } catch (e) {
      debugPrint("Data fetch error: $e");
    }
  }

  List<Widget> get _screens => [
    _buildVideoChatTab(),
    _buildDiscoverTab(),
    _buildHistoryTab(),
    _buildMessagesTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: TranslationService(),
      builder: (context, _) {
        return WillPopScope(
      onWillPop: () async {
        if (_currentIndex != 0) {
          setState(() {
            _currentIndex = 0;
          });
          return false;
        }
        final now = DateTime.now();
        if (_lastPressedAt == null || now.difference(_lastPressedAt!) > const Duration(seconds: 2)) {
          _lastPressedAt = now;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(TranslationService().t('Press back again to exit'), style: const TextStyle(color: Colors.white)),
              backgroundColor: Colors.black54,
              duration: const Duration(seconds: 2),
            ),
          );
          return false;
        }
        return true;
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFF0D0E12),
      body: Stack(
        children: [
          // Current Screen Content
          Positioned.fill(child: _screens[_currentIndex]),
          
          // Header Overlaid
          if (_currentIndex == 0 || _currentIndex == 1)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(),
            ),
        ],
      ),
      bottomNavigationBar: Theme(
        data: ThemeData(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF15161C),
            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05), width: 1)),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              if (index == 0 && _currentIndex != 0) {
                _initCamera();
              } else if (index != 0 && _currentIndex == 0) {
                _localStream?.getTracks().forEach((track) => track.stop());
                _localStream?.dispose();
                _localStream = null;
                _localRenderer.srcObject = null;
                _isCameraReady = false;
              }
              setState(() => _currentIndex = index);
            },
            backgroundColor: Colors.transparent,
            elevation: 0,
            selectedItemColor: const Color(0xFF00E676),
            unselectedItemColor: Colors.grey.shade600,
            selectedFontSize: 10,
            unselectedFontSize: 10,
            type: BottomNavigationBarType.fixed,
            items: [
              BottomNavigationBarItem(
                icon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.videocam_outlined, size: 24)),
                activeIcon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.videocam, size: 24)),
                label: TranslationService().t('Video Chat'),
              ),
              BottomNavigationBarItem(
                icon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.explore_outlined, size: 24)),
                activeIcon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.explore, size: 24)),
                label: TranslationService().t('Discover'),
              ),
              BottomNavigationBarItem(
                icon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.history, size: 24)),
                activeIcon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.history, size: 24)),
                label: TranslationService().t('History'),
              ),
              BottomNavigationBarItem(
                icon: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Badge(
                    label: Text('$_unreadMessagesCount'),
                    isLabelVisible: _unreadMessagesCount > 0,
                    backgroundColor: Colors.red,
                    child: const Icon(Icons.chat_bubble_outline, size: 24),
                  ),
                ),
                activeIcon: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Badge(
                    label: Text('$_unreadMessagesCount'),
                    isLabelVisible: _unreadMessagesCount > 0,
                    backgroundColor: Colors.red,
                    child: const Icon(Icons.chat_bubble, size: 24),
                  ),
                ),
                label: TranslationService().t('Messages'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
      },
    );
  }

  Widget _buildTopBar() {
    final topPadding = MediaQuery.of(context).padding.top;
    final bool isVip = _currentUser['isVip'] == true || (_currentUser['vipExpiry'] != null && DateTime.tryParse(_currentUser['vipExpiry'].toString())?.isAfter(DateTime.now()) == true);

    return Padding(
      padding: EdgeInsets.only(top: topPadding + 6, left: 16, right: 16, bottom: 8),
      child: Row(
        children: [
            // Logo
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset('assets/images/logo.png', width: 36, height: 36, fit: BoxFit.cover),
            ),
            const SizedBox(width: 8),
            // VIP Badge
            if (isVip) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFFA500)]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('VIP', style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
            ],
            // Diamonds next to logo
            GestureDetector(
              onTap: () async {
                await showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => StoreBottomSheet(user: _currentUser),
                  );
                  await _fetchRealData();
                  if (mounted) setState(() {});
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF0F4C75), Color(0xFF3282B8)]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.diamond, color: Colors.cyanAccent, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '${_currentUser['gems'] ?? 0}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            // Notifications
            IconButton(
              icon: const Icon(Icons.notifications_none, color: Colors.white70, size: 24),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const NotificationsBottomSheet(),
                );
              },
            ),
            const SizedBox(width: 8),
            // Profile Avatar
            GestureDetector(
              onTap: _showProfileDrawer,
              child: UserAvatar(
                avatarUrl: _currentUser['avatar']?.toString(),
                radius: 16,
                fallbackChild: Text(
                  (_currentUser['name'] ?? 'U').toString().substring(0, 1).toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      );
    }

  void _showProfileDrawer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Color(0xFF15161C),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            UserAvatar(
              avatarUrl: _currentUser['avatar']?.toString(),
              radius: 40,
            ),
            const SizedBox(height: 12),
            Text(_currentUser['name'] ?? 'User', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('@${_currentUser['username'] ?? 'user'}', style: const TextStyle(color: Color(0xFF00E676), fontSize: 16)),
            const SizedBox(height: 30),
            ListTile(
                leading: const Icon(Icons.person, color: Colors.white),
                title: Text(TranslationService().t('View Profile'), style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(user: _currentUser)));
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.white),
                title: Text(TranslationService().t('Edit Profile'), style: const TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  final updated = await Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfileScreen(user: _currentUser)));
                  if (updated != null && mounted) {
                    setState(() {
                      if (updated is Map<String, dynamic>) {
                        _currentUser = updated;
                      }
                    });
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings, color: Colors.white),
                title: Text(TranslationService().t('Settings'), style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.redAccent),
                title: Text(TranslationService().t('Logout'), style: const TextStyle(color: Colors.redAccent)),
                onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('token');
                await prefs.remove('auth_token');
                await prefs.remove('user');
                if (mounted) {
                  Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const VibeMatchApp()), (r) => false);
                }
              },
            )
          ],
        ),
      ),
    );
  }

  Widget _buildVideoChatTab() {
    return Stack(
      children: [
        if (_isCameraReady)
          Positioned.fill(
            child: RTCVideoView(
              _localRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              mirror: true,
            ),
          )
        else if (_isPermissionDenied)
          Positioned.fill(
            child: Container(
              color: const Color(0xFF0F1116),
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.videocam_off_outlined, color: Colors.white70, size: 48),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Camera Access Needed',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'To start random video chats, please allow camera & microphone access in your device settings.',
                      style: TextStyle(color: Colors.white60, fontSize: 14, height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () async {
                        await openAppSettings();
                      },
                      icon: const Icon(Icons.settings, size: 18),
                      label: const Text('Open Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E676),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Positioned.fill(
            child: Container(
              color: Colors.black,
              child: const Center(
                child: CircularProgressIndicator(color: Color(0xFF00E676), strokeWidth: 2),
              ),
            ),
          ),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                // Match count badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF00E676)),
                      ),
                      const SizedBox(width: 8),
                      Text('$_onlineUsers matches', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                ),
                const Spacer(),
                
                // Mic and Camera toggles
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildIconButton(_isAudioMuted ? Icons.mic_off : Icons.mic_none, onTap: () => setState(() => _isAudioMuted = !_isAudioMuted), active: !_isAudioMuted),
                    const SizedBox(width: 20),
                    _buildIconButton(_isVideoMuted ? Icons.videocam_off : Icons.camera_alt_outlined, onTap: () => setState(() => _isVideoMuted = !_isVideoMuted), active: !_isVideoMuted),
                  ],
                ),
                const SizedBox(height: 20),
                
                // Gender / Region filter
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () async {
                          final result = await showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => MatchFilterBottomSheet(
                              user: _currentUser,
                              initialGender: _targetGender,
                              initialRegion: _targetRegion,
                              initialSuperMatch: _superMatch,
                            ),
                          );
                          if (result != null && mounted) {
                              if (result['action'] == 'open_store') {
                                await showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (_) => StoreBottomSheet(user: _currentUser, initialTab: result['tab'] ?? 'gems'),
                                );
                                await _fetchRealData();
                                if (mounted) setState(() {});
                              } else {
                                setState(() {
                                  _targetGender = result['gender'];
                                  _targetRegion = result['region'];
                                  _superMatch = result['superMatch'];
                                });
                              }
                            }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                  _targetGender == 'both' ? Icons.people : (_targetGender == 'female' ? Icons.face_3 : Icons.face),
                                  color: _targetGender == 'both' ? Colors.purpleAccent : (_targetGender == 'female' ? Colors.orangeAccent : Colors.amber),
                                  size: 18),
                              const SizedBox(width: 8),
                              Text(
                                  _targetGender == 'both'
                                      ? 'Both'
                                      : (_targetGender == 'female'
                                          ? 'Girls'
                                          : 'Boys'),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                      Container(width: 1, height: 20, color: Colors.white24),
                      GestureDetector(
                        onTap: () async {
                          final result = await showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => MatchFilterBottomSheet(
                              user: _currentUser,
                              initialGender: _targetGender,
                              initialRegion: _targetRegion,
                              initialSuperMatch: _superMatch,
                            ),
                          );
                          if (result != null && mounted) {
                              if (result['action'] == 'open_store') {
                                await showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (_) => StoreBottomSheet(user: _currentUser, initialTab: result['tab'] ?? 'gems'),
                                );
                                await _fetchRealData();
                                if (mounted) setState(() {});
                              } else {
                                setState(() {
                                  _targetGender = result['gender'];
                                  _targetRegion = result['region'];
                                  _superMatch = result['superMatch'];
                                });
                              }
                            }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(20)),
                          child: Row(
                            children: [
                              const Icon(Icons.public,
                                  color: Colors.blueAccent, size: 18),
                              const SizedBox(width: 8),
                              Text(_targetRegion == 'all' ? 'Region' : _targetRegion,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                
                // Start Button
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: () async {
                    try {
                      final camStatus = await Permission.camera.request();
                      final micStatus = await Permission.microphone.request();
                      if (camStatus.isPermanentlyDenied || micStatus.isPermanentlyDenied) {
                        await openAppSettings();
                        return;
                      }
                      if (camStatus.isDenied || micStatus.isDenied) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Camera & Microphone permissions are required for video chat'),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                        }
                        return;
                      }
                    } catch (e) {
                      debugPrint("Error requesting permissions on button click: $e");
                    }

                    _localStream?.getTracks().forEach((track) => track.stop());
                    _localStream?.dispose();
                    _localStream = null;
                    _localRenderer.srcObject = null;
                    _isCameraReady = false;
                    if (!mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ChatScreen(
                        userId: _currentUser['id'] ?? _currentUser['_id'] ?? '',
                        myGender: _currentUser['gender'] ?? 'female', 
                        targetGender: _targetGender,
                        targetRegion: _targetRegion,
                        superMatch: _superMatch,
                      )),
                    ).then((_) => _initCamera());
                  },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E676),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      elevation: 10,
                      shadowColor: const Color(0xFF00E676).withOpacity(0.5),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.videocam, size: 24),
                        SizedBox(width: 12),
                        Text('Start Video Chat', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- DISCOVER TAB ---
  Widget _buildDiscoverTab() {
    if (_discoverUsers.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)));
    }
    return PageView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: _discoverUsers.length,
      itemBuilder: (context, index) {
        final u = _discoverUsers[index];
        final name = u['name'] ?? 'User';
        final age = u['age']?.toString() ?? '18';
        final country = u['country'] ?? 'World';
        final countryCode = u['countryCode'] ?? '';
        final avatar = u['avatar'];
        
        final avatarUrl = avatar != null && avatar.isNotEmpty
            ? (avatar.startsWith('http') ? avatar : '${AppConfig.apiBaseUrl.replaceAll('/api', '')}$avatar')
            : '';

        return Stack(
          fit: StackFit.expand,
          children: [
            // Background Image
            if (avatarUrl.isNotEmpty)
              (avatarUrl.toLowerCase().contains('.svg')
                  ? SvgPicture.network(avatarUrl, fit: BoxFit.cover, placeholderBuilder: (_) => Container(color: const Color(0xFF1E293B)))
                  : Image.network(avatarUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1E293B))))
            else
              Container(color: const Color(0xFF1E293B)),
            
            // Rich Gradient Overlay for Pro Design
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.black45, Colors.black87, Colors.black],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.4, 0.7, 0.9, 1.0],
                )
              ),
            ),
            
            // Content
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text('$name, $age', 
                          style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, height: 1.1),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(_countryCodeToEmoji(countryCode), style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 8),
                      Text(country, style: const TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      // View Profile Button
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(user: u)));
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white24,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            elevation: 0,
                          ),
                          child: const Text('View Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      
                      // Follow Button
                        Expanded(
                          child: StatefulBuilder(
                            builder: (context, setStateItem) {
                              List followingList = _currentUser['following'] ?? [];
                              bool isFollowing = followingList.contains(u['id']) || followingList.contains(u['_id']);
                              
                              return ElevatedButton.icon(
                                onPressed: () async {
                                  try {
                                    final dio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
                                    final prefs = await SharedPreferences.getInstance();
                                    final token = prefs.getString('auth_token') ?? prefs.getString('token');
                                    if (token != null) dio.options.headers['Authorization'] = 'Bearer $token';
                                    
                                    final endpoint = isFollowing ? 'unfollow' : 'follow';
                                    await dio.post('/users/${u['id']}/$endpoint');
                                    
                                    setStateItem(() {
                                      isFollowing = !isFollowing;
                                      if (isFollowing) {
                                        followingList.add(u['id']);
                                      } else {
                                        followingList.remove(u['id']);
                                        followingList.remove(u['_id']);
                                      }
                                      _currentUser['following'] = followingList;
                                    });
                                    
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                      content: Text(isFollowing ? TranslationService().t('You are now following $name!') : TranslationService().t('Unfollowed $name')), 
                                      backgroundColor: const Color(0xFF00E676)
                                    ));
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(TranslationService().t('Failed to update follow status'))));
                                  }
                                },
                                icon: Icon(isFollowing ? Icons.check : Icons.person_add, size: 20),
                                label: Text(isFollowing ? TranslationService().t('Following') : TranslationService().t('Follow'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isFollowing ? Colors.white10 : const Color(0xFF00E676),
                                  foregroundColor: isFollowing ? Colors.white : Colors.black,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                  elevation: isFollowing ? 0 : 8,
                                  shadowColor: isFollowing ? Colors.transparent : const Color(0xFF00E676).withOpacity(0.5),
                                ),
                              );
                            }
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // --- HISTORY TAB ---
  Widget _buildHistoryTab() {
    final topPadding = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.only(top: topPadding + 16, left: 20, right: 20, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('History', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(height: 20),
          Row(
            children: [
              _buildTabButton('Recent activity', _historyIsRecent),
              const SizedBox(width: 20),
              _buildTabButton('Viewed me', !_historyIsRecent),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _fetchRealData,
              color: const Color(0xFF00E676),
              backgroundColor: const Color(0xFF15161C),
              child: _history.isEmpty 
                ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [Center(child: Padding(padding: EdgeInsets.all(40.0), child: Text('No history yet.', style: TextStyle(color: Colors.white54))))])
                : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: _history.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final item = _history[index];
                      final partner = item['partner'] ?? {'id': item['partnerId'], 'name': 'User ${item['partnerId'] ?? ''}'};
                      return _buildHistoryCard(Map<String, dynamic>.from(partner), Map<String, dynamic>.from(item));
                    },
                  ),
            ),
          ),
        ],
      ),
    );
  }

  // --- MESSAGES TAB ---
  Widget _buildMessagesTab() {
    final List<dynamic> convList = (_conversations is List) ? (_conversations as List) : [];
    final topPadding = MediaQuery.of(context).padding.top;

    return Padding(
      padding: EdgeInsets.only(top: topPadding + 16, left: 20, right: 20, bottom: 20),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                          const Text('Messages', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white)),
            const SizedBox(height: 20),
            TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search chats...',
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                filled: true,
                fillColor: Colors.black45,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(color: Colors.white10),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(color: Colors.white10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchRealData,
                color: const Color(0xFF00E676),
                backgroundColor: const Color(0xFF15161C),
                child: convList.isEmpty
                  ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [Center(child: Padding(padding: EdgeInsets.all(40.0), child: Text('No messages yet', style: TextStyle(color: Colors.white54))))])
                  : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: convList.length,
                      itemBuilder: (context, index) {
                        final conv = convList[index];
                        final p = (conv is Map && conv['partner'] is Map) ? conv['partner'] : {};
                        final lastMsg = (conv is Map && conv['lastMessage'] is Map) ? conv['lastMessage'] : {};
                        
                        final avatarUrl = p['avatar'] != null && p['avatar'].toString().isNotEmpty
                            ? (p['avatar'].toString().startsWith('http') ? p['avatar'] : '${AppConfig.apiBaseUrl.replaceAll('/api', '')}${p['avatar']}')
                            : '';
                            
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: UserAvatar(avatarUrl: avatarUrl, radius: 28),
                          title: Text(p['name'] ?? 'User', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          subtitle: Text(lastMsg['content'] ?? 'Started a conversation', style: const TextStyle(color: Colors.white54), maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: const Text('now', style: TextStyle(color: Colors.white38, fontSize: 12)),
                          onTap: () {
                            final partner = (p.isNotEmpty) ? p : {'id': (conv is Map ? (conv['partnerId'] ?? '') : '')};
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => DirectChatScreen(partner: partner)),
                            );
                          },
                        );
                      },
                    ),
              ),
            ),
          ],
        ),
    );
  }

  Widget _buildIconButton(IconData icon, {required VoidCallback onTap, bool active = true}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: active ? Colors.white12 : Colors.redAccent.withOpacity(0.2),
          shape: BoxShape.circle,
          border: Border.all(color: active ? Colors.white24 : Colors.redAccent),
        ),
        child: Icon(icon, color: active ? Colors.white : Colors.redAccent, size: 28),
      ),
    );
  }

  Widget _buildTabButton(String text, bool isActive) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _historyIsRecent = text == 'Recent activity';
        });
        _fetchRealData();
      },
      child: Column(
        children: [
          Text(text, style: TextStyle(color: isActive ? Colors.white : Colors.white54, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          if (isActive)
            Container(width: 40, height: 3, decoration: BoxDecoration(color: const Color(0xFF00E676), borderRadius: BorderRadius.circular(2)))
          else
            const SizedBox(height: 3),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> partner, Map<String, dynamic> item) {
    final name = partner['name'] ?? 'Unknown';
    final age = partner['age'] ?? '';
    final date = item['createdAt'] != null ? DateTime.tryParse(item['createdAt'].toString())?.toLocal().toString().substring(0, 16) ?? '' : '';
    final title = age.toString().isNotEmpty ? '$name, $age' : name;
    
    final avatarUrl = partner['avatar'] != null && partner['avatar'].toString().isNotEmpty
        ? (partner['avatar'].toString().startsWith('http') ? partner['avatar'] : '${AppConfig.apiBaseUrl.replaceAll('/api', '')}${partner['avatar']}')
        : '';

    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(user: partner)));
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF15161C),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            UserAvatar(avatarUrl: avatarUrl, radius: 25),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(date, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF00E676)),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => DirectChatScreen(partner: partner)));
              },
            ),
          ],
        ),
      ),
    );
  }

  String _countryCodeToEmoji(String countryCode) {
    if (countryCode.isEmpty) return '🌍';
    return countryCode.toUpperCase().replaceAllMapped(
      RegExp(r'[A-Z]'),
      (match) => String.fromCharCode(match.group(0)!.codeUnitAt(0) + 127397)
    );
  }
}





