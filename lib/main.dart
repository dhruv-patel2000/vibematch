import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'core/constants/app_strings.dart';
import 'core/services/api_service.dart';
import 'core/services/translation_service.dart';
import 'features/home/presentation/main_navigation_screen.dart';
import 'features/onboarding/presentation/onboarding_screen.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TranslationService().init();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }
  
  runApp(
    const ProviderScope(
      child: VibeMatchApp(),
    ),
  );
}

class VibeMatchApp extends StatelessWidget {
  const VibeMatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: TranslationService(),
      builder: (context, _) {
        return MaterialApp(
          title: AppStrings.appName,
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: const Color(0xFFE11D48), // Rose 600
            scaffoldBackgroundColor: const Color(0xFF0F172A), // Slate 950
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF0F172A),
              elevation: 0,
            ),
            useMaterial3: true,
          ),
          home: const SplashScreen(),
        );
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  bool _hasError = false;
  String _errorMessage = '';
  late AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _initializeApp();
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    setState(() { _hasError = false; });
    
    // Fetch settings to check API connection and keys
    final settingsResult = await ApiService.getSettings();
    
    if (settingsResult != null && settingsResult.containsKey('error') && settingsResult['error'] == 'check_internet_connection') {
      setState(() {
        _hasError = true;
        _errorMessage = 'Check internet connection or API Base URL';
      });
    } else {
      final settings = settingsResult?['settings'] as Map<String, dynamic>? ?? {};
      
      // Simulate some loading time for smooth transition
      await Future.delayed(const Duration(milliseconds: 1500));
      
      // Success, go to main screen
        if (mounted) {
          final prefs = await SharedPreferences.getInstance();
          final bool isFirstTime = prefs.getBool('v2FirstTime') ?? true;
          
          final String? token = prefs.getString('token');
          final String? userStr = prefs.getString('user');
          
          if (token != null && userStr != null && token.isNotEmpty) {
            try {
              final parsed = jsonDecode(userStr);
              final user = (parsed is Map && parsed['user'] != null) ? parsed['user'] : parsed;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => MainNavigationScreen(user: user))
              );
              return;
            } catch (e) {
              // fallthrough
            }
          }

          if (isFirstTime) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const OnboardingScreen())
            );
          } else {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => MainScreen(settings: settings))
            );
          }
        }
      }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0f),
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
              child: _hasError 
                ? Center(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(),
                      const Icon(Icons.wifi_off, size: 80, color: Colors.redAccent),
                      const SizedBox(height: 20),
                      const Text(
                        'Connection Error',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _errorMessage,
                        style: const TextStyle(fontSize: 14, color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 30),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _hasError = false;
                            _errorMessage = '';
                          });
                          _progressController.reset();
                          _initializeApp();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E676),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const Spacer(),
                    ],
                  ))
                : SizedBox(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                      const Spacer(),
                      // Logo
                      ClipOval(
                        child: Image.asset('assets/images/logo.png', width: 100, height: 100, fit: BoxFit.cover),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'VibeMatch',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -1,
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(height: 16),
                      Container(
                        width: 180,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: AnimatedBuilder(
                          animation: _progressController,
                          builder: (context, child) {
                            return FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: (_progressController.value * 2) > 1 ? 1 : (_progressController.value * 2),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00E676),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
            ),
          ),
        ],
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  final Map<String, dynamic>? settings;

  const MainScreen({super.key, this.settings});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  Map<String, dynamic>? _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    if (_settings == null || _settings!.isEmpty) {
      _loadCachedSettings();
    }
  }

  Future<void> _loadCachedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('app_settings');
    if (cached != null && cached.isNotEmpty) {
      try {
        final parsed = jsonDecode(cached);
        if (mounted) setState(() => _settings = parsed);
      } catch (e) {}
    }
    if (_settings == null || _settings!.isEmpty) {
      final res = await ApiService.getSettings();
      if (res != null && res['settings'] != null && mounted) {
        setState(() => _settings = res['settings']);
        await prefs.setString('app_settings', jsonEncode(res['settings']));
      }
    }
  }

  Map<String, dynamic>? get _effectiveSettings => _settings ?? widget.settings;

  bool get _guestEnabled => _effectiveSettings?['data']?['guestLogin'] ?? _effectiveSettings?['guestLogin'] ?? true;
  bool get _googleEnabled => _effectiveSettings?['data']?['googleLogin'] ?? _effectiveSettings?['googleLogin'] ?? true;
  bool get _facebookEnabled => _effectiveSettings?['data']?['facebookLogin'] ?? _effectiveSettings?['facebookLogin'] ?? false;
  bool get _appleEnabled => _effectiveSettings?['data']?['appleLogin'] ?? _effectiveSettings?['appleLogin'] ?? false;
  bool get _phoneEnabled => _effectiveSettings?['data']?['phoneLogin'] ?? _effectiveSettings?['phoneLogin'] ?? false;
  bool get _twitterEnabled => _effectiveSettings?['data']?['twitterLogin'] ?? _effectiveSettings?['twitterLogin'] ?? false;

  String _targetGender = 'any';
  bool _isLoading = false;

  Future<void> _handleSocialLogin(String provider) async {
    setState(() {
      _isLoading = true;
    });

    try {
      UserCredential? userCredential;
      String firebaseUid = '';
      String email = '';
      String name = '';
      String? avatar;
      String? persistentGuestId;
      bool isAnonymous = false;

      final prefs = await SharedPreferences.getInstance();

      if (provider == 'anonymous') {
        persistentGuestId = prefs.getString('persistent_guest_id') ?? '';
        if (persistentGuestId.isEmpty) {
          final rand = Random().nextInt(9999).toRadixString(36);
          final time = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
          persistentGuestId = 'guest_${time}_$rand';
          if (persistentGuestId.length > 20) {
            persistentGuestId = persistentGuestId.substring(0, 20);
          }
          await prefs.setString('persistent_guest_id', persistentGuestId);
        }

        try {
          userCredential = await FirebaseAuth.instance.signInAnonymously();
          firebaseUid = userCredential.user?.uid ?? persistentGuestId;
        } catch (e) {
          firebaseUid = persistentGuestId;
        }

        isAnonymous = true;
        name = 'Guest';
        email = '$persistentGuestId@guest.vibematch';
        avatar = 'https://api.dicebear.com/9.x/avataaars/png?seed=$persistentGuestId';
      } else if (provider == 'google') {
        final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) {
          setState(() => _isLoading = false);
          return;
        }
        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
        firebaseUid = userCredential.user!.uid;
        email = userCredential.user!.email ?? '';
        name = userCredential.user!.displayName ?? '';
        avatar = userCredential.user!.photoURL;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(TranslationService().t('Provider not fully configured yet.'))));
        setState(() => _isLoading = false);
        return;
      }

      // Send to our backend
      final res = await ApiService.socialLogin({
        'firebaseUid': firebaseUid,
        'persistentGuestId': persistentGuestId,
        'email': email,
        'name': name,
        'avatar': avatar,
        'provider': provider,
        'isAnonymous': isAnonymous,
      });

      setState(() => _isLoading = false);

      if (res != null && res['token'] != null) {
        await prefs.setString('token', res['token']);
        await prefs.setString('auth_token', res['token']);
        
        final Map<String, dynamic> user = res['user'] ?? res['userData'] ?? res['data'] ?? {'gender': 'other'};
        await prefs.setString('user', jsonEncode(user));
        
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => MainNavigationScreen(user: user)),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(TranslationService().t('Backend login failed'))));
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login error: $e')));
      }
    }
  }

  Future<void> _showPhoneLoginDialog() async {
    String phoneNumber = '';
    String selectedCountry = '+212';
    final t = TranslationService().t;
    
    final List<Map<String, String>> countries = [
      {'code': '+212', 'flag': '🇲🇦', 'name': 'Morocco'},
      {'code': '+1', 'flag': '🇺🇸', 'name': 'USA'},
      {'code': '+44', 'flag': '🇬🇧', 'name': 'UK'},
      {'code': '+33', 'flag': '🇫🇷', 'name': 'France'},
    ];

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: Text(t('Phone Login'), style: const TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButton<String>(
                    dropdownColor: const Color(0xFF334155),
                    value: selectedCountry,
                    isExpanded: true,
                    style: const TextStyle(color: Colors.white),
                    items: countries.map((c) => DropdownMenuItem(
                      value: c['code'],
                      child: Text('${c['flag']} ${c['name']} (${c['code']})'),
                    )).toList(),
                    onChanged: (val) => setState(() => selectedCountry = val!),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: t('Phone Number'),
                      hintStyle: const TextStyle(color: Colors.grey),
                      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE11D48))),
                    ),
                    onChanged: (val) => phoneNumber = val,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(t('Cancel'), style: const TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _verifyPhone(selectedCountry + phoneNumber);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE11D48)),
                  child: Text(t('Next')),
                ),
              ],
            );
          }
        );
      },
    );
  }

  Future<void> _verifyPhone(String fullNumber) async {
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: fullNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
          await _handlePhoneBackend(userCredential);
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Verification failed')));
        },
        codeSent: (String verificationId, int? resendToken) async {
          setState(() => _isLoading = false);
          _showOtpDialog(verificationId);
        },
        codeAutoRetrievalTimeout: (String verificationId) {},
      );
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showOtpDialog(String verificationId) {
    String smsCode = '';
    final t = TranslationService().t;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Text(t('Verify Phone Number'), style: const TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t('Enter the 6-digit code sent to your phone'), style: const TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 16),
              TextField(
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white, letterSpacing: 8, fontSize: 20),
                textAlign: TextAlign.center,
                maxLength: 6,
                decoration: const InputDecoration(
                  counterText: '',
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE11D48))),
                ),
                onChanged: (val) => smsCode = val,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('Cancel'), style: const TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (smsCode.length == 6) {
                  Navigator.pop(context);
                  setState(() => _isLoading = true);
                  try {
                    PhoneAuthCredential credential = PhoneAuthProvider.credential(
                      verificationId: verificationId,
                      smsCode: smsCode,
                    );
                    final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
                    await _handlePhoneBackend(userCredential);
                  } catch (e) {
                    setState(() => _isLoading = false);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invalid code: $e')));
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE11D48)),
              child: Text(t('Verify')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handlePhoneBackend(UserCredential userCredential) async {
    try {
      final res = await ApiService.socialLogin({
        'firebaseUid': userCredential.user!.uid,
        'email': userCredential.user!.phoneNumber,
        'name': '',
        'provider': 'phone',
        'isAnonymous': false,
      });

      setState(() => _isLoading = false);
      if (res != null && res['token'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', res['token']);
        await prefs.setString('auth_token', res['token']);
        
        final Map<String, dynamic> user = res['user'] ?? res['userData'] ?? res['data'] ?? {'gender': 'other'};
        await prefs.setString('user', jsonEncode(user));
        
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => MainNavigationScreen(user: user)),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(TranslationService().t('Backend login failed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: TranslationService(),
      builder: (context, _) {
        final t = TranslationService().t;

        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 30.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Logo Header
                  Column(
                    children: [
                      const SizedBox(height: 40),
                      Image.asset('assets/images/logo.png', width: 70, height: 70, errorBuilder: (context, error, stackTrace) => const Icon(Icons.bolt, size: 70, color: Color(0xFF00E676))),
                      const SizedBox(height: 16),
                      const Text(
                        AppStrings.loginTitle,
                        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t(AppStrings.loginSubtitle),
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),

                  // Buttons
                  Column(
                    children: [
                      if (_isLoading)
                        const CircularProgressIndicator(color: Color(0xFFE11D48))
                      else ...[
                        if (_guestEnabled) // Guest Button
                        ElevatedButton.icon(
                          onPressed: () => _handleSocialLogin('anonymous'),
                          icon: const Icon(Icons.person, size: 20),
                          label: Text(t('Sign In as Guest'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E293B), // slate-800
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 54),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: const BorderSide(color: Color(0xFF334155)), // slate-700
                            ),
                            elevation: 0,
                          ),
                        ),
                        if (_guestEnabled) const SizedBox(height: 12),
                        
                        if (_googleEnabled) // Google Button
                        ElevatedButton.icon(
                          onPressed: () => _handleSocialLogin('google'),
                          icon: const FaIcon(FontAwesomeIcons.google, size: 20, color: Color(0xFFDB4437)),
                          label: Text(t('Continue with Google'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            minimumSize: const Size(double.infinity, 54),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 1,
                          ),
                        ),
                        if (_googleEnabled) const SizedBox(height: 12),

                        if (_facebookEnabled) // Facebook Button
                        ElevatedButton.icon(
                          onPressed: () => _handleSocialLogin('facebook'),
                          icon: const FaIcon(FontAwesomeIcons.facebook, size: 20, color: Colors.white),
                          label: Text(t('Continue with Facebook'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1877F2),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 54),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 1,
                          ),
                        ),
                        if (_facebookEnabled) const SizedBox(height: 12),

                        if (_appleEnabled) // Apple Button
                        ElevatedButton.icon(
                          onPressed: () => _handleSocialLogin('apple'),
                          icon: const FaIcon(FontAwesomeIcons.apple, size: 22, color: Colors.white),
                          label: Text(t('Continue with Apple'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 54),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 1,
                          ),
                        ),
                        if (_appleEnabled) const SizedBox(height: 12),

                        if (_phoneEnabled) // Phone Button
                        ElevatedButton.icon(
                          onPressed: _showPhoneLoginDialog,
                          icon: const Icon(Icons.phone, size: 20, color: Colors.white),
                          label: Text(t('Continue with Phone'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF059669), // emerald-600
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 54),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 1,
                          ),
                        ),
                        if (_phoneEnabled) const SizedBox(height: 12),

                        if (_twitterEnabled) // Twitter Button
                        ElevatedButton.icon(
                          onPressed: () => _handleSocialLogin('twitter'),
                          icon: const FaIcon(FontAwesomeIcons.xTwitter, size: 20, color: Colors.white),
                          label: Text(t('Continue with Twitter (X)'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 54),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 1,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
