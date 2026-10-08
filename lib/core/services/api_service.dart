import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

class ApiService {
  static final Dio _dio = Dio(BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: const Duration(milliseconds: AppConfig.connectionTimeout),
    receiveTimeout: const Duration(milliseconds: AppConfig.receiveTimeout),
    headers: {
      'x-api-key': AppConfig.apiAccessKey,
      'Accept': 'application/json',
    },
  ));

  static void init() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_token != null) {
          options.headers['Authorization'] = 'Bearer $_token';
        }
        return handler.next(options);
      },
      onError: (DioException e, handler) {
        if (e.type == DioExceptionType.connectionTimeout || 
            e.type == DioExceptionType.receiveTimeout || 
            e.type == DioExceptionType.unknown ||
            e.response?.statusCode == 401 ||
            e.response?.statusCode == 403) {
          // You could use a stream/event bus here to trigger UI, 
          // or handle it in the UI layer when it returns null/error.
          debugPrint("Network or Auth Error: Please check internet connection or API Key.");
        }
        return handler.next(e);
      }
    ));
  }
  
  static String? _token;

  static Future<void> sendFCMToken(String token) async {
    try {
      await _dio.post('/auth/fcm-token', data: {'token': token});
    } catch (e) {
      debugPrint('Failed to send FCM token: $e');
    }
  }

  static Future<Map<String, dynamic>?> guestLogin() async {
    try {
      final res = await _dio.post('/auth/guest');
      _token = res.data['token'];
      return res.data;
    } on DioException catch (e) {
      return {'error': 'check_internet_connection'};
    }
  }

  static Future<Map<String, dynamic>?> socialLogin(Map<String, dynamic> data) async {
    try {
      final String provider = data['provider'] ?? '';
      final String uid = data['firebaseUid'] ?? '';
      
      String username;
      String password;
      
      if (provider == 'anonymous') {
        final String pId = (data['persistentGuestId'] as String?) ?? uid;
        username = pId.startsWith('guest_') ? pId : 'guest_$pId';
        if (username.length > 20) {
          username = username.substring(0, 20);
        }
        password = 'guest123';
      } else {
        final String email = data['email'] ?? '';
        username = email.isNotEmpty ? email : '${provider}_user';
        password = '${provider}123';
      }
      
      final payload = {
        'username': username,
        'password': password,
        'extraData': {
          'name': data['name'] ?? (provider == 'anonymous' ? 'Guest' : ''),
          'firebaseUid': uid,
          'avatar': data['avatar'],
          'provider': provider,
          'email': data['email']
        }
      };
      
      final res = await _dio.post('/auth/login', data: payload);
      _token = res.data['token'];
      return res.data;
    } on DioException catch (e) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getSettings() async {
    try {
      final response = await _dio.get('/init');
      return response.data;
    } catch (e) {
      return {'error': 'check_internet_connection'};
    }
  }
}
