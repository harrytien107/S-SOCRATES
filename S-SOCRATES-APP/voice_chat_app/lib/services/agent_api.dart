import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AgentAPI {
  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  Uri get _chatUri => Uri.parse('$_apiBaseUrl/chat');

  Future<String> sendMessage(String message) async {
    try {
      final response = await http
          .post(
            _chatUri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'message': message}),
          )
          .timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reply = data['response'];
        if (reply is String && reply.trim().isNotEmpty) {
          return reply;
        }
        throw Exception('Backend trả phản hồi rỗng.');
      }

      if (response.statusCode == 500) {
        throw Exception(
            'Backend lỗi nội bộ (500). Kiểm tra Ollama có đang chạy không.');
      }

      throw Exception('API lỗi ${response.statusCode}: ${response.body}');
    } on TimeoutException {
      throw Exception(
          'Hết thời gian chờ (timeout). Backend hoặc Ollama phản hồi quá lâu.');
    } on http.ClientException catch (e) {
      debugPrint('AgentAPI ClientException: $e');
      throw Exception(
          'Không kết nối được backend tại $_apiBaseUrl. '
          'Kiểm tra backend đang chạy và CORS đã bật.');
    }
  }
}
