import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:voice_chat_app/services/api_config.dart';

class AgentAPI {

  Future<Map<String, dynamic>?> processAudio(String filePath) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/process-audio'),
      );
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 45),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data.containsKey('error')) {
          throw Exception(data['error']);
        }
        return data; // Chứa cả transcript và candidates
      }
      throw Exception('Process Audio Server Error ${response.statusCode}');
    } catch (e) {
      debugPrint('AgentAPI processAudio error: $e');
      return null;
    }
  }

  Future<String> speechToText(String filePath) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/stt'),
      );
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 45),
      );
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

  Future<void> syncRobotMicStatus(String status) async {
    try {
      await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/robot/mic-sync'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'status': status}),
          )
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('AgentAPI syncRobotMicStatus error: $e');
    }
  }

  /// Báo cho Server biết App đã upload xong audio, reset chu kỳ
  Future<void> notifyMicDone() async {
    try {
      await http
          .post(Uri.parse('${ApiConfig.baseUrl}/robot/mic-done'))
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('AgentAPI notifyMicDone error: $e');
    }
  }

  /// Đồng bộ ngược: App báo cho Backend khi người dùng chạm Orb thủ công
  Future<void> sendMicControl(String action) async {
    try {
      await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/robot/mic-control'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'action': action}),
          )
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('AgentAPI sendMicControl error: $e');
    }
  }
}
