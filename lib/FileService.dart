// lib/services/file_service.dart
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'config.dart';
import 'dart:convert';

import 'transfer_provider.dart';
import 'TransferService.dart';

class FileService {
  static final Uuid _uuid = Uuid();

  // 获取用户ID（私有方法）
  static Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('userId');
  }

  // 获取文件列表
  static Future<List<Map<String, dynamic>>> getFileList({
    required String path,
    required String sortBy,
  }) async {
    final userId = await getUserId();
    if (userId == null) throw Exception('用户未登录');

    try {
      final response = await http
          .get(
            Uri.parse(
                '${Config.baseUrl}/file_list?user_id=$userId&path=${Uri.encodeComponent(path)}'),
          )
          .timeout(const Duration(seconds: 10)); //超时处理

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
    final userId = await getUserId();
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
    final userId = await getUserId();
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

  // 下载文件（获取下载链接）
  static Future<String> getDownloadUrl({
    required String filePath,
  }) async {
    final userId = await getUserId();
    final encodedPath = Uri.encodeComponent(filePath);
    return '${Config.baseUrl}/download?user_id=$userId&file_path=$encodedPath';
  }

  // 删除文件
  static Future<void> deleteFile({
    required String filePath,
  }) async {
    final userId = await getUserId();
    final response = await http.post(
      Uri.parse('${Config.baseUrl}/delete_file'),
      body: {
        'user_id': userId,
        'file_path': filePath,
      },
    );
    if (response.statusCode != 200) throw Exception('删除失败');
  }

  // 重命名文件
  static Future<void> renameFile({
    required String oldPath,
    required String newName,
  }) async {
    final userId = await getUserId();
    final response = await http.post(
      Uri.parse('${Config.baseUrl}/rename_file'),
      body: {
        'user_id': userId,
        'old_path': oldPath,
        'new_name': newName,
      },
    );
    if (response.statusCode != 200) throw Exception('重命名失败');
  }

  //断点续传服务
  // file_service.dart
  static Future<TransferTask> uploadWithResume({
    required String filePath,
    required String targetPath,
    required TransferProvider provider,
  }) async {
    final task = TransferTask(
      id: _uuid.v4(),
      filePath: filePath,
      remotePath: targetPath,
    );

    provider.addUpload(task);

    final service = TransferService();
    await service.uploadFile(
      task: task,
      onProgress: (progress) {
        task.progress = progress;
        provider.notifyListeners();
      },
    );

    return task;
  }

// 获取回收站文件
  static Future<List<Map<String, dynamic>>> getTrashedFiles() async {
    final userId = await getUserId();
    final response = await http.get(
      Uri.parse('${Config.baseUrl}/trashed_files?user_id=$userId'),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      List<Map<String, dynamic>> files = data.cast<Map<String, dynamic>>();
      return files;
      //return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    }
    throw Exception('加载失败');
  }

  // 恢复文件
  static Future<void> restoreFile(String filePath) async {
    final userId = await getUserId();
    final response = await http.post(
      Uri.parse('${Config.baseUrl}/restore_file'),
      body: {'user_id': userId, 'file_path': filePath},
    );
    if (response.statusCode != 200) throw Exception('恢复失败');
  }

  // 永久删除
  static Future<void> permanentDelete(String filePath) async {
    final userId = await getUserId();
    final response = await http.post(
      Uri.parse('${Config.baseUrl}/permanent_delete'),
      body: {'user_id': userId, 'file_path': filePath},
    );
    if (response.statusCode != 200) throw Exception('删除失败');
  }

// --- 新增：创建分享链接 ---
  static Future<String> createShareLink({
    required String fileId, // Use String for ID consistency if needed
    int? expiresInDays, // Optional expiration
  }) async {
    final userId = await getUserId();
    if (userId == null) throw Exception('User not logged in');

    final Map<String, String> body = {
      'user_id': userId,
      'file_id': fileId,
    };
    if (expiresInDays != null) {
      body['expires_in_days'] = expiresInDays.toString();
    }

    print("Sending create share request for fileId: $fileId"); // Debug log

    final response = await http.post(
      Uri.parse('${Config.baseUrl}/share/create'),
      body: body,
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded['status'] == 'success' && decoded['share_code'] != null) {
        print(
            "Share created successfully, code: ${decoded['share_code']}"); // Debug log
        return decoded['share_code']; // 返回分享码
      } else {
        throw Exception(decoded['message'] ?? 'Failed to create share link');
      }
    } else {
      String errorMessage =
          'Failed to create share link (HTTP ${response.statusCode})';
      try {
        final decodedError = jsonDecode(response.body);
        errorMessage = decodedError['message'] ?? errorMessage;
      } catch (_) {}
      print("Error creating share link: $errorMessage"); // Debug log
      throw Exception(errorMessage);
    }
  }

// 获取分享内容
  static Future<Map<String, dynamic>> getShareContentByCode(
      String shareCode) async {
    final uri = Uri.parse('${Config.baseUrl}/share/content_by_code')
        .replace(queryParameters: {'code': shareCode});
    print("Requesting share content: $uri"); // 调试打印
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded['status'] == 'success') {
        return decoded; // 返回包含 items, share_root_path 等的整个 Map
      } else {
        throw Exception(decoded['message'] ?? 'Failed to load share content');
      }
    } else {
      // 尝试解析后端 abort 返回的 description
      String errorMessage =
          'Failed to load share content (HTTP ${response.statusCode})';
      try {
        final decodedError = jsonDecode(response.body);
        errorMessage = decodedError['description'] ?? errorMessage;
      } catch (_) {}
      throw Exception(errorMessage);
    }
  }

