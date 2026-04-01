import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  static String? _baseUrl;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('api_base_url');
  }

  static String get baseUrl {
    return _baseUrl ?? const String.fromEnvironment('API_BASE_URL', defaultValue: 'http://192.168.1.7:8000');
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_base_url', url);
    _baseUrl = url;
  }
}
