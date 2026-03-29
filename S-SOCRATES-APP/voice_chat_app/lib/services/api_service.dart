import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:voice_chat_app/services/api_config.dart';

class CommandPollResult {
  final Map<String, dynamic>? command;
  final bool reachable;

  const CommandPollResult({
    required this.command,
    required this.reachable,
  });
}

class ApiService {
  static Future<CommandPollResult> getLatestCommand() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/latest-command'),
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data != null && data is Map<String, dynamic>) {
          return CommandPollResult(command: data, reachable: true);
        }
        return const CommandPollResult(command: null, reachable: true);
      }
    } catch (e) {
      debugPrint('Polling Error: $e (Target: ${ApiConfig.baseUrl})');
      return const CommandPollResult(command: null, reachable: false);
    }
    return const CommandPollResult(command: null, reachable: false);
  }
}
