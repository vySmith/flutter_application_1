import 'package:flutter/material.dart';
import 'config.dart'; //
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'transfer_provider.dart';
import 'package:flutter/services.dart'; // <--- 添加这行
import 'FileService.dart';
import 'preview_helper.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p; // For basename
import 'dart:io'; // <--- 导入 dart:io 来使用 Directory 和 File
import 'package:path_provider/path_provider.dart'; // <--- 导入 path_provider
import 'transfer_page.dart';
import 'package:permission_handler/permission_handler.dart';

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
          final int? fileId = file['id'];
          final int? physical_fileId = file['physical_file_id'];
          final String? filePath = file['path']?.toString();
          // final imageUrl =
          //     '${Config.baseUrl}/get_file?user_id=$_userId&file_path=${Uri.encodeComponent(file['path'] ?? '')}';
          final imageUrl =
              '${Config.baseUrl}/get_file?user_id=$_userId&file_id=$fileId&physical_file_id=$physical_fileId&file_path=${Uri.encodeComponent(filePath!)}';

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
              //_previewFile(file);
              previewFile(context, file);
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
    // final result = await Navigator.push(
    //   context,
    //   MaterialPageRoute(
    //     builder: (context) =>
    //         UploadPage(uploadType: uploadType, currentPath: widget.path),
    //   ),
    // );
    // // If UploadPage returns true, refresh the list
    // if (result == true && mounted) {
    //   _fetchFileList();
    // }
    // --- 使用 pushNamed 并传递参数 ---
    final result = await Navigator.pushNamed(
      context,
      '/upload', // 使用路由名称
      arguments: {
        // 通过 arguments 传递参数
        'uploadType': uploadType,
        'currentPath': widget.path,
      },
    );
    // -----------------------------

    // 处理返回结果
    if (result == true && mounted) {
      _fetchFileList(); // 刷新文件列表
    }
    // 如果之前没有 pop，可以在这里 pop
    if (Navigator.canPop(context)) {
      // Navigator.pop(context); // 关闭 Bottom Sheet
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

  Future<String?> _getTargetDownloadDirectory(String fileName) async {
    PermissionStatus status = PermissionStatus.denied; // 默认拒绝状态

    try {
      if (Platform.isAndroid) {
        print("正在请求 Android 存储权限...");
        status = await Permission.storage.request();
        print("Android 存储权限状态: $status");
      } else if (Platform.isIOS) {
        // iOS 保存到公共目录困难，所以我们直接获取应用文档目录
        // 但如果后续要保存到相册，那里会单独请求 photos 权限
        status = PermissionStatus.granted; // 假设文档目录可写
        print("iOS 平台，默认使用应用文档目录。");
      } else {
        status = PermissionStatus.granted; // 其他平台暂时假设可以
        print("其他平台，假设有权限。");
      }
    } catch (e) {
      print("请求权限时出错: $e");
      // 将 status 设为拒绝，以便后续逻辑知道出错了
      status = PermissionStatus.denied;
    }

    // --- 检查权限结果 ---
    if (!status.isGranted) {
      print("存储权限未被授予 (状态: $status)");
      // 可以根据具体状态给出更详细提示
      String message = '需要存储权限才能下载文件到公共目录。';
      if (status.isPermanentlyDenied) {
        message += ' 请在系统设置中手动开启权限。';
        // 可以引导用户去设置
        openAppSettings(); // permission_handler 提供的函数
      } else if (status.isRestricted) {
        message = '存储权限受限，无法下载。';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return null; // 返回 null 表示无法继续
    }

    // --- 权限已授予，继续获取目录 ---
    Directory? downloadsDir;
    String? downloadPath;
    String targetDirDescription = "应用文档目录"; // 用于日志

    if (Platform.isAndroid) {
      //   try {
      //     print("尝试获取公共 Downloads 目录...");
      //     downloadsDir = await getDownloadsDirectory(); // 优先尝试这个
      //     if (downloadsDir != null) {
      //       targetDirDescription = "公共 Downloads 目录";
      //       String appDownloadDir =
      //           p.join(downloadsDir.path, 'CloudS_Downloads'); // 应用名子目录
      //       final dir = Directory(appDownloadDir);
      //       if (!await dir.exists()) {
      //         await dir.create(recursive: true);
      //         print("在公共下载目录中创建了子目录: $appDownloadDir");
      //       }
      //       downloadPath = p.join(appDownloadDir, fileName);
      //       print("将使用公共下载目录下的子目录: $downloadPath");
      //     } else {
      //       print("无法获取公共下载目录。");
      //     }
      //   } catch (e) {
      //     print("获取公共下载目录时出错: $e");
      //   }
      // }
      try {
        final Directory docDir = await getApplicationDocumentsDirectory();
        // 在文档目录下也创建一个 Downloads 子目录，保持一致性
        String appDocDownloadDir = p.join(docDir.path, 'Downloads');
        final dir = Directory(appDocDownloadDir);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        downloadPath = p.join(appDocDownloadDir, fileName);
        targetDirDescription = "应用文档目录";
        print("回退到应用文档目录: $downloadPath");
      } catch (e) {
        print("获取应用文档目录时出错: $e");
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('无法获取应用文档目录: ${e.toString()}')));
        return null; // 连文档目录都获取失败，则无法下载
      }
      // // 回退到应用文档目录
      // if (downloadPath == null) {
      //   try {
      //     final Directory docDir = await getApplicationDocumentsDirectory();
      //     // 在文档目录下也创建一个 Downloads 子目录，保持一致性
      //     String appDocDownloadDir = p.join(docDir.path, 'Downloads');
      //     final dir = Directory(appDocDownloadDir);
      //     if (!await dir.exists()) {
      //       await dir.create(recursive: true);
      //     }
      //     downloadPath = p.join(appDocDownloadDir, fileName);
      //     targetDirDescription = "应用文档目录";
      //     print("回退到应用文档目录: $downloadPath");
      //   } catch (e) {
      //     print("获取应用文档目录时出错: $e");
      //     ScaffoldMessenger.of(context).showSnackBar(
      //         SnackBar(content: Text('无法获取应用文档目录: ${e.toString()}')));
      //     return null; // 连文档目录都获取失败，则无法下载
      //   }
      // }
    }
    // --- 文件名冲突处理 ---
    int counter = 1;
    String finalPath = downloadPath!; // 此时 downloadPath 必不为 null
    final base = p.basenameWithoutExtension(finalPath);
    final ext = p.extension(finalPath);
    while (await File(finalPath).exists()) {
      finalPath = p.join(p.dirname(downloadPath), '$base($counter)$ext');
      counter++;
      if (counter > 100) {
        print("文件名冲突过多，无法保存: $downloadPath");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('目标位置 (${targetDirDescription}) 文件名冲突过多')),
        );
        return null;
      }
    }
    if (finalPath != downloadPath) {
      print("文件名冲突，最终路径调整为: $finalPath");
    } else {
      print("最终下载路径确定为: $finalPath (位于: ${targetDirDescription})");
    }
    return finalPath;
  }

