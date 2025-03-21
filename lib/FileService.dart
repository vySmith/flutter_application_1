// lib/services/file_service.dart
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

class FileService {
  // 获取用户ID（私有方法）
  static Future<String?> _getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('userId');
  }

  // 获取文件列表
  static Future<List<Map<String, dynamic>>> getFileList({
    required String path,
    required String sortBy,
  }) async {
    final userId = await _getUserId();
    if (userId == null) throw Exception('用户未登录');

    try {
      final response = await http.get(
        Uri.parse(
            '${Config.baseUrl}/file_list?user_id=$userId&path=${Uri.encodeComponent(path)}'),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        List<Map<String, dynamic>> files = data.cast<Map<String, dynamic>>();

        // 排序逻辑
        files.sort((a, b) {
          switch (sortBy) {
            case '文件名':
              return a['name'].compareTo(b['name']);
            case '文件类型':
              return a['format'].compareTo(b['format']);
            case '文件大小':
              return (a['size'] as num).compareTo(b['size'] as num);
            case '修改时间':
              return DateTime.parse(b['updated_at'])
                  .compareTo(DateTime.parse(a['updated_at']));
            case '打开时间':
              return DateTime.parse(b['opened_at'])
                  .compareTo(DateTime.parse(a['opened_at']));
            default:
              return 0;
          }
        });

        return files;
      } else {
        throw Exception('加载失败: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('网络请求失败: $e');
    }
  }

// 创建文件夹
  static Future<void> createFolder({
    required String path,
    required String folderName,
  }) async {
    final userId = await _getUserId();
    if (userId == null) throw Exception('用户未登录');

    try {
      final response = await http.post(
        Uri.parse('${Config.baseUrl}/create_folder'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'user_id': userId,
          'path': path,
          'folder_name': folderName,
        },
      );

      if (response.statusCode != 201) {
        final errorMessage = jsonDecode(response.body)['message'] ?? '未知错误';
        throw Exception('创建失败: $errorMessage');
      }
    } catch (e) {
      throw Exception('操作失败: $e');
    }
  }

  // 上传文件到后端
  // 上传文件
  static Future<void> uploadFiles({
    required List<String> filePaths,
    required String targetPath,
  }) async {
    final userId = await _getUserId();
    if (userId == null) throw Exception('用户未登录');

    try {
      for (final filePath in filePaths) {
        var request = http.MultipartRequest(
          'POST',
          Uri.parse('${Config.baseUrl}/upload'),
        );

        request.fields['user_id'] = userId;
        request.fields['path'] = targetPath;
        request.files.add(await http.MultipartFile.fromPath('file', filePath));

        final response = await request.send();
        if (response.statusCode != 201) {
          throw Exception('上传失败: ${filePath.split('/').last}');
        }
      }
    } catch (e) {
      throw Exception('上传过程出错: $e');
    }
  }
}

// 其他操作（删除、重命名、创建文件夹等）...
