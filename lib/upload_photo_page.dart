// upload_photo_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http; // 导入 http 包
import 'package:shared_preferences/shared_preferences.dart'; // 导入 shared_preferences
import 'dart:convert'; // 导入 json
import 'config.dart';

class UploadPhotoPage extends StatefulWidget {
  final String path; // 接收 path 参数

  const UploadPhotoPage({Key? key, this.path = '/'})
      : super(key: key); // path 默认为根目录

  @override
  _UploadPhotoPageState createState() => _UploadPhotoPageState();
}

class _UploadPhotoPageState extends State<UploadPhotoPage> {
  List<XFile> _imageList = [];
  List<int> _selectedIndices = [];
  bool _selectAll = false;
  bool _isUploading = false; // 添加上传状态

  @override
  void initState() {
    super.initState();
    _getImages();
  }

  Future<void> _getImages() async {
    final ImagePicker _picker = ImagePicker();
    final List<XFile>? images = await _picker.pickMultiImage();

    if (images != null) {
      setState(() {
        _imageList = images;
        _selectedIndices = [];
        _selectAll = false;
      });
    }
  }

  void _toggleSelection(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
      _selectAll = _selectedIndices.length == _imageList.length;
    });
  }

  void _selectAllPhotos() {
    setState(() {
      _selectAll = !_selectAll;
      if (_selectAll) {
        _selectedIndices = List<int>.generate(_imageList.length, (i) => i);
      } else {
        _selectedIndices.clear();
      }
    });
  }

  Future<void> _uploadSelectedPhotos() async {
    setState(() {
      _isUploading = true; // 开始上传时显示加载状态
    });

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');
    print('User ID: $userId'); // 打印 userId

    if (userId == null) {
      setState(() {
        _isUploading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('用户未登录，请重新登录')),
      );
      return;
    }
    print('Image List Length: ${_imageList.length}'); // 打印 _imageList 长度
    print(
        'Selected Indices Length: ${_selectedIndices.length}'); // 打印 _selectedIndices 长度
    final uploadUrl =
        Uri.parse('${Config.baseUrl}}/upload_photo'); //  上传照片的路由 (你需要Flask后端实现)

    try {
      var request = http.MultipartRequest('POST', uploadUrl);
      request.fields['user_id'] = userId;
      request.fields['path'] = widget.path; // 发送当前路径

      for (int index in _selectedIndices) {
        final XFile imageFile = _imageList[index];
        request.files.add(await http.MultipartFile.fromPath(
          'photos', // 后端接收文件的字段名，例如 'photos'
          imageFile.path,
          filename: imageFile.name,
        ));
      }

      final response = await request.send();
      final respStr = await response.stream.bytesToString(); // 获取响应体
      final respJson = jsonDecode(respStr); // 解析 JSON 响应

      if (response.statusCode == 201) {
        // 上传成功
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(respJson['message'] ?? '照片上传成功')), // 显示后端返回的消息
        );
        Navigator.pop(context, true); // 返回 file_page 并传递 true 表示上传成功，可以刷新列表
      } else {
        // 上传失败
        print('照片上传失败: ${response.statusCode}, body: $respStr'); // 打印详细错误信息
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(respJson['message'] ?? '照片上传失败')), // 显示后端返回的错误消息
        );
      }
    } catch (e) {
      print('照片上传出错: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('照片上传出错')),
      );
    } finally {
      setState(() {
        _isUploading = false; // 上传完成，停止加载状态
      });
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
        title: const Text('上传照片'),
        actions: [
          TextButton(
            onPressed: _selectAllPhotos,
            child: Text(_selectAll ? '取消全选' : '全选',
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: _isUploading // 根据上传状态显示不同的 UI
          ? const Center(child: CircularProgressIndicator()) // 上传中显示加载指示器
          : GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4.0,
                mainAxisSpacing: 4.0,
              ),
              itemCount: _imageList.length,
              itemBuilder: (context, index) {
                return Stack(
                  children: [
                    GestureDetector(
                      onTap: () => _toggleSelection(index),
                      child: Image.file(
                        File(_imageList[index].path),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                    Positioned(
                      bottom: 5,
                      right: 5,
                      child: IconButton(
                        icon: Icon(
                          _selectedIndices.contains(index)
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: _selectedIndices.contains(index)
                              ? Colors.blue
                              : Colors.grey,
                        ),
                        onPressed: () => _toggleSelection(index),
                      ),
                    ),
                  ],
                );
              },
            ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          onPressed: _selectedIndices.isNotEmpty
              ? _uploadSelectedPhotos
              : null, // 只有选中照片才允许点击上传
          child: const Text('上传'),
        ),
      ),
    );
  }
}
