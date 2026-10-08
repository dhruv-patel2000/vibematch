import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/translation_service.dart';
import 'package:dio/dio.dart';
import '../../../core/config/app_config.dart';
import '../../../main.dart'; // We'll go to login after this.

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  List<dynamic> _languages = [];
  String? _selectedLanguage;
  bool _isLoadingLangs = true;

  final List<Map<String, String>> _pages = [
    {
      'title': 'Welcome to VibeMatch',
      'desc': 'Make new friends and connect with people worldwide.',
      'image': 'assets/images/logo.png', // We'll just show an icon if logo missing
      'icon': 'video_chat',
    },
    {
      'title': 'Start Video Chat',
      'desc': 'Swipe to find your next vibe and start video chatting instantly.',
      'icon': 'swipe',
    },
  ];

  @override
  void initState() {
    super.initState();
    _fetchLanguages();
  }

  Future<void> _fetchLanguages() async {
    try {
      final dio = Dio();
      final res = await dio.get('${AppConfig.apiBaseUrl}/languages');
      if (res.data != null && res.data['languages'] != null) {
        setState(() {
          _languages = res.data['languages'];
          _isLoadingLangs = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching languages: $e');
      setState(() {
        _isLoadingLangs = false;
      });
    }
  }

  void _nextPage() {
    if (_currentPage < _pages.length) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finishOnboarding();
    }
  }

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('v2FirstTime', false);
    if (_selectedLanguage != null) {
      await TranslationService().setLanguage(_selectedLanguage!);
      await prefs.setString('language', _selectedLanguage!);
    }
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (idx) {
                  setState(() {
                    _currentPage = idx;
                  });
                },
                itemCount: _pages.length + 1, // +1 for language selection
                itemBuilder: (context, index) {
                  if (index < _pages.length) {
                    return _buildInfoPage(_pages[index]);
                  } else {
                    return _buildLanguagePage();
                  }
                },
              ),
            ),
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoPage(Map<String, String> data) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF151520),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00E676).withOpacity(0.3),
                  blurRadius: 40,
                  spreadRadius: 10,
                )
              ]
            ),
            child: Icon(
              data['icon'] == 'video_chat' ? Icons.videocam : Icons.swipe,
              size: 60,
              color: const Color(0xFF00E676),
            ),
          ),
          const SizedBox(height: 60),
          Text(
            data['title']!,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Text(
            data['desc']!,
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withOpacity(0.6),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildLanguagePage() {
    return Padding(
      padding: const EdgeInsets.all(30.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Select Language',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 40),
          if (_isLoadingLangs)
            const CircularProgressIndicator(color: Color(0xFF00E676))
          else if (_languages.isEmpty)
            const Text('No languages available', style: TextStyle(color: Colors.white54))
          else
            Expanded(
              child: ListView.builder(
                itemCount: _languages.length,
                itemBuilder: (context, index) {
                  final lang = _languages[index];
                  final isSelected = _selectedLanguage == lang['code'];
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedLanguage = lang['code'];
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 15),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF00E676).withOpacity(0.1) : const Color(0xFF151520),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF00E676) : Colors.white.withOpacity(0.1),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            lang['name'],
                            style: TextStyle(
                              fontSize: 18,
                              color: isSelected ? const Color(0xFF00E676) : Colors.white,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          if (isSelected)
                            const Icon(Icons.check_circle, color: Color(0xFF00E676)),
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
  }

  Widget _buildBottomControls() {
    return Padding(
      padding: const EdgeInsets.all(30.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Dots indicator
          Row(
            children: List.generate(
              _pages.length + 1,
              (index) => Container(
                margin: const EdgeInsets.only(right: 8),
                height: 8,
                width: _currentPage == index ? 24 : 8,
                decoration: BoxDecoration(
                  color: _currentPage == index ? const Color(0xFF00E676) : Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          
          ElevatedButton(
            onPressed: _nextPage,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            child: Text(
              _currentPage == _pages.length ? 'Get Started' : 'Next',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }
}
