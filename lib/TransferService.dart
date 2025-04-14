// transfer_service.dart
import 'dart:io';
import 'package:http/http.dart' as http;
import "config.dart";
import 'transfer_provider.dart';
import 'FileService.dart';
import 'dart:typed_data'; // 修复 Uint8List 类型错误

class TransferService {
  final Map<String, http.Client> _activeClients = {};

  Future<void> uploadFile({
    required TransferTask task,
    required Function(double) onProgress,
  }) async {
    final file = File(task.filePath);
    const chunkSize = 5 * 1024 * 1024; // 5MB 分块
    final totalSize = await file.length();
    int uploaded = 0;

    try {
      for (int start = 0; start < totalSize; start += chunkSize) {
        final chunk = await file
            .readAsBytes()
            .then((bytes) => bytes.sublist(start, start + chunkSize));

        final request = http.MultipartRequest(
          'POST',
          Uri.parse('${Config.baseUrl}/upload_chunk'),
        )
          ..fields.addAll({
            'user_id': await FileService.getUserId() ?? '',
            'task_id': task.id,
            'chunk_index': (start ~/ chunkSize).toString(),
          })
          ..files.add(http.MultipartFile.fromBytes('chunk', chunk));

        final response = await request.send();
        if (response.statusCode != 200) throw Exception('分片上传失败');

        uploaded += chunk.length;
        onProgress(uploaded / totalSize);
      }
    } catch (e) {
      throw Exception('上传失败: $e');
    }
  }

  void cancelTransfer(String taskId) {
    _activeClients[taskId]?.close();
    _activeClients.remove(taskId);
  }

  // 文件下载（支持断点续传）
  Future<void> downloadFile({
    required TransferTask task,
    required Function(double) onProgress,
  }) async {
    // final file = File(task.filePath);
    // final response = await http.get(
    //   Uri.parse('${Config.baseUrl}/download?file_id=${task.id}'),
    //   headers: {'Range': 'bytes=0-'}, // 初始请求整个文件
    // );

    // if (response.statusCode != 200 && response.statusCode != 206) {
    //   throw Exception('下载失败: ${response.statusCode}');
    // }

    // final totalSize = int.parse(
    //   response.headers['content-length'] ?? '0',
    // );
    // int received = 0;

    // final raf = file.openSync(mode: FileMode.write);
    // final sink = raf.openWrite();

    // await response.stream.listen(
    //   (List<int> chunk) {
    //     received += chunk.length;
    //     sink.add(chunk);
    //     onProgress(received / totalSize);
    //   },
    //   onDone: () => sink.close(),
    // ).asFuture();

    // 正确写入方式
    // await response.stream.asBroadcastStream().forEach((chunk) {
    //   raf.writeFromSync(chunk);
    //   onProgress(chunk.length / response.contentLength!);
    // });

    // await raf.close();
    final file = File(task.filePath);
    final existingLength = await file.exists() ? file.lengthSync() : 0;

    final client = http.Client();
    final request = http.Request(
      'GET',
      Uri.parse('${Config.baseUrl}/download?file_id=${task.id}'),
    );

    // 设置 Range 头部实现断点续传
    request.headers['Range'] = 'bytes=$existingLength-';

    final response = await client.send(request); // 返回 StreamedResponse

    if (response.statusCode != 200 && response.statusCode != 206) {
      throw Exception('下载失败: ${response.statusCode}');
    }

    final totalLength = response.contentLength != null
        ? response.contentLength! + existingLength
        : existingLength;

    int received = existingLength;

    final raf = file.openSync(mode: FileMode.append); // 追加写入

    await response.stream.forEach((chunk) {
      raf.writeFromSync(chunk);
      received += chunk.length;
      onProgress(received / totalLength);
    });

    await raf.close();
    client.close();
  }

  // 分块下载实现
  Future<Uint8List> _downloadChunk({
    required String taskId,
    required String url,
    required int start,
    required int end,
  }) async {
    final client = http.Client();
    _activeClients[taskId] = client;

    try {
      final response = await client.get(
        Uri.parse(url),
        headers: {'Range': 'bytes=$start-$end'},
      );

      if (response.statusCode != 206) {
        throw Exception('分块下载失败');
      }

      return response.bodyBytes;
    } finally {
      client.close();
      _activeClients.remove(taskId);
    }
  }
}
