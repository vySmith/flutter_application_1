import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'config.dart';
import 'dart:convert';

// --- 需要在 UserService.dart 或类似文件中实现 ---
class UserService {
  // 获取用户配置信息
  static Future<Map<String, dynamic>> getUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');
    if (userId == null) throw Exception('User not logged in');

    final response = await http.get(
      Uri.parse('${Config.baseUrl}/user/profile?user_id=$userId'), // 使用 GET 请求
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded['status'] == 'success') {
        return decoded['data']; // 返回用户信息 Map
      } else {
        throw Exception(decoded['message'] ?? 'Failed to load user profile');
      }
    } else {
      throw Exception(
          'Failed to load user profile (HTTP ${response.statusCode})');
    }
  }

  // 更新用户昵称
  static Future<void> updateNickname(String newNickname) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');
    if (userId == null) throw Exception('User not logged in');

    final response = await http.post(
      Uri.parse('${Config.baseUrl}/user/update_nickname'),
      body: {
        'user_id': userId,
        'nickname': newNickname,
      },
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded['status'] != 'success') {
        throw Exception(decoded['message'] ?? 'Failed to update nickname');
      }
      // 更新成功，无需返回数据
    } else {
      throw Exception(
          'Failed to update nickname (HTTP ${response.statusCode})');
    }
  }
  // --- 分享相关的 API 调用 ---
  // (createShareLink, verifyShareCode, getShareContent, saveSharedContent 等方法也应放在这里或专门的 ShareService 中)
}
