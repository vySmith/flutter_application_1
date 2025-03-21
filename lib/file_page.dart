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

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.videoUrl)
      ..initialize().then((_) {
        setState(() {});
        _controller.play();
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

  // 状态变量新增
  Set<String> _selectedFiles = Set(); // 存储选中文件ID
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
      if (_selectedFiles.length == _filteredFiles.length) {
        _selectedFiles.clear();
      } else {
        _selectedFiles = Set.from(
            _filteredFiles.map((file) => file['id'].toString()).toList());
      }
    });
  }

  Widget _buildActionButton(
      IconData icon, String label, VoidCallback onPressed) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon),
          onPressed: onPressed, // 添加缺失的 required 参数
        ),
        Text(label),
      ],
    );
  }

  // 从后端获取文件列表
  Future<void> _fetchFileList() async {
    // TODO: 从用户登录状态获取用户ID
    final prefs =
        await SharedPreferences.getInstance(); // 获取 SharedPreferences 实例
    final userId = prefs.getString('userId'); // 从 SharedPreferences 中获取 userId

    setState(() {
      _isLoading = true; // 开始加载时显示加载状态
    });

    if (userId == null) {
      // 如果 userId 为空，说明用户未登录或登录状态已丢失，需要处理
      print('User ID not found in SharedPreferences');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('用户未登录，请重新登录')),
      );
      setState(() {
        _isLoading = false;
      });
      return; // 终止函数执行
    }
    _userId = userId; //  设置 userId 状态

    final path = widget.path;
    final apiUrl =
        Uri.parse('${Config.baseUrl}/file_list?user_id=$userId&path=$path');

    try {
      final response = await http.get(apiUrl);
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _allFiles = data
              .cast<Map<String, dynamic>>(); // 强制转换为 Map<String, dynamic> 列表
          _filteredFiles = _allFiles;
          _isLoading = false; // 加载完成
          //排序功能
          _filteredFiles.sort((a, b) {
            switch (_sortBy) {
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
        });
      } else {
        // 处理错误情况
        print('Failed to load file list: ${response.statusCode}');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('加载文件列表失败')),
        );
        setState(() {
          _isLoading = false; // 加载失败也需要停止加载状态
        });
      }
    } catch (e) {
      print('Error fetching file list: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('加载文件列表出错')),
      );
      setState(() {
        _isLoading = false; // 加载失败也需要停止加载状态
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
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
      ),
      body: _isLoading // 根据加载状态显示不同的 UI
          ? const Center(child: CircularProgressIndicator()) // 加载中显示加载指示器
          : Column(
              children: [
                buildFunctionBar(),
                // 文件列表
                Expanded(
                  child: ListView.builder(
                    itemCount: _filteredFiles.length,
                    itemBuilder: (context, index) {
                      final file = _filteredFiles[index];
                      return ListTile(
                        leading: file['format'] != null &&
                                ['jpg', 'jpeg', 'png', 'gif', 'bmp'].contains(
                                    file['format']
                                        .toString()
                                        .toLowerCase()) // 判断是否是图片格式
                            ? Image.network(
                                // 使用 Image.network 显示缩略图，你需要后端提供访问图片的 URL
                                '${Config.baseUrl}/get_file?user_id=$_userId&file_path=${Uri.encodeComponent('${widget.path}${file['name']}')}',
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    Icon(Icons.image), // 加载失败显示默认图片图标
                              )
                            : Icon(
                                file['type'] == 'folder'
                                    ? Icons.folder
                                    : Icons.insert_drive_file,
                              ),
                        title: Text(file['name'] ?? 'Unknown Name'),
                        trailing: _isSelectionMode
                            ? Checkbox(
                                value: _selectedFiles
                                    .contains(file['id'].toString()),
                                onChanged: (_) => _enterSelectionMode(file),
                              )
                            : null,
                        subtitle: Text(
                            '大小: ${file['size'] ?? 'Unknown Size'} bytes, 更新时间: ${file['updated_at'] != null ? file['updated_at'].toString().substring(0, 25) : 'Unknown Date'}'),
                        onTap: () {
                          if (file['type'] == 'folder') {
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
                          if (_selectedFiles.isEmpty) {
                            _enterSelectionMode(file);
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            builder: (context) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo),
                  title: const Text('上传照片'),
                  onTap: () async {
                    Navigator.pop(context);
                    final refreshList = await Navigator.push(
                      // 等待 UploadPhotoPage 返回结果
                      context,
                      MaterialPageRoute(
                        builder: (context) => UploadPage(
                            uploadType: 'photo', currentPath: widget.path),
                        //UploadPhotoPage(path: widget.path), // 传递 path
                      ),
                    );
                    if (refreshList == true) {
                      // 如果返回 true，则刷新文件列表
                      _fetchFileList();
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.video_library),
                  title: const Text('上传视频'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => UploadPage(
                          uploadType: 'video',
                          currentPath: widget.path,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.insert_drive_file),
                  title: const Text('上传文档'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => UploadPage(
                            uploadType: 'document', currentPath: widget.path),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.audiotrack),
                  title: const Text('上传音频'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => UploadPage(
                            uploadType: 'audio', currentPath: widget.path),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.file_upload),
                  title: const Text('上传其他文件'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => UploadPage(
                            uploadType: 'other', currentPath: widget.path),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder),
                  title: const Text('创建文件夹'),
                  onTap: () {
                    Navigator.pop(context);
                    // TODO: 实现创建文件夹逻辑
                    _showCreateFolderDialog(); // 显示创建文件夹对话框
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.note),
                  title: const Text('新建笔记'),
                  onTap: () {
                    Navigator.pop(context);
                    // TODO: 实现新建笔记逻辑
                  },
                ),
              ],
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

// 新增预览方法
  void _previewFile(Map<String, dynamic> file) async {
    final fileUrl =
        '${Config.baseUrl}/get_file?user_id=$_userId&file_path=${Uri.encodeComponent('${widget.path}${file['name']}')}';

    if (file['format'] != null &&
        ['jpg', 'jpeg', 'png', 'gif', 'bmp']
            .contains(file['format'].toString().toLowerCase())) {
      // 图片预览
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => PhotoViewGalleryScreen(imageUrl: fileUrl)));
    } else if (isVideoFile(file['format'])) {
      // 视频预览
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => VideoPreviewScreen(videoUrl: fileUrl)));
    } else {
      // 其他文件用系统应用打开
      if (await canLaunch(fileUrl)) {
        await launch(fileUrl);
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
  Widget _buildSelectionAppBar() {
    return AppBar(
      leading: IconButton(
        icon: Icon(Icons.close),
        onPressed: _exitSelectionMode,
      ),
      title: Text('已选中 ${_selectedFiles.length} 个文件'),
      actions: [
        IconButton(
          icon: Icon(_selectedFiles.length == _filteredFiles.length
              ? Icons.check_box_outline_blank
              : Icons.check_box),
          onPressed: _toggleSelectAll,
        ),
      ],
    );
  }

  // 构建底部操作栏
  Widget _buildBottomActionBar() {
    return BottomAppBar(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // _buildActionButton(Icons.download, '下载', _handleDownload),
          // _buildActionButton(Icons.share, '分享', _handleShare),
          // _buildActionButton(Icons.delete, '删除', _handleDelete),
          // _buildActionButton(
          //     Icons.drive_file_rename_outline, '重命名', _handleRename),
          // _buildActionButton(Icons.drive_file_move, '移动', _handleMove),
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

  // 调用后端 API 创建文件夹
  Future<void> _createFolder(String folderName) async {
    if (folderName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件夹名称不能为空')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');
    if (userId == null) {
      // ... 用户未登录处理 ...
      return;
    }

    final apiUrl = Uri.parse('${Config.baseUrl}/create_folder');
    try {
      final response = await http.post(
        apiUrl,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded'
        }, // 使用 form-urlencoded 格式
        body: {
          'user_id': userId,
          'path': widget.path,
          'folder_name': folderName,
        },
      );

      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('文件夹 "$folderName" 创建成功')),
        );
        _fetchFileList(); // 创建成功后刷新文件列表
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '文件夹 "$folderName" 创建失败: ${jsonDecode(response.body)['message']}')),
        );
      }
    } catch (e) {
      print('Error creating folder: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('创建文件夹出错，请检查网络')),
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
}
