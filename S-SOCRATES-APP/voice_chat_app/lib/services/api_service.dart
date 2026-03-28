import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:voice_chat_app/services/api_config.dart';

class ApiService {
  static Future<Map<String, dynamic>?> getLatestCommand() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/latest-command'),
      ).timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data != null && data is Map<String, dynamic>) {
          return data;
        }
      }
    } catch (e) {
      debugPrint('Polling Error: $e (Target: ${ApiConfig.baseUrl})');
    }
    return null;
  }
}
