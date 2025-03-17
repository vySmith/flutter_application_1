import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart'; // 文件选择器
import 'package:http/http.dart' as http; // HTTP 请求
import 'package:path_provider/path_provider.dart'; // 获取临时路径
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

class UploadPage extends StatefulWidget {
  final String uploadType; // 上传类型：photo, video, document, audio, other
  const UploadPage({Key? key, required this.uploadType}) : super(key: key);

  @override
  _UploadPageState createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  String _uploadPath = '/'; // 默认上传路径
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
      if (paths != null) {
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
        // result.paths 为 null 的情况 (理论上不应该发生，但为了严谨处理)
        print('File paths are null');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('获取文件路径失败')),
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

  // 选择上传路径
  void _selectUploadPath() {
    // TODO: 从后端获取文件夹列表并显示选择对话框
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择上传路径'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('/ (根目录)'),
              onTap: () {
                setState(() => _uploadPath = '/');
                Navigator.pop(context);
              },
            ),
            // 示例文件夹，实际应从后端获取
            ListTile(
              title: const Text('/folder1'),
              onTap: () {
                setState(() => _uploadPath = '/folder1/');
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  // 全选文件
  void _selectAll() {
    setState(() {
      _selectedFiles = List.from(_files);
    });
  }

  // 上传文件到后端
  Future<void> _uploadFiles() async {
    const String apiUrl = '${Config.baseUrl}/upload'; // 后端地址
    for (var file in _selectedFiles) {
      var request = http.MultipartRequest('POST', Uri.parse(apiUrl));

      final prefs =
          await SharedPreferences.getInstance(); // 获取 SharedPreferences 实例
      final userId =
          prefs.getString('userId'); // 从 SharedPreferences 中获取 userId

      request.fields['user_id'] = userId.toString(); // 替换为实际用户ID
      request.fields['path'] = _uploadPath;
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      var response = await request.send();
      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传成功: ${file.path.split('/').last}')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传失败: ${file.path.split('/').last}')),
        );
      }
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
        actions: [
          TextButton(
            onPressed: _selectUploadPath,
            child: Text('上传至: $_uploadPath',
                style: const TextStyle(color: Color.fromARGB(255, 71, 69, 69))),
          ),
        ],
      ),
      body: Column(
        children: [
          // 文件筛选
          if (widget.uploadType == 'photo')
            DropdownButton<String>(
              value: _filter,
              items: ['全部', '相册一', '相册二'] // 示例相册，实际需从设备获取
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
