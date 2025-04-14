import 'package:flutter/material.dart';
import 'upload_page.dart'; // 导入上传页面
import 'config.dart'; // 替换 your_project_name 为你的项目名
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart'; // 导入 shared_preferences
import 'upload_photo_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:flutter/services.dart'; // <--- 添加这行
import 'FileService.dart';

// 添加文件类型判断方法
bool isImageFile(String? format) {
  if (format == null) return false;
  return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp']
      .contains(format.toLowerCase());
}

bool isVideoFile(String? format) {
  if (format == null) return false;
  return ['mp4', 'mov', 'avi', 'mkv', 'flv', 'wmv']
      .contains(format.toLowerCase());
}

// 图片预览组件
class PhotoViewGalleryScreen extends StatelessWidget {
  final String imageUrl;

  const PhotoViewGalleryScreen({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: PhotoView(
        imageProvider: NetworkImage(imageUrl),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 2,
      ),
    );
  }
}

// 视频预览组件
class VideoPreviewScreen extends StatefulWidget {
  final String videoUrl;

  const VideoPreviewScreen({required this.videoUrl});

  @override
  _VideoPreviewScreenState createState() => _VideoPreviewScreenState();
}

class _VideoPreviewScreenState extends State<VideoPreviewScreen> {
  late VideoPlayerController _controller;
  bool _initialized = false; // 标记初始化状态
  bool _hasError = false; // 标记是否有错误

  @override
  void initState() {
    super.initState();
    print(
        "VideoPreviewScreen initState: Initializing video from ${widget.videoUrl}");
    Uri? videoUri;
    try {
      videoUri = Uri.parse(widget.videoUrl); // 解析 Uri
    } catch (e) {
      print("Error parsing video URL: ${widget.videoUrl}, Error: $e");
      setState(() {
        _hasError = true; // 标记错误状态
      });
      return; // 如果 URL 无效，则不继续初始化
    }

    _controller = VideoPlayerController.networkUrl(videoUri)
      ..initialize().then((_) {
        setState(() {
          _initialized = true;
          _hasError = false;
        });
        _controller.play();
        _controller.setLooping(true); // 可以选择循环播放
      }).catchError((error) {
        // 初始化失败
        print("Error initializing video player: $error");
        setState(() {
          _initialized = false; // 确保 initialized 为 false
          _hasError = true; // 标记错误状态
        });
      });
  }

