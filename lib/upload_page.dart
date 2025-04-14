import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart'; // 文件选择器
import 'package:http/http.dart' as http; // HTTP 请求
import 'package:path_provider/path_provider.dart'; // 获取临时路径
import 'package:shared_preferences/shared_preferences.dart';
import 'transfer_provider.dart';
import 'TransferService.dart';
import 'config.dart';
import 'FileService.dart';
import 'package:provider/provider.dart';

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

  //支持断点续传
  void _startUpload() async {
    final provider = Provider.of<TransferProvider>(context, listen: false);

    for (final file in _selectedFiles) {
      await FileService.uploadWithResume(
        filePath: file.path,
        targetPath: _uploadPath,
        provider: provider,
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
            ElevatedButton(onPressed: _uploadFiles, child: const Text('上传')),
          ],
        ),
      ),
    );
  }
}
