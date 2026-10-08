import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'package:country_picker/country_picker.dart';
import '../../../core/config/app_config.dart';
import '../../home/presentation/main_navigation_screen.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> user;

  const EditProfileScreen({super.key, required this.user});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  String? _usernameErrorText;
  Timer? _debounceTimer;

  late TextEditingController _nameController;
  late TextEditingController _usernameController;
  late TextEditingController _bioController;
  late TextEditingController _ageController;
  late TextEditingController _phoneController;
  String _gender = 'female';
  String _country = 'United States';
  String _countryCode = 'US';
  File? _avatarImage;
  String? _generatedAvatarUrl;

  @override
  void initState() {
    super.initState();
    final Map<String, dynamic> rawUser = widget.user['user'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(widget.user['user'])
        : Map<String, dynamic>.from(widget.user);

    _nameController = TextEditingController(text: rawUser['name'] ?? '');
    _usernameController = TextEditingController(text: rawUser['username'] ?? '');
    _bioController = TextEditingController(text: rawUser['bio'] ?? '');
    _ageController = TextEditingController(text: rawUser['age']?.toString() ?? '18');
    _phoneController = TextEditingController(text: rawUser['phone'] ?? '');
    _gender = (rawUser['gender'] != null && rawUser['gender'].toString().isNotEmpty) ? rawUser['gender'] : 'female';
    _country = (rawUser['country'] != null && rawUser['country'].toString().isNotEmpty) ? rawUser['country'] : 'United States';
    _countryCode = (rawUser['countryCode'] != null && rawUser['countryCode'].toString().isNotEmpty) ? rawUser['countryCode'] : 'US';
    
    _usernameController.addListener(_onUsernameChanged);
  }

  void _onUsernameChanged() {
    final text = _usernameController.text.trim().toLowerCase();
    
    final rawUser = widget.user['user'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(widget.user['user'])
        : Map<String, dynamic>.from(widget.user);
        
    if (text == (rawUser['username'] ?? '').toString().toLowerCase()) {
      setState(() {
        _isUsernameAvailable = null;
        _usernameErrorText = null;
        _isCheckingUsername = false;
      });
      return;
    }

    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();

    if (text.isEmpty) {
      setState(() {
        _isUsernameAvailable = null;
        _usernameErrorText = 'Username cannot be empty';
        _isCheckingUsername = false;
      });
      return;
    }

    if (!RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(text)) {
      setState(() {
        _isUsernameAvailable = false;
        _usernameErrorText = '3-20 chars: a-z, 0-9, _';
        _isCheckingUsername = false;
      });
      return;
    }

    setState(() {
      _isCheckingUsername = true;
      _usernameErrorText = null;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 600), () async {
      try {
        final dio = Dio();
        final res = await dio.get('${AppConfig.apiBaseUrl}/users/check-username', queryParameters: {'username': text});
        if (mounted) {
          setState(() {
            _isCheckingUsername = false;
            _isUsernameAvailable = res.data['available'] == true;
            if (_isUsernameAvailable == false) {
              _usernameErrorText = res.data['error'] ?? 'Username is already taken';
            } else {
              _usernameErrorText = null;
            }
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isCheckingUsername = false;
            _isUsernameAvailable = null;
            _usernameErrorText = 'Error checking username';
          });
        }
      }
    });
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _avatarImage = File(pickedFile.path);
      });
    }
  }

  void _pickCountry() {
    showCountryPicker(
      context: context,
      showPhoneCode: false,
      onSelect: (Country country) {
        setState(() {
          _country = country.name;
          _countryCode = country.countryCode;
        });
      },
      countryListTheme: const CountryListThemeData(
        backgroundColor: Color(0xFF1E293B),
        textStyle: TextStyle(color: Colors.white),
        searchTextStyle: TextStyle(color: Colors.white),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_isUsernameAvailable == false || _usernameErrorText != null || _isCheckingUsername) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please choose a valid username before saving.'),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }
    
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? prefs.getString('token');

      final dio = Dio();
      String? newAvatarUrl;

      if (_avatarImage != null) {
        final formData = FormData.fromMap({
          'avatar': await MultipartFile.fromFile(_avatarImage!.path, filename: 'avatar.jpg'),
        });
        try {
          final uploadRes = await dio.post(
            '${AppConfig.apiBaseUrl}/users/upload',
            data: formData,
            options: Options(headers: {'Authorization': 'Bearer $token', 'Content-Type': 'multipart/form-data'}),
          );
          if (uploadRes.statusCode == 200 && uploadRes.data['url'] != null) {
            newAvatarUrl = uploadRes.data['url'];
          }
        } catch (e) {
          debugPrint('Upload failed: $e');
        }
      }

      final updateData = {
        'name': _nameController.text.trim(),
        'username': _usernameController.text.trim(),
        'bio': _bioController.text.trim(),
        'age': int.tryParse(_ageController.text) ?? 18,
        'phone': _phoneController.text.trim(),
        'gender': _gender,
        'country': _country,
        'countryCode': _countryCode,
      };

      if (newAvatarUrl != null) {
        updateData['avatar'] = newAvatarUrl;
      } else if (_generatedAvatarUrl != null) {
        updateData['avatar'] = _generatedAvatarUrl!;
      }

      final res = await dio.put(
        '${AppConfig.apiBaseUrl}/users/me',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
        data: updateData,
      );

      if (res.statusCode == 200) {
        final updatedUser = (res.data is Map && res.data['user'] != null)
            ? Map<String, dynamic>.from(res.data['user'])
            : Map<String, dynamic>.from(res.data);

        // Update local prefs
        await prefs.setString('user', jsonEncode(updatedUser));
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated successfully!')));
          if (Navigator.canPop(context)) {
            Navigator.pop(context, updatedUser); // Return updated user
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => MainNavigationScreen(user: updatedUser)),
            );
          }
        }
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.response?.data['error'] ?? e.message}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Slate 900
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          _isLoading
              ? const Center(child: Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
              : TextButton(
                  onPressed: _saveProfile,
                  child: const Text('Save', style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 16)),
                )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: const Color(0xFF334155),
                        backgroundImage: _avatarImage != null
                              ? FileImage(_avatarImage!) as ImageProvider
                              : (_generatedAvatarUrl != null
                                  ? NetworkImage(_generatedAvatarUrl ?? '') as ImageProvider
                                  : (widget.user['avatar'] != null && widget.user['avatar'].isNotEmpty
                                      ? NetworkImage(widget.user['avatar'].startsWith('http') ? widget.user['avatar'] : AppConfig.apiBaseUrl.replaceAll('/api', '') + widget.user['avatar'])
                                      : null)),
                        child: _avatarImage == null && (widget.user['avatar'] == null || widget.user['avatar'].isEmpty)
                            ? const Icon(Icons.person, size: 50, color: Colors.white54)
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Color(0xFF00E676),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.edit, size: 20, color: Colors.black),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),
              
              _buildTextField('Name', _nameController, Icons.person_outline),
              const SizedBox(height: 20),
              _buildTextField(
                'Username', 
                _usernameController, 
                Icons.alternate_email,
                errorText: _usernameErrorText,
                suffixIcon: _isCheckingUsername 
                    ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                    : (_isUsernameAvailable == true 
                        ? const Icon(Icons.check_circle, color: Color(0xFF00E676))
                        : (_isUsernameAvailable == false ? const Icon(Icons.cancel, color: Colors.redAccent) : null)),
              ),
              const SizedBox(height: 20),
              _buildTextField('Bio', _bioController, Icons.info_outline, maxLines: 3),
              const SizedBox(height: 20),
              _buildTextField('Age', _ageController, Icons.calendar_today, isNumber: true),
              const SizedBox(height: 20),
              _buildTextField('Phone', _phoneController, Icons.phone, isNumber: true),
              const SizedBox(height: 20),
              
              const Text('Gender', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildGenderOption('Male', 'male', Icons.male),
                  const SizedBox(width: 16),
                  _buildGenderOption('Female', 'female', Icons.female),
                ],
              ),
              const SizedBox(height: 20),

              const Text('Country', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickCountry,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.public, color: Colors.white54),
                      const SizedBox(width: 16),
                      Text(
                        _country,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      const Spacer(),
                      const Icon(Icons.arrow_drop_down, color: Colors.white54),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label, 
    TextEditingController controller, 
    IconData icon, 
    {
      int maxLines = 1, 
      bool isNumber = false, 
      Widget? suffixIcon,
      String? errorText,
    }
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            prefixIcon: maxLines == 1 ? Icon(icon, color: Colors.white54) : null,
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: const Color(0xFF1E293B),
            errorText: errorText,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return '$label is required';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildGenderOption(String label, String value, IconData icon) {
    final isSelected = _gender == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _gender = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF00E676).withOpacity(0.15) : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? const Color(0xFF00E676) : Colors.transparent, width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isSelected ? const Color(0xFF00E676) : Colors.white54, size: 20),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: isSelected ? const Color(0xFF00E676) : Colors.white, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
            ],
          ),
        ),
      ),
    );
  }
}
