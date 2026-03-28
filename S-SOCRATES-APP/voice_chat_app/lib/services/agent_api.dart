import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:voice_chat_app/services/api_config.dart';

class AgentAPI {
  Uri get _chatUri => Uri.parse('${ApiConfig.baseUrl}/chat');

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
          'Không kết nối được backend tại ${ApiConfig.baseUrl}. '
          'Kiểm tra backend đang chạy và CORS đã bật.');
    }
  }

  Future<String> speechToText(String filePath) async {
    try {
      final request =
          http.MultipartRequest('POST', Uri.parse('${ApiConfig.baseUrl}/stt'));
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      final streamedResponse =
          await request.send().timeout(const Duration(seconds: 45));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data.containsKey('error')) {
          throw Exception(data['error']);
        }
        return data['text'] ?? '';
      }
      throw Exception('STT Server Error ${response.statusCode}');
    } catch (e) {
      debugPrint('AgentAPI speechToText error: $e');
      throw Exception('Lỗi nhận diện giọng nói: $e');
    }
  }
  Future<Map<String, dynamic>?> getRobotCommand() async {
    try {
      final response = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/robot-command'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data != null && data is Map<String, dynamic>) {
          return data;
        }
      }
      return null;
    } catch (e) {
      debugPrint('AgentAPI getRobotCommand error: $e');
      return null;
    }
  }
}