// 保存分享内容
  static Future<String?> saveSharedContent({required String shareCode}) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');
    if (userId == null) throw Exception('User not logged in');

    final response = await http.post(
      Uri.parse('${Config.baseUrl}/share/save'),
      body: {
        'user_id': userId,
        'share_code': shareCode,
      },
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded['status'] == 'success') {
        return decoded['message']; // 返回后端成功的消息
      } else {
        throw Exception(decoded['message'] ?? 'Failed to save share');
      }
    } else {
      String errorMessage =
          'Failed to save share (HTTP ${response.statusCode})';
      try {
        final decodedError = jsonDecode(response.body);
        errorMessage =
            decodedError['message'] ?? errorMessage; // 后端 save 接口返回 message
      } catch (_) {}
      throw Exception(errorMessage);
    }
  }

// --- 取消分享 ---
  static Future<void> cancelShare(String shareCode) async {
    final userId = await getUserId();
    if (userId == null) throw Exception('User not logged in');

    print("Sending cancel share request for code: $shareCode");

    final response = await http.post(
      Uri.parse('${Config.baseUrl}/share/cancel'),
      body: {
        'user_id': userId,
        'share_code': shareCode,
      },
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded['status'] != 'success') {
        throw Exception(decoded['message'] ?? 'Failed to cancel share');
      }
      // 取消成功
    } else {
      String errorMessage =
          'Failed to cancel share (HTTP ${response.statusCode})';
      try {
        final decodedError = jsonDecode(response.body);
        errorMessage = decodedError['message'] ?? errorMessage;
      } catch (_) {}
      throw Exception(errorMessage);
    }
  }

  //获取分享列表
  static Future<List<Map<String, dynamic>>> getMyShares() async {
    final userId = await FileService.getUserId();
    if (userId == null) throw Exception('User not logged in');

    final uri = Uri.parse('${Config.baseUrl}/shares/my')
        .replace(queryParameters: {'user_id': userId});
    print("Requesting my shares: $uri");

    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded['status'] == 'success' && decoded['data'] is List) {
        // 后端返回的是 List<dynamic>，需要转换
        return List<Map<String, dynamic>>.from(decoded['data']);
      } else {
        throw Exception(decoded['message'] ?? 'Failed to load my shares');
      }
    } else {
      throw Exception('Failed to load my shares (HTTP ${response.statusCode})');
    }
  }
}

// 其他操作（删除、重命名、创建文件夹等）...
