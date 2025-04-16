import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart'; // 文件选择器
import 'package:http/http.dart' as http; // HTTP 请求
import 'package:path_provider/path_provider.dart'; // 获取临时路径
import 'package:shared_preferences/shared_preferences.dart';
import 'transfer_provider.dart';
import 'Transfer_service.dart';
import 'config.dart';
import 'FileService.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'transfer_page.dart';
import 'package:path/path.dart' as p; // <--- 就是这一行

class UploadPage extends StatefulWidget {
  final String uploadType; // 上传类型：photo, video, document, audio, other

  final String currentPath; // 新增当前路径参数

  const UploadPage({
    Key? key,
    required this.uploadType,
    required this.currentPath, // 添加路径参数
  }) : super(key: key);

  @override
  _UploadPageState createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  String get _uploadPath => widget.currentPath; // 上传路径
  List<File> _selectedFiles = []; // 选中的文件
  List<File> _files = []; // 显示的文件列表
  String _filter = '全部'; // 文件筛选条件
  bool _isProcessing = false; // 防止重复点击

  @override
  void initState() {
    super.initState();
    _loadFiles(); // 加载文件列表
  }

  // 根据上传类型加载文件
  Future<void> _loadFiles() async {
    FilePickerResult? result;

    try {
      switch (widget.uploadType) {
        case 'photo':
          result = await FilePicker.platform.pickFiles(
            type: FileType.image,
            allowMultiple: true,
          );
          break;
        case 'video':
          result = await FilePicker.platform.pickFiles(
            type: FileType.video,
            allowMultiple: true,
          );
          break;
        case 'document':
          result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: [
              'txt',
              'doc',
              'docx',
              'pdf',
              'xls',
              'xlsx',
              'ppt',
              'pptx',
              'epub'
            ],
            allowMultiple: true,
          );
          break;
        case 'audio':
          result = await FilePicker.platform.pickFiles(
            type: FileType.audio,
            allowMultiple: true,
          );
          break;
        case 'other':
          result = await FilePicker.platform.pickFiles(
            type: FileType.any,
            allowMultiple: true,
          );
          break;
      }
    } catch (e) {
      // 捕获文件选择过程中的异常
      print('Error picking files: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件选择出错，请重试')),
      );
      return; // 发生错误直接返回，不继续处理
    }

    if (result != null) {
      final paths = result.paths;
      // 再次检查 paths 是否为 null (虽然在 result != null 条件下不太可能)
      final validPaths = paths.whereType<String>().toList(); // 过滤掉 null 路径
      if (validPaths.isNotEmpty) {
        setState(() {
          _files = validPaths.map((path) => File(path)).toList();
        });
      } else {
        // 没有选择到有效文件路径
        print('No valid file paths selected');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未选择任何有效文件')),
        );
      }
    } else {
      // result 为 null，用户可能取消了文件选择
      print('File picking cancelled or no result');
      // 可以选择是否提示用户取消操作
      // ScaffoldMessenger.of(context).showSnackBar(
      //   const SnackBar(content: Text('文件选择已取消')),
      // );
    }
  }

  // 全选文件
  void _selectAll() {
    setState(() {
      _selectedFiles = List.from(_files);
    });
  }

  Future<void> addUploadTasks() async {
    if (_selectedFiles.isEmpty || _isProcessing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择要上传的文件')),
      );
      return;
    }
    if (!mounted) return;

    setState(() => _isProcessing = true); // 开始处理

    final provider = Provider.of<TransferProvider>(context, listen: false);
    int addedCount = 0;
    List<TransferTask> tasksToStart = [];

    // 使用当前状态中的 _selectedFiles
    for (final file in _selectedFiles) {
      final filePath = file.path;
      try {
        if (!await file.exists()) {
          print("文件不存在，跳过: $filePath");
          continue;
        }
        final fileName = p.basename(filePath);
        final fileSize = await file.length();

        final task = TransferTask(
          id: Uuid().v4(),
          filePath: filePath,
          remotePath: _uploadPath, // 使用当前页面的上传路径
          fileName: fileName,
          totalSize: fileSize,
          isUpload: true,
          status: TransferStatus.queued,
        );

        // 将任务添加到 Provider (异步，内部处理持久化)
        // 注意：addTask 本身是异步的，但我们不需要在这里 await 它完成持久化
        // 我们关心的是任务被加入内存队列
        provider.addTask(task); // 注意：没用 await
        tasksToStart.add(task); // 记录下来准备启动
        addedCount++;
      } catch (e) {
        print("处理文件 $filePath 失败: $e");
        if (!mounted) return; // 异步后检查
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加文件 ${p.basename(filePath)} 到队列时出错')),
        );
      }
    }

    if (!mounted) return; // 检查 mounted

    if (addedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$addedCount 个文件已添加到上传队列')),
      );

      // --- 启动新添加的任务 ---
      // 这里我们选择立即启动，也可以只导航让 TransferPage 处理
      // final transferService =
      //     Provider.of<TransferService>(context, listen: false); // 获取 Service
      for (final task in tasksToStart) {
        // 注意：直接在循环里调用 async 方法但不用 await，会让它们并发执行
        // 这可能导致同时启动大量上传，需要小心处理并发数
        // 更好的方式可能是维护一个有限的并发队列
        print("启动上传任务: ${task.fileName}");
        // 调用 TransferPage 中的静态方法或共享的启动函数
        TransferPage.startTransferTask(context, task); // 使用静态方法启动
      }

      // --- 导航到传输页面 ---
      // 可以选择每次都跳转，或者只在添加成功后跳转一次
      // if (mounted) {
      //   Navigator.push(
      //       context, MaterialPageRoute(builder: (_) => const TransferPage()));
      // }

      // ✅ 使用 post-frame callback 安全跳转，避免 async context 警告
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TransferPage()),
          );
        }
      });
      // 上传任务已添加并开始，可以清空当前页面的选择或返回上一页
      // setState(() {
      //    _selectedFiles.clear();
      // });
      // Navigator.pop(context, true); // 返回 true 表示有上传任务添加
    } else {
      // 没有成功添加任何任务
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未能添加任何上传任务')),
      );
    }

    setState(() => _isProcessing = false); // 结束处理
  }

  // 上传文件到后端