  @override
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: _controller.value.isInitialized
          ? AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            )
          : Center(child: CircularProgressIndicator()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class FilePage extends StatefulWidget {
  final String path; // 当前路径，默认为根目录
  const FilePage({Key? key, this.path = '/'}) : super(key: key);

  @override
  _FilePageState createState() => _FilePageState();
}

class _FilePageState extends State<FilePage> {
  final TextEditingController _searchController = TextEditingController();
  String _sortBy = '文件名'; // 默认排序方式
  List<Map<String, dynamic>> _allFiles = []; // 文件列表，类型改为 dynamic 以适应不同数据类型
  List<Map<String, dynamic>> _filteredFiles = [];
  bool _isLoading = true; // 加载状态
  String? _userId; //  新增：用于存储 userId 的状态变量
  bool _isProcessingShare = false; // Add state for share processing
  // 状态变量新增
  Set<String> _selectedFiles = {}; // 存储选中文件ID
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    _fetchFileList(); // 初始化时加载文件列表
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedFiles.clear();
    });
  }

  void _toggleSelectAll() {
    setState(() {
      final allFileIds = _filteredFiles.map((f) => f['id'].toString()).toSet();
      if (_selectedFiles.length == allFileIds.length) {
        _selectedFiles.clear();
      } else {
        _selectedFiles = allFileIds;
      }
    });
  }

  // Widget _buildActionButton(
  //     IconData icon, String label, VoidCallback onPressed) {
  //   return Column(
  //     mainAxisSize: MainAxisSize.min,
  //     children: [
  //       IconButton(
  //         icon: Icon(icon),
  //         onPressed: onPressed, // 添加缺失的 required 参数
  //       ),
  //       Text(label),
  //     ],
  //   );
  // }

  // --- 修改 _buildActionButton 以支持禁用状态 (可选但推荐) ---
  Widget _buildActionButton(
      IconData icon, String label, VoidCallback? onPressed) {
    // onPressed 改为可空
    final bool enabled = onPressed != null;
    final Color? iconColor =
        enabled ? Theme.of(context).iconTheme.color : Colors.grey;
    final Color? textColor =
        enabled ? Theme.of(context).textTheme.bodySmall?.color : Colors.grey;

    return InkWell(
      onTap: onPressed, // 直接使用传入的 onPressed
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: iconColor),
            SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, color: textColor)),
          ],
        ),
      ),
    );
  }

  // 获取文件列表
  Future<void> _fetchFileList() async {
    setState(() => _isLoading = true);
    try {
      final files = await FileService.getFileList(
        path: widget.path,
        sortBy: _sortBy,
      );
      final userId = await FileService.getUserId();
      _userId = userId;
      setState(() {
        _allFiles = files;
        _filteredFiles = files;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

// 新增切换单个文件选择的方法
  void _toggleFileSelection(Map<String, dynamic> file) {
    final fileId = file['id'].toString();
    setState(() {
      if (_selectedFiles.contains(fileId)) {
        _selectedFiles.remove(fileId);
        //if (_selectedFiles.isEmpty) _exitSelectionMode();
      } else {
        _selectedFiles.add(fileId);
        //_isSelectionMode = true; // 确保进入选择模式
      }
    });
  }

  Widget _buildFileList() {
    return ListView.builder(
      itemCount: _filteredFiles.length,
      itemBuilder: (context, index) {
        final file = _filteredFiles[index];

        // Determine the leading icon
        Widget leadingIcon;
        if (isImageFile(file['format'])) {
          final imageUrl =
              '${Config.baseUrl}/get_file?user_id=$_userId&file_path=${Uri.encodeComponent(file['path'] ?? '')}';
          leadingIcon = Image.network(
            imageUrl,
            width: 50, // Slightly smaller thumbnail
            height: 50,
            fit: BoxFit.cover,
            // Provide hints for caching smaller images
            cacheWidth:
                80, // Request slightly larger for better quality if device pixel ratio > 1
            cacheHeight: 80,
            errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.image,
                size: 40), // Default image icon on error
          );
        } else if (file['type'] == 'folder') {
          leadingIcon = const Icon(Icons.folder,
              size: 40, color: Colors.orangeAccent); // Colored folder
        } else {
          leadingIcon = const Icon(Icons.insert_drive_file,
              size: 40, color: Colors.grey); // Default file icon
        }

        return ListTile(
          leading: leadingIcon,
          title: Text(file['name'] ?? 'Unknown Name'),
          trailing: _isSelectionMode
              ? Checkbox(
                  value: _selectedFiles.contains(file['id'].toString()),
                  onChanged: (_) => _toggleFileSelection(file),
                )
              : null,
          subtitle: Text(
              '大小: ${file['size'] ?? 'Unknown Size'} bytes, 更新时间: ${file['updated_at'] != null ? file['updated_at'].toString().substring(0, 25) : 'Unknown Date'}'),
          onTap: () {
            if (_isSelectionMode) {
              _toggleFileSelection(file);
            } else if (file['type'] == 'folder') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FilePage(
                    path: '${widget.path}${file['name']}/',
                  ),
                ),
              );
            } else {
              // TODO: 文件点击事件，例如下载、预览等
              _previewFile(file);
            }
          },
          onLongPress: () {
            if (!_isSelectionMode) {
              _enterSelectionMode(file);
            }
          },
        );
      },
    );
  }

  AppBar _builddefaultAppBar() {
    return AppBar(
      leading: widget.path != '/'
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            )
          : null, // 根目录不显示返回按钮
      title: TextField(
        controller: _searchController,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: '搜索文件...',
          border: InputBorder.none,
        ),
        onChanged: (value) {
          setState(() {
            _filteredFiles = _allFiles
                .where((file) => file['name']
                    .toString()
                    .toLowerCase()
                    .contains(value.toLowerCase())) // 搜索过滤，注意判空和转小写
                .toList(); // 搜索过滤
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          _isSelectionMode ? _buildSelectionAppBar() : _builddefaultAppBar(),
      // body: _isLoading // 根据加载状态显示不同的 UI
      //     ? const Center(child: CircularProgressIndicator()) // 加载中显示加载指示器
      //     : Column(
      //         children: [
      //           buildFunctionBar(),
      //           // 文件列表
      //           Expanded(child: _buildFileList())
      //         ],
      //       ),
      body: RefreshIndicator(
        // Added pull-to-refresh
        onRefresh: _fetchFileList, // Refresh action re-fetches the list
        child: Column(
          children: [
            // Consider making the function bar optional or placed differently
            // buildFunctionBar(), // This was the sort/filter bar
            // File list takes remaining space
            Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildFileList() // Display the file list or empty message
                )
          ],
        ),
      ),
      bottomNavigationBar: _isSelectionMode ? _buildBottomActionBar() : null,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            builder: (context) => _buildAddContentSheet(),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  // Extracted BottomSheet content for clarity
  Widget _buildAddContentSheet() {
    return Wrap(
      // Use Wrap for better layout if many items
      children: [
        ListTile(
          leading:
              const Icon(Icons.photo_library_outlined), // Use outlined icons
          title: const Text('上传照片'),
          onTap: () => _handleUpload('photo'),
        ),
        ListTile(
          leading: const Icon(Icons.video_library_outlined),
          title: const Text('上传视频'),
          onTap: () => _handleUpload('video'),
        ),
        ListTile(
          leading: const Icon(Icons.file_present_outlined),
          title: const Text('上传文档'),
          onTap: () => _handleUpload('document'),
        ),
        ListTile(
          leading: const Icon(Icons.audiotrack_outlined),
          title: const Text('上传音频'),
          onTap: () => _handleUpload('audio'),
        ),
        ListTile(
          leading: const Icon(Icons.upload_file_outlined),
          title: const Text('上传其他文件'),
          onTap: () => _handleUpload('other'),
        ),
        Divider(), // Separator
        ListTile(
          leading: const Icon(Icons.create_new_folder_outlined),
          title: const Text('创建文件夹'),
          onTap: () {
            Navigator.pop(context); // Close sheet first
            _showCreateFolderDialog(); // Then show dialog
          },
        ),
        // ListTile( // Example for future feature
        //   leading: const Icon(Icons.note_add_outlined),
        //   title: const Text('新建笔记'),
        //   onTap: () {
        //     Navigator.pop(context);
        //     // TODO: Implement note creation
        //   },
        // ),
      ],
    );
  }

  // Common handler for Upload actions
  Future<void> _handleUpload(String uploadType) async {
    Navigator.pop(context); // Close bottom sheet
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            UploadPage(uploadType: uploadType, currentPath: widget.path),
      ),
    );
    // If UploadPage returns true, refresh the list
    if (result == true && mounted) {
      _fetchFileList();
    }
  }

// 新增预览方法
  void _previewFile(Map<String, dynamic> file) async {
    final fileUrlString =
        '${Config.baseUrl}/get_file?user_id=$_userId&file_path=${Uri.encodeComponent('${file['path']}')}';

    Uri? fileUri; // Uri 可以为 null
    try {
      fileUri = Uri.parse(fileUrlString); // 尝试将字符串解析为 Uri
    } catch (e) {
      print("Error parsing URL: $fileUrlString, Error: $e");
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('无法解析文件链接')));
      return; // 如果 URL 无效则停止执行
    }

    final String format =
        (file['format'] ?? '').toString().toLowerCase(); // 获取格式并转小写

    if (file['format'] != null &&
        ['jpg', 'jpeg', 'png', 'gif', 'bmp']
            .contains(file['format'].toString().toLowerCase())) {
      // 图片预览
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => PhotoViewGalleryScreen(imageUrl: fileUrlString)));
    } else if (isVideoFile(file['format'])) {
      // 视频预览
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => VideoPreviewScreen(videoUrl: fileUrlString)));
    } else {
      // 其他文件用系统应用打开
      if (await canLaunchUrl(fileUri)) {
        try {
          // 对于 http/https 链接，通常不需要指定 mode
          // 如果是本地文件 file:// uri，可能需要 LaunchMode.externalApplication
          await launchUrl(fileUri,
              mode: LaunchMode.externalApplication); // 使用 launchUrl 和 Uri
        } catch (e) {
          print("Error launching URL: $fileUri, Error: $e");
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('启动外部应用失败: $e')));
        }
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法打开此文件类型')));
      }
    }
  }

  // 进入选择模式
  void _enterSelectionMode(Map<String, dynamic> initialFile) {
    setState(() {
      _isSelectionMode = true;
      _selectedFiles.add(initialFile['id'].toString());
    });
  }

