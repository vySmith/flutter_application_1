import 'package:flutter/material.dart';
import 'FileService.dart'; // 假设 FileService 正确定义
import 'config.dart'; // 假设 Config 正确定义
import 'file_page.dart'; // 假设预览组件在此文件中
import 'package:url_launcher/url_launcher.dart';
import 'preview_helper.dart';
// 推荐使用 intl 包进行更健壮的日期格式化和计算
// import 'package:intl/intl.dart';

// --- Trash Page ---
class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  _TrashPageState createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  // 使用 ValueNotifier 或其他状态管理方案可以更精细地控制刷新，
  // 但对于简单列表，FutureBuilder + setState 也可以工作。
  Future<List<Map<String, dynamic>>>? _trashedFilesFuture; // 改为可空，以便重新加载

  @override
  void initState() {
    super.initState();
    _loadTrashedFiles(); // 调用加载方法
  }

  // 提取加载逻辑为一个方法，方便重载
  void _loadTrashedFiles() {
    setState(() {
      _trashedFilesFuture = FileService.getTrashedFiles();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站'),
        // leading: IconButton( // AppBar 默认会添加返回按钮如果可以 pop
        //   icon: const Icon(Icons.arrow_back),
        //   onPressed: () => Navigator.pop(context),
        // ),
        actions: [
          IconButton(
            // 添加刷新按钮
            icon: Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _loadTrashedFiles,
          )
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        // 明确 Future 的类型
        future: _trashedFilesFuture,
        builder: (context, snapshot) {
          // 处理不同的连接状态
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator()); // 显示加载指示器
          }
          if (snapshot.hasError) {
            print("Error loading trashed files: ${snapshot.error}"); // 打印错误方便调试
            return Center(
                child: Text('加载回收站列表失败: ${snapshot.error}')); // 显示错误信息
          }
          // 确保 snapshot.hasData 为 true 才继续，并检查数据是否为 null 或空
          if (!snapshot.hasData ||
              snapshot.data == null ||
              snapshot.data!.isEmpty) {
            return const Center(child: Text('回收站是空的')); // 显示空状态信息
          }

          // 数据加载成功且不为空
          final files = snapshot.data!;
          return RefreshIndicator(
            // 添加下拉刷新
            onRefresh: () async => _loadTrashedFiles(),
            child: ListView.builder(
              itemCount: files.length,
              itemBuilder: (ctx, index) => _TrashItem(
                // 使用唯一的 Key
                key: ValueKey(files[index]['id'] ?? index), // 优先使用 ID 作为 Key
                file: files[index],
                onRefresh: _loadTrashedFiles, // 传递刷新方法
              ),
            ),
          );
        },
      ),
    );
  }
}

// --- Trash Item Widget ---
class _TrashItem extends StatelessWidget {
  final Map<String, dynamic> file;
  final VoidCallback onRefresh; // 用于刷新列表的回调

  const _TrashItem(
      {super.key, required this.file, required this.onRefresh}); // 使用 super key

  // 计算剩余天数，添加空值处理和错误处理
  String _getRemainingDaysText(dynamic deletedAtValue) {
    if (deletedAtValue == null) {
      return '未知'; // 如果 deleted_at 为 null，返回 '未知'
    }
    try {
      final deleteDate = DateTime.parse(deletedAtValue.toString());
      // 注意：这里的 30 天应该与后端逻辑一致
      final expiryDate = deleteDate.add(const Duration(days: 30));
      final remaining = expiryDate.difference(DateTime.now());

      if (remaining.isNegative) {
        return '已过期'; // 如果已经超过 30 天
      }
      // 可以根据需要显示更详细的信息，例如 "剩余 X 天 Y 小时"
      return '${remaining.inDays} 天';
    } catch (e) {
      print("Error parsing deleted_at date '$deletedAtValue': $e");
      return '无效日期'; // 如果日期解析失败
    }
  }