// --- 下载处理函数 ---
  Future<void> _handleDownload() async {
    if (_selectedFiles.isEmpty) return;

    final List<TransferTask> downloadTasks = [];
    int addedCount = 0;
    bool errorOccurred = false;

    // --- 遍历选中的文件 ---
    for (final fileId in _selectedFiles) {
      final file = _allFiles.firstWhere(
        (f) => f['id']?.toString() == fileId,
        orElse: () => <String, dynamic>{},
      );

      if (file['type'] == 'file' &&
          file['path'] != null &&
          file['name'] != null &&
          file['size'] != null) {
        final String remoteIdentifier = file['id'].toString(); // 使用文件 ID
        final String fileName = file['name'];
        final int totalSize = file['size'];
        final String? fileFormat = file['format']?.toString().toLowerCase();

        // --- 获取并确定本地保存路径 (包含权限和冲突处理) ---
        final String? localSavePath =
            await _getTargetDownloadDirectory(fileName);

        if (localSavePath == null) {
          errorOccurred = true; // 获取路径失败，标记错误
          continue; // 跳过这个文件
        }
        // -------------------------------------------------

        final task = TransferTask(
          id: Uuid().v4(),
          filePath: localSavePath, // 使用最终确定的本地路径
          remotePath: remoteIdentifier, // 使用文件 ID
          fileName: fileName,
          totalSize: totalSize,
          isUpload: false,
          status: TransferStatus.queued,
        );
        downloadTasks.add(task);
        addedCount++;
      } else {
        print("跳过无效或非文件项: $fileId");
      }
    }

    // --- 处理结果 ---
    if (errorOccurred && addedCount == 0) {
      // 如果所有文件都因为获取路径失败而跳过
      print("所有选定文件都无法确定下载路径。");
      // SnackBar 已在 _getTargetDownloadDirectory 中显示
    } else if (downloadTasks.isNotEmpty) {
      final provider = Provider.of<TransferProvider>(context, listen: false);
      for (final task in downloadTasks) {
        await provider.addTask(task);
        TransferPage.startTransferTask(context, task);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$addedCount 个文件已添加到下载队列')),
      );
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => const TransferPage()));
    } else if (!errorOccurred) {
      // 没有错误，但也没添加任务
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未选择任何有效文件进行下载')),
      );
    }

    _exitSelectionMode(); // 退出选择模式
  }

  // --- 修改底部操作栏 ---
  Widget _buildBottomActionBar() {
    // 分享按钮是否启用 (仅当选中了 1 个文件时)
    final bool canShare = _selectedFiles.length == 1;
    final bool canDownload = _selectedFiles.isNotEmpty &&
        _selectedFiles.every((id) {
          // 确保选中的都是文件而不是文件夹
          final file = _allFiles.firstWhere((f) => f['id']?.toString() == id,
              orElse: () => <String, dynamic>{});
          return file['type'] == 'file';
        });
    return BottomAppBar(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildActionButton(
              Icons.download_outlined, // 使用 outlined icon
              '下载',
              canDownload ? _handleDownload : null // 仅当选中且都是文件时启用
              ),
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
