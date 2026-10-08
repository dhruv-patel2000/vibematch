import 'package:flutter/material.dart';
import 'package:country_picker/country_picker.dart';
import '../../../core/services/translation_service.dart';

class MatchFilterBottomSheet extends StatefulWidget {
  final Map<String, dynamic> user;
  final String initialGender;
  final String initialRegion;
  final bool initialSuperMatch;

  const MatchFilterBottomSheet({
    super.key,
    required this.user,
    required this.initialGender,
    required this.initialRegion,
    required this.initialSuperMatch,
  });

  @override
  State<MatchFilterBottomSheet> createState() => _MatchFilterBottomSheetState();
}

class _MatchFilterBottomSheetState extends State<MatchFilterBottomSheet> {
  late String _selectedGender;
  late String _selectedRegion;
  late bool _superMatch;

  @override
  void initState() {
    super.initState();
    _selectedGender = widget.initialGender;
    _selectedRegion = widget.initialRegion;
    _superMatch = widget.initialSuperMatch;
  }

  bool get _isVip {
    return widget.user['isVip'] == true || (widget.user['vipExpiry'] != null && DateTime.tryParse(widget.user['vipExpiry'].toString())?.isAfter(DateTime.now()) == true);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF15161C),
        borderRadius: BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                TranslationService().t('Gender Filter'),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: Colors.white10, shape: BoxShape.circle),
                  child: const Icon(Icons.close, color: Colors.white70, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            TranslationService().t('Select preferred gender & region for video matching'),
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 30),
          
          Text(TranslationService().t('MATCH WITH').toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildGenderOption('both', 'Both'),
              const SizedBox(width: 12),
              _buildGenderOption('female', 'Female'),
              const SizedBox(width: 12),
              _buildGenderOption('male', 'Male'),
            ],
          ),
          const SizedBox(height: 24),

          Text(TranslationService().t('PREFERRED REGION').toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              if (!_isVip) {
                _showVipUpsell();
                return;
              }
              showCountryPicker(
                context: context,
                countryListTheme: CountryListThemeData(
                  backgroundColor: const Color(0xFF15161C),
                  textStyle: const TextStyle(color: Colors.white),
                  searchTextStyle: const TextStyle(color: Colors.white),
                  bottomSheetHeight: MediaQuery.of(context).size.height * 0.7,
                ),
                onSelect: (Country country) {
                  setState(() {
                    _selectedRegion = country.countryCode;
                  });
                },
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _isVip ? const Color(0xFF00E676) : Colors.white24),
              ),
              child: Row(
                children: [
                  Text(_selectedRegion == 'all' ? '🌍' : _countryCodeToEmoji(_selectedRegion), style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                        _selectedRegion == 'all' ? TranslationService().t('All Countries') : _selectedRegion,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (_selectedRegion != 'all')
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedRegion = 'all';
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
                          child: const Icon(Icons.close, color: Colors.white54, size: 16),
                        ),
                      )
                    else
                      const Icon(Icons.keyboard_arrow_down, color: Colors.white54),
                  ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E212B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.orange.withOpacity(0.2), shape: BoxShape.circle),
                  child: const Icon(Icons.auto_awesome, color: Colors.orangeAccent),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('Super Match', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)),
                            child: const Text('HOT', style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "Super Match finds people you're more likely to click with.",
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _superMatch,
                  activeColor: const Color(0xFF00E676),
                  onChanged: (val) {
                    if (!_isVip) {
                      _showVipUpsell();
                      return;
                    }
                    setState(() {
                      _superMatch = val;
                    });
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF262A34),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () {
                Navigator.pop(context, {
                  'gender': _selectedGender,
                  'region': _selectedRegion,
                  'superMatch': _superMatch,
                });
              },
              child: const Text('Save Preferences', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildGenderOption(String value, String label) {
    final isSelected = _selectedGender == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (value != 'both' && !_isVip) {
            _showVipUpsell();
            return;
          }
          setState(() {
            _selectedGender = value;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isSelected ? const Color(0xFF00E676) : Colors.white24, width: isSelected ? 2 : 1),
          ),
          child: Column(
            children: [
              Icon(
                value == 'both' ? Icons.people : (value == 'female' ? Icons.face_3 : Icons.face),
                color: value == 'both' ? Colors.purpleAccent : (value == 'female' ? Colors.orangeAccent : Colors.amber),
                size: 32,
              ),
              const SizedBox(height: 8),
              Text(
                TranslationService().t(label),
                style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showVipUpsell() {
    Navigator.pop(context, {'action': 'open_store', 'tab': 'vip'});
  }

  String _countryCodeToEmoji(String countryCode) {
    if (countryCode.isEmpty || countryCode == 'all') return '🌍';
    return countryCode.toUpperCase().replaceAllMapped(
      RegExp(r'[A-Z]'),
      (match) => String.fromCharCode(match.group(0)!.codeUnitAt(0) + 127397)
    );
  }
}