  // 弹出确认对话框的辅助函数
  Future<bool> _showConfirmDialog(
      BuildContext context, String title, String content) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // 防止点击外部关闭
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context, false), // 返回 false
          ),
          TextButton(
            // 可以给确定按钮添加醒目颜色
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确定'),
            onPressed: () => Navigator.pop(context, true), // 返回 true
          ),
        ],
      ),
    );
    return result ?? false; // 如果对话框被意外关闭，默认为 false
  }

  @override
  Widget build(BuildContext context) {
    // 安全地获取值，提供默认值
    final String name = file['name']?.toString() ?? '未知文件名';
    final String type = file['type']?.toString() ?? 'file'; // 默认为文件
    final String path = file['path']?.toString() ?? ''; // 路径不能为空，否则操作会失败
    final dynamic deletedAt = file['deleted_at']; // 获取 deleted_at，可能是 null

    // *** 错误修正和优化点 ***
    final String remainingDaysText = _getRemainingDaysText(deletedAt);

    return ListTile(
      leading: Icon(
        type == 'folder'
            ? Icons.folder_delete_outlined
            : Icons.restore_from_trash_outlined, // 使用更形象的回收站图标
        color: Colors.grey[600],
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('剩余: $remainingDaysText', style: TextStyle(fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min, // 让 Row 只占用必要的宽度
        children: [
          // 恢复按钮
          IconButton(
            icon: const Icon(Icons.restore, color: Colors.green),
            tooltip: '恢复文件', // 添加提示
            onPressed: path.isEmpty
                ? null
                : () async {
                    // 如果路径为空则禁用按钮
                    final confirmed = await _showConfirmDialog(
                        context, '确认恢复', '确定要恢复 "$name" 吗？');
                    if (confirmed) {
                      try {
                        await FileService.restoreFile(path);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('"$name" 已恢复')),
                        );
                        onRefresh(); // 调用回调刷新列表
                      } catch (e) {
                        print("Error restoring file '$path': $e");
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('恢复失败: ${e.toString()}')),
                        );
                      }
                    }
                  },
          ),
          // 永久删除按钮
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
            tooltip: '永久删除', // 添加提示
            onPressed: path.isEmpty
                ? null
                : () async {
                    // 如果路径为空则禁用按钮
                    final confirmed = await _showConfirmDialog(
                        context, '确认永久删除', '此操作不可恢复，确定要删除 "$name" 吗？');
                    if (confirmed) {
                      try {
                        await FileService.permanentDelete(path);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('"$name" 已永久删除')),
                        );
                        onRefresh(); // 调用回调刷新列表
                      } catch (e) {
                        print("Error permanently deleting file '$path': $e");
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('删除失败: ${e.toString()}')),
                        );
                      }
                    }
                  },
          ),
        ],
      ),
      // 优化：文件夹通常不可预览，只允许预览文件
      onTap: (type == 'file' && path.isNotEmpty)
          ? () => _previewFile(context, file)
          : null, // 文件夹或路径为空时禁用 onTap
    );
  }

  // --- 文件预览逻辑 (基本保持不变，增加健壮性) ---
  void _previewFile(BuildContext context, Map<String, dynamic> file) async {
    final userId = await FileService.getUserId(); // 假设 FileService 能获取用户 ID

    final String? filePath = file['path']?.toString(); // 安全获取路径
    final String? format = file['format']?.toString(); // 安全获取格式

    if (userId == null || filePath == null || filePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法获取预览所需信息')),
      );
      return;
    }

    final fileUrlString =
        '${Config.baseUrl}/get_file?user_id=$userId&file_path=${Uri.encodeComponent(filePath)}';

    Uri? fileUri;
    try {
      fileUri = Uri.parse(fileUrlString);
    } catch (e) {
      print("Error parsing preview URL '$fileUrlString': $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法构建预览链接')),
      );
      return;
    }

    print("Attempting to preview: $fileUri");

    // 使用 file_page.dart 中的 isImageFile/isVideoFile
    if (isImageFile(format)) {
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => PhotoViewGalleryScreen(imageUrl: fileUrlString)),
      );
    } else if (isVideoFile(format)) {
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => VideoPreviewScreen(videoUrl: fileUrlString)),
      );
    } else {
      // 其他文件尝试用 url_launcher 打开
      if (await canLaunchUrl(fileUri)) {
        try {
          await launchUrl(fileUri, mode: LaunchMode.externalApplication);
        } catch (e) {
          print("Error launching URL '$fileUri': $e");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('启动外部应用失败: ${e.toString()}')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未找到可打开此文件类型的应用')),
        );
      }
    }
  }
}

// 假设 file_page.dart 中有以下辅助函数 (如果不在，需要在此文件或公共文件中定义)
// bool isImageFile(String? format) { ... }
// bool isVideoFile(String? format) { ... }
// class PhotoViewGalleryScreen extends StatelessWidget { ... }
// class VideoPreviewScreen extends StatefulWidget { ... }
