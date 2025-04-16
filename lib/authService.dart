import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'package:shared_preferences/shared_preferences.dart';

// In AuthService.dart or similar
class AuthService {
  static Future<bool> refreshToken(String refreshToken) async {
    try {
      final response = await http.post(
        Uri.parse('${Config.baseUrl}/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newAccessToken = data['access_token'];
        final newExpiresAt = data['expires_at']; // 毫秒时间戳

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('access_token', newAccessToken);
        await prefs.setInt('token_expires_at', newExpiresAt);
        print("Token refreshed and saved.");
        return true; // 刷新成功
      } else {
        print("Refresh token API returned status: ${response.statusCode}");
        return false; // 刷新失败
      }
    } catch (e) {
      print("Error calling refresh token API: $e");
      return false; // 网络或其他错误
    }
  }
  // ... 其他认证方法 ...
}
