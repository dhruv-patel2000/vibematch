import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/config/app_config.dart';
import '../../../core/services/translation_service.dart';
import 'delete_account_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool notificationsEnabled = true;
  Map<String, dynamic>? settings;
  List<dynamic> _languages = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
    });

    try {
      final dio = Dio();
      final res = await dio.get(
        AppConfig.apiBaseUrl.replaceAll('/api', '') + '/api/init',
        options: Options(headers: {'x-api-key': AppConfig.apiAccessKey}),
      );
      if (res.data != null && res.data['settings'] != null) {
        setState(() {
          settings = res.data['settings'];
        });
      }
      
      final langRes = await dio.get(AppConfig.apiBaseUrl.replaceAll('/api', '') + '/api/languages');
      if (langRes.data != null && langRes.data['languages'] != null) {
        setState(() {
          _languages = langRes.data['languages'];
        });
      }
    } catch (e) {
      debugPrint('Failed to load settings: $e');
    }
  }

  Future<void> _toggleNotifications(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notificationsEnabled', val);
    setState(() {
      notificationsEnabled = val;
    });
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showLanguageDialog() {
    final langs = _languages.isNotEmpty ? _languages : TranslationService().supportedLanguages;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF181A20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(TranslationService().t('Select Language'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: langs.length,
              separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
              itemBuilder: (context, index) {
                final lang = langs[index];
                final String code = lang['code']?.toString() ?? '';
                final bool isSelected = code == TranslationService().currentLanguage;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  leading: isSelected 
                    ? const Icon(Icons.check_circle, color: Color(0xFF00E676))
                    : const Icon(Icons.radio_button_unchecked, color: Colors.grey),
                  title: Text(
                    lang['nativeName'] ?? lang['name'] ?? code,
                    style: TextStyle(
                      color: isSelected ? const Color(0xFF00E676) : Colors.white,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(code.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await TranslationService().setLanguage(code);
                    setState(() {}); 
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: TranslationService(),
      builder: (context, _) {
        final t = TranslationService().t;

        return Scaffold(
          backgroundColor: const Color(0xFF0F1014),
          appBar: AppBar(
            backgroundColor: const Color(0xFF181A20),
            elevation: 0,
            title: Text(t('Settings'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSectionTitle(t('Preferences')),
              _buildSwitchTile(t('Notifications'), notificationsEnabled, _toggleNotifications),
              _buildListTile(t('Language'), Icons.language, _showLanguageDialog, subtitle: TranslationService().currentLanguage.toUpperCase()),
              
              const SizedBox(height: 24),
              _buildSectionTitle(t('About')),
              _buildListTile(t('Privacy Policy'), Icons.privacy_tip_outlined, () {
                String? link;
                if (settings != null) {
                  link = Platform.isIOS ? settings!['iosPrivacyUrl'] : settings!['androidPrivacyUrl'];
                }
                _openUrl(link != null && link.isNotEmpty ? link : AppConfig.apiBaseUrl.replaceAll('/api', '') + '/privacy-policy');
              }),
              _buildListTile(t('Terms of Service'), Icons.description_outlined, () {
                String? link;
                if (settings != null) {
                  link = Platform.isIOS ? settings!['iosTermsUrl'] : settings!['androidTermsUrl'];
                }
                _openUrl(link != null && link.isNotEmpty ? link : AppConfig.apiBaseUrl.replaceAll('/api', '') + '/terms-of-service');
              }),
              _buildListTile(t('Share App'), Icons.share_outlined, () {
                String? link;
                if (settings != null) {
                  link = Platform.isIOS ? settings!['iosUpdateUrl'] : settings!['androidUpdateUrl'];
                }
                if (link != null && link.isNotEmpty) {
                  _openUrl(link);
                } else if (settings != null && settings!['playStoreLink'] != null) {
                  _openUrl(settings!['playStoreLink']);
                }
              }),
              _buildListTile(t('Rate App'), Icons.star_outline, () {
                String? link;
                if (settings != null) {
                  link = Platform.isIOS ? settings!['iosRateUrl'] : settings!['androidRateUrl'];
                }
                if (link != null && link.isNotEmpty) {
                  _openUrl(link);
                } else if (settings != null && settings!['playStoreLink'] != null) {
                  _openUrl(settings!['playStoreLink']);
                }
              }),
              
              const SizedBox(height: 48),
              ListTile(
                title: Text(t('Delete Account'), style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const DeleteAccountScreen()));
                },
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: const Color(0xFF181A20),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildSwitchTile(String title, bool value, Function(bool) onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: const Color(0xFF181A20), borderRadius: BorderRadius.circular(12)),
      child: SwitchListTile(
        title: Text(title, style: const TextStyle(color: Colors.white)),
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFF00E676),
      ),
    );
  }

  Widget _buildListTile(String title, IconData icon, VoidCallback onTap, {String? subtitle}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: const Color(0xFF181A20), borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: Colors.grey),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        trailing: subtitle != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(subtitle, style: const TextStyle(color: Colors.grey)),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                ],
              )
            : const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}
