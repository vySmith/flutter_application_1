import 'package:flutter/material.dart';
// import 'ShareService.dart'; // 假设你将分享相关的 API 调用放在这里
import 'FileService.dart'; // 或者放在 FileService 里
import 'config.dart';
import 'package:path/path.dart' as p; // 用于处理路径

// 导入你的预览组件 (假设在 file_page.dart 或公共文件)
import 'package:url_launcher/url_launcher.dart'; // 用于其他文件类型预览
import 'preview_helper.dart';

class SharePreviewPage extends StatefulWidget {
  final String shareCode; // 接收分享码

  const SharePreviewPage({Key? key, required this.shareCode}) : super(key: key);

  @override
  _SharePreviewPageState createState() => _SharePreviewPageState();
}

class _SharePreviewPageState extends State<SharePreviewPage> {
  // Future 用于 FutureBuilder
  Future<Map<String, dynamic>>? _shareContentFuture;
  bool _isSaving = false; // 标记是否正在保存

  @override
  void initState() {
    super.initState();
    // 在 initState 中触发加载
    _shareContentFuture = _fetchShareContent();
  }

  // 获取分享内容
  Future<Map<String, dynamic>> _fetchShareContent() async {
    try {
      // 调用 Service 获取分享内容 (假设方法名为 getShareContentByCode)
      final content = await FileService.getShareContentByCode(widget.shareCode);
      return content; // 返回获取到的数据 Map
    } catch (e) {
      print("获取分享内容失败 (Code: ${widget.shareCode}): $e");
      // 重新抛出异常，让 FutureBuilder 捕获并显示错误
      throw Exception('加载分享内容失败: ${e.toString()}');
    }
  }

  // 保存分享到用户的 "/来自分享" 目录
  Future<void> _saveShareToDrive() async {
    if (_isSaving) return; // 防止重复点击
    setState(() => _isSaving = true);

    try {
      // 调用 Service 保存分享 (假设方法名为 saveSharedContent)
      final message =
          await FileService.saveSharedContent(shareCode: widget.shareCode);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message ?? '保存成功!')), // 显示后端返回的消息
      );
      // 保存成功后可以考虑关闭预览页面
      // Navigator.pop(context);
    } catch (e) {
      print("保存分享失败 (Code: ${widget.shareCode}): $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: ${e.toString()}')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  // --- 文件预览逻辑 (与 TrashPage 类似，但使用 owner_id) ---
  void _previewFile(
      BuildContext context, Map<String, dynamic> file, String? ownerId) async {
    final String? filePath = file['path']?.toString();
    final String? format = file['format']?.toString();

    // 预览需要原始所有者的 ID
    if (ownerId == null || filePath == null || filePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法获取预览所需信息 (Owner ID 或 Path)')),
      );
      return;
    }

    // 使用 ownerId 构建预览 URL
    final fileUrlString =
        '${Config.baseUrl}/get_file?user_id=$ownerId&file_path=${Uri.encodeComponent(filePath)}';

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

    print("Attempting to preview shared file: $fileUri");

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('分享预览 (${widget.shareCode})'), // 显示分享码
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _shareContentFuture,
        builder: (context, snapshot) {
          // ---- 1. 处理加载状态 ----
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // ---- 2. 处理错误状态 ----
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, color: Colors.red, size: 50),
                    SizedBox(height: 10),
                    Text(
                      // snapshot.error 包含了我们 throw 的 Exception
                      snapshot.error.toString().replaceFirst("Exception: ", ""),
                      style: TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 20),
                    ElevatedButton.icon(
                      icon: Icon(Icons.refresh),
                      label: Text('重试'),
                      onPressed: () {
                        setState(() {
                          // 重新触发 FutureBuilder
                          _shareContentFuture = _fetchShareContent();
                        });
                      },
                    )
                  ],
                ),
              ),
            );
          }

          // ---- 3. 处理无数据状态 (理论上 Future 完成后应该有数据或错误) ----
          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text('未找到分享内容。'));
          }

          // ---- 4. 成功加载数据 ----
          final shareData = snapshot.data!;
          final String shareRootPath = shareData['share_root_path'] ?? '/';
          // final String shareRootType = shareData['share_root_type'] ?? 'folder'; // 可能有用
          final String? ownerId =
              shareData['owner_id_for_preview']?.toString(); // 获取 Owner ID
          final List<dynamic> itemsDynamic = shareData['items'] ?? [];
          // 类型转换和过滤 null
          final List<Map<String, dynamic>> items = itemsDynamic
              .where((item) => item is Map<String, dynamic>)
              .map((item) => item as Map<String, dynamic>)
              .toList();

          if (items.isEmpty) {
            return Center(child: Text('此分享中没有文件。'));
          }

          return Column(
            children: [
              // (可选) 显示一些分享信息，例如分享的根名称
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text(
                  "分享内容: ${p.basename(shareRootPath)}", // 显示根名称
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final file = items[index];
                    final String name = file['name']?.toString() ?? '未知名称';
                    final String path = file['path']?.toString() ?? '';
                    final String type = file['type']?.toString() ?? 'file';
                    final String format = file['format']?.toString() ?? '';
                    final int size = file['size'] ?? 0;
                    // 计算相对路径用于显示，或显示完整路径
                    // String displayPath = path;
                    // if (path.startsWith(shareRootPath) && path != shareRootPath) {
                    //    displayPath = path.substring(shareRootPath.length).lstrip('/');
                    // }
                    String displayPath = path; // 直接显示完整路径可能更清晰

                    return ListTile(
                      key: ValueKey(file['id'] ?? index),
                      leading: Icon(
                        type == 'folder'
                            ? Icons.folder_outlined
                            : Icons.insert_drive_file_outlined,
                        color: type == 'folder'
                            ? Colors.orangeAccent
                            : Colors.grey,
                      ),
                      title: Text(name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        // 显示相对路径或完整路径 + 大小
                        '路径: $displayPath\n大小: $size bytes',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      isThreeLine: true, // 允许 subtitle 显示两行
                      onTap: (type == 'file') // 文件夹在预览页通常不可点击进入
                          ? () => previewFile(context,
                              file) //_previewFile(context, file, ownerId)
                          : null,
                    );
                  },
                ),
              ),
              // ---- 保存按钮区域 ----
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  // 让按钮宽度适应屏幕
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: _isSaving
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Icon(Icons.save_alt),
                    label: Text(_isSaving ? '正在保存...' : '保存到我的网盘 (/来自分享)'),
                    onPressed:
                        _isSaving ? null : _saveShareToDrive, // 正在保存时禁用按钮
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      // backgroundColor: Theme.of(context).primaryColor, // 使用主题色
                      // foregroundColor: Colors.white,
                    ),
                  ),
                ),
              )
            ],
          );
        },
      ),
    );
  }
}