// 上传文件
  Future<void> _uploadFiles() async {
    try {
      await FileService.uploadFiles(
        filePaths: _selectedFiles.map((f) => f.path).toList(),
        targetPath: _uploadPath,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所有文件上传成功')),
      );
      Navigator.pop(context, true); // 返回刷新信号
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
            '上传${widget.uploadType == 'photo' ? '照片' : widget.uploadType == 'video' ? '视频' : widget.uploadType == 'document' ? '文档' : widget.uploadType == 'audio' ? '音频' : '其他文件'}'),
        // actions: [
        //   TextButton(
        //     onPressed: _selectUploadPath,
        //     child: Text('上传至: $_uploadPath',
        //         style: const TextStyle(color: Color.fromARGB(255, 71, 69, 69))),
        //   ),
        // ],
      ),
      body: Column(
        children: [
          // 文件筛选
          if (widget.uploadType == 'photo')
            DropdownButton<String>(
              value: _filter,
              items: ['全部'] // 示例相册，实际需从设备获取
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (value) {
                setState(() => _filter = value!);
                // TODO: 根据筛选条件重新加载文件
              },
            ),
          if (widget.uploadType == 'document')
            DropdownButton<String>(
              value: _filter,
              items: ['全部', 'Txt', 'Word', 'PDF', 'Excel', 'PPT', 'EPUB']
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (value) {
                setState(() => _filter = value!);
                // TODO: 根据筛选条件重新加载文件
              },
            ),
          // 文件列表
          Expanded(
            child: ListView.builder(
              itemCount: _files.length,
              itemBuilder: (context, index) {
                final file = _files[index];
                return ListTile(
                  title: Text(file.path.split('/').last),
                  subtitle: Text(
                      '时间: ${DateTime.now().toString().substring(0, 19)}, 大小: ${file.lengthSync()} bytes'),
                  trailing: Checkbox(
                    value: _selectedFiles.contains(file),
                    onChanged: (bool? value) {
                      setState(() {
                        if (value!) {
                          _selectedFiles.add(file);
                        } else {
                          _selectedFiles.remove(file);
                        }
                      });
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(onPressed: _selectAll, child: const Text('全选')),
            //ElevatedButton(onPressed: _uploadFiles, child: const Text('上传')),
            Padding(
              // 加点边距
              padding: const EdgeInsets.only(left: 16.0),
              child: Text("已选 ${_selectedFiles.length} 项"), // 显示已选数量
            ),
            ElevatedButton.icon(
              icon: Icon(Icons.cloud_upload_outlined),
              // --- 调用新的上传处理函数 ---
              onPressed: (_selectedFiles.isNotEmpty && !_isProcessing)
                  ? addUploadTasks // 点击时调用新函数
                  : null, // 禁用按钮如果没有选择文件或正在处理
              label: Text(_isProcessing ? '处理中...' : '开始上传'),
            ),
          ],
        ),
      ),
    );
  }
}
