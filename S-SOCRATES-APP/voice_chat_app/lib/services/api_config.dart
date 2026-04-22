import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  static String? _baseUrl;

  static String _normalizeBaseUrl(String raw) {
    var value = raw.trim();
    if (value.isEmpty) {
      value = 'http://172.29.87.82:8000';
    }

    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }

    if (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }

    return value;
  }

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final persisted = prefs.getString('api_base_url');
    if (persisted != null && persisted.trim().isNotEmpty) {
      _baseUrl = _normalizeBaseUrl(persisted);
    }
  }

  static String get baseUrl {
    final raw =
        _baseUrl ?? const String.fromEnvironment('API_BASE_URL', defaultValue: 'http://172.29.87.82:8000');
    return _normalizeBaseUrl(raw);
  }

  static String get robotWebSocketUrl {
    final normalizedBase = baseUrl;
    final wsUrl = normalizedBase.startsWith('https://')
        ? normalizedBase.replaceFirst('https://', 'wss://')
        : normalizedBase.replaceFirst('http://', 'ws://');
    return '$wsUrl/ws/robot';
  }

  static Future<void> setBaseUrl(String url) async {
    final normalized = _normalizeBaseUrl(url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_base_url', normalized);
    _baseUrl = normalized;
  }
}