// 构建顶部操作栏
  AppBar _buildSelectionAppBar() {
    return AppBar(
      leading: IconButton(
        icon: Icon(Icons.close),
        onPressed: _exitSelectionMode,
      ),
      title: Text('已选中 ${_selectedFiles.length} 个文件'),
      actions: [
        IconButton(
          icon: Icon(_selectedFiles.length == _filteredFiles.length
              ? Icons.check_box
              : Icons.check_box_outline_blank),
          onPressed: _toggleSelectAll,
        ),
      ],
    );
  }

  // 构建底部操作栏
  // Widget _buildBottomActionBar() {
  //   return BottomAppBar(
  //     child: Row(
  //       mainAxisAlignment: MainAxisAlignment.spaceAround,
  //       children: [
  //         // _buildActionButton(Icons.download, '下载', _handleDownload),
  //          _buildActionButton(Icons.share, '分享', _handleShare),
  //         _buildActionButton(Icons.delete, '删除', _handleDelete),
  //         // _buildActionButton(
  //         //     Icons.drive_file_rename_outline, '重命名', _handleRename),
  //         // _buildActionButton(Icons.drive_file_move, '移动', _handleMove),
  //       ],
  //     ),
  //   );
  // }
  // --- 修改底部操作栏 ---
  Widget _buildBottomActionBar() {
    // 分享按钮是否启用 (仅当选中了 1 个文件时)
    final bool canShare = _selectedFiles.length == 1;

    return BottomAppBar(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // _buildActionButton(Icons.download, '下载', _handleDownload), // Placeholder
          _buildActionButton(
              Icons.share_outlined, // Use outlined icon
              '分享',
              // 只有当 canShare 为 true 时传递 _handleShare，否则传递 null (禁用按钮)
              canShare ? _handleShare : null),
          _buildActionButton(
              Icons.delete_outline, // Use outlined icon
              '删除',
              // 删除按钮可以在选中至少一项时启用
              _selectedFiles.isNotEmpty ? _handleDelete : null),
          // _buildActionButton(Icons.drive_file_rename_outline, '重命名', _handleRename), // Placeholder
          // _buildActionButton(Icons.drive_file_move_outline, '移动', _handleMove), // Placeholder
        ],
      ),
    );
  }

  // 显示创建文件夹对话框
  Future<void> _showCreateFolderDialog() async {
    String folderName = '';
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('创建文件夹'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                TextField(
                  decoration: const InputDecoration(
                    hintText: '文件夹名称',
                  ),
                  onChanged: (value) {
                    folderName = value;
                  },
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('取消'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('创建'),
              onPressed: () {
                Navigator.of(context).pop();
                _createFolder(folderName); // 调用创建文件夹函数
              },
            ),
          ],
        );
      },
    );
  }

  // 创建文件夹
  Future<void> _createFolder(String folderName) async {
    try {
      await FileService.createFolder(
        path: widget.path,
        folderName: folderName,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('文件夹 "$folderName" 创建成功')),
      );
      _fetchFileList();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Widget buildFunctionBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        DropdownButton<String>(
          value: _sortBy,
          items: ['打开时间', '修改时间', '文件名', '文件类型', '文件大小']
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (value) => setState(() => _sortBy = value!),
        ),
        IconButton(
          icon: Icon(Icons.filter_list),
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('筛选'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('来源：'),
                    Wrap(
                      children: ['全部', '我创建的', '我上传的', '来自共享的']
                          .map((e) => Padding(
                                padding: EdgeInsets.all(4.0),
                                child: Chip(label: Text(e)),
                              ))
                          .toList(),
                    ),
                    Text('类型：'),
                    Wrap(
                      children: ['图片', '视频', '文档', '音频', '其他文件']
                          .map((e) => Padding(
                                padding: EdgeInsets.all(4.0),
                                child: Chip(label: Text(e)),
                              ))
                          .toList(),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('确定'),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

// void _handleDownload() async {
//   try {
//     final url = await FileService.getDownloadUrl(filePath: file['path']);
//     if (await canLaunch(url)) {
//       await launch(url); // 使用浏览器下载
//     }
//   } catch (e) {
//     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('下载失败')));
//   }
// }

  void _handleDelete() async {
    if (_selectedFiles.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('将删除选中的 ${_selectedFiles.length} 个文件'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final List<Future> deleteTasks = [];

      // 遍历所有选中文件
      for (final fileId in _selectedFiles) {
        // 根据文件ID找到对应文件对象
        final file = _allFiles.firstWhere(
          (f) => f['id'].toString() == fileId,
          //orElse: () => null,
        );

        if (file != null) {
          deleteTasks.add(FileService.deleteFile(filePath: file['path']));
        }
      }

      await Future.wait(deleteTasks);

      // 刷新列表并退出选择模式
      _fetchFileList();
      _exitSelectionMode();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败: ${e.toString()}')),
      );
    }
  }

// --- 新增：显示分享码对话框 ---
  Future<void> _showShareCodeDialog(String shareCode, String fileName) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // 用户必须点击按钮关闭
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('分享成功'),
          content: SingleChildScrollView(
            // 防止内容过多溢出
            child: ListBody(
              children: <Widget>[
                Text('文件 "$fileName" 的分享码为:'),
                SizedBox(height: 10),
                // 显示分享码，并使其易于复制
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        shareCode,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2, // 增加字母间距
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.copy, size: 20),
                        tooltip: '复制分享码',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: shareCode));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('分享码已复制到剪贴板')),
                          );
                        },
                      )
                    ],
                  ),
                ),
                SizedBox(height: 10),
                Text('请将此分享码告知给接收者。',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('关闭'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // --- 新增：处理分享操作 ---
  Future<void> _handleShare() async {
    if (_selectedFiles.length != 1 || _isProcessingShare) {
      // 如果选中数量不是1，或正在处理分享，则不执行
      return;
    }

    final selectedFileId = _selectedFiles.first; // 获取唯一选中的文件 ID

    // 从列表中找到对应的文件信息 (可选，用于显示文件名)
    final file = _allFiles.firstWhere(
      (f) => f['id']?.toString() == selectedFileId,
      orElse: () => <String, dynamic>{}, // 如果找不到返回空 Map
    );
    final fileName = file['name'] ?? '未知文件'; // 获取文件名

    if (!mounted) return;
    setState(() => _isProcessingShare = true); // 开始处理，显示加载状态 (如果需要UI反馈)

    try {
      // 调用 FileService 创建分享链接
      final shareCode =
          await FileService.createShareLink(fileId: selectedFileId);

      if (!mounted) return; // 异步操作后检查 mounted

      // 显示分享码给用户
      await _showShareCodeDialog(shareCode, fileName);

      // 分享成功后退出选择模式
      _exitSelectionMode();
    } catch (e) {
      print("处理分享失败: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('创建分享失败: ${e.toString()}')),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessingShare = false); // 结束处理
      }
    }
  }

// void _handleRename() async {
//   final newName = await showDialog<String>(...); // 弹出输入对话框
//   if (newName != null) {
//     try {
//       await FileService.renameFile(
//         oldPath: file['path'],
//         newName: newName,
//       );
//       _fetchFileList();
//     } catch (e) {
//       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('重命名失败')));
//     }
//   }
// }
// --- 获取我的分享列表 ---
}
