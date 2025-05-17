// transfer_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math'; // For min
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p; // For basename
import 'config.dart';
import 'transfer_provider.dart'; // Assuming TransferTask is here
import 'FileService.dart'; // For getUserId
import 'dart:typed_data';

class TransferService {
  // 使用 Map 来跟踪取消请求的 Completer 或 StreamSubscription
  final Map<String, Completer<void>> _uploadCancelCompleters = {};
  final Map<String, StreamSubscription<dynamic>?> _downloadSubscriptions = {};

  // --- 上传文件 (支持断点续传) ---
  Future<void> uploadFile({
    required TransferTask task,
    required Function(double) onProgress, // 回调进度 (0.0 - 1.0)
    required Function(String filePath) onSuccess, // 成功回调，传递最终文件路径
    required Function(String error) onError, // 失败回调
  }) async {
    final completer = Completer<void>();
    _uploadCancelCompleters[task.id] = completer; // 注册取消器

    final file = File(task.filePath);
    if (!await file.exists()) {
      onError("本地文件不存在: ${task.filePath}");
      _uploadCancelCompleters.remove(task.id);
      return;
    }

    final totalSize = await file.length();
    const chunkSize = 1 * 1024 * 1024; // 1MB 分块 (根据网络调整)
    final totalChunks = (totalSize / chunkSize).ceil();
    final fileName = p.basename(task.filePath);
    final userId = await FileService.getUserId();
    if (userId == null) {
      onError("用户未登录");
      _uploadCancelCompleters.remove(task.id);
      return;
    }

    print(
        "开始上传任务: ${task.id}, 文件: $fileName, 大小: $totalSize, 分块数: $totalChunks");

    Set<int> uploadedIndices = {}; // 用于存储已上传的分块索引
    int uploadedBytes = 0;

    try {
      // 1. 检查已上传的分块 (调用新后端 API)
      try {
        print("检查已上传分块 for task: ${task.id}");
        final checkResponse = await http.get(
          Uri.parse('${Config.baseUrl}/check_uploaded_chunks')
              .replace(queryParameters: {
            'user_id': userId,
            'task_id': task.id,
          }),
        );
        if (checkResponse.statusCode == 200) {
          final decoded = jsonDecode(checkResponse.body);
          if (decoded['status'] == 'success' &&
              decoded['uploaded_indices'] is List) {
            uploadedIndices = Set<int>.from(decoded['uploaded_indices']);
            uploadedBytes = uploadedIndices.length * chunkSize; // 估算已上传大小
            print("发现 ${uploadedIndices.length} 个已上传分块: $uploadedIndices");
            // 初始进度
            if (totalSize > 0)
              onProgress(min(uploadedBytes / totalSize, 1.0));
            else
              onProgress(1.0); // 空文件
          }
        } else {
          print("检查分块失败 (HTTP ${checkResponse.statusCode}), 将从头上传");
          uploadedIndices.clear();
          uploadedBytes = 0;
        }
      } catch (e) {
        print("检查分块时出错: $e, 将从头上传");
        uploadedIndices.clear();
        uploadedBytes = 0;
      }

      // 2. 逐个上传未上传的分块
      final stream = file.openRead();
      int currentChunkIndex = 0;
      int currentChunkStartByte = 0;
      List<int> chunkBuffer = [];

      await for (final data in stream) {
        // 检查是否已取消
        if (completer.isCompleted) {
          print("上传任务 ${task.id} 已取消 (during stream processing)");
          throw Exception("Upload canceled");
        }

        chunkBuffer.addAll(data);

        // 当 buffer 大小足够一个分块时处理
        while (chunkBuffer.length >= chunkSize ||
            (currentChunkStartByte + chunkBuffer.length == totalSize &&
                chunkBuffer.isNotEmpty)) {
          final endByte = min(chunkSize, chunkBuffer.length);
          final chunkToSend = chunkBuffer.sublist(0, endByte);
          final thisChunkIndex = currentChunkIndex; // 捕获当前索引
          final thisChunkSize = chunkToSend.length;

          // 移除已处理的部分
          chunkBuffer = chunkBuffer.sublist(endByte);

          // 如果此分块未上传，则上传
          if (!uploadedIndices.contains(thisChunkIndex)) {
            print("上传分块: index=$thisChunkIndex, size=${thisChunkSize}");
            try {
              final request = http.MultipartRequest(
                'POST',
                Uri.parse('${Config.baseUrl}/upload_chunk'),
              )
                ..fields['user_id'] = userId
                ..fields['task_id'] = task.id
                ..fields['chunk_index'] = thisChunkIndex.toString()
                ..files.add(http.MultipartFile.fromBytes('chunk', chunkToSend,
                    filename: "$fileName.chunk$thisChunkIndex")); // 添加文件名

              // 检查是否已取消
              if (completer.isCompleted) throw Exception("Upload canceled");

              final response = await request
                  .send(); //.timeout(Duration(seconds: 60)); // 添加超时

              // 读取响应体以确保连接关闭
              final responseBody = await response.stream.bytesToString();

              if (response.statusCode != 200) {
                print(
                    "分块上传失败: index=$thisChunkIndex, status=${response.statusCode}, body=$responseBody");
                throw Exception(
                    '分块 $thisChunkIndex 上传失败 (Status: ${response.statusCode})');
              }

              // 上传成功，更新状态
              uploadedIndices.add(thisChunkIndex); // 标记为已上传
              uploadedBytes += thisChunkSize;
              if (totalSize > 0)
                onProgress(min(uploadedBytes / totalSize, 1.0));
              print(
                  "分块 $thisChunkIndex 上传成功, 总进度: ${(uploadedBytes / totalSize * 100).toStringAsFixed(1)}%");
            } catch (e) {
              print("上传分块 $thisChunkIndex 时出错: $e");
              // 可以实现重试逻辑，这里先直接抛出错误
              throw e;
            }
          } else {
            print("跳过已上传的分块: index=$thisChunkIndex");
            // 虽然跳过了上传，但仍需更新进度（如果之前没算对）
            // uploadedBytes 已经包含了这部分，或者需要在检查后精确计算
          }

          // 移动到下一个分块
          currentChunkIndex++;
          currentChunkStartByte += thisChunkSize; // 使用实际发送的大小
        }
      }

      // 3. 所有分块处理完毕 (包括已上传和新上传的)，请求合并
      if (completer.isCompleted) {
        print("任务 ${task.id} 在请求合并前被取消");
        throw Exception("Upload canceled");
      }

      // 检查是否所有块都已（标记为）上传
      if (uploadedIndices.length == totalChunks) {
        print("所有分块已上传/处理完毕，请求合并...");
        final mergeResponse =
            await http.post(Uri.parse('${Config.baseUrl}/merge_chunks'), body: {
          'user_id': userId,
          'task_id': task.id,
          'total_chunks': totalChunks.toString(),
          'file_name': fileName, // 传递原始文件名
          'target_path': task.remotePath, // 传递目标逻辑路径
          'total_size': totalSize.toString(), // 传递总大小用于验证
        });

        if (mergeResponse.statusCode == 200 ||
            mergeResponse.statusCode == 201) {
          final decoded = jsonDecode(mergeResponse.body);
          if (decoded['status'] == 'success') {
            print("文件合并成功: ${decoded['file_path']}");
            onProgress(1.0); // 确保进度为 100%
            onSuccess(decoded['file_path']); // 调用成功回调
          } else {
            print("文件合并失败: ${decoded['message']}");
            throw Exception(decoded['message'] ?? '文件合并失败');
          }
        } else {
          print(
              "合并请求失败 (HTTP ${mergeResponse.statusCode}): ${mergeResponse.body}");
          throw Exception('合并请求失败 (HTTP ${mergeResponse.statusCode})');
        }
      } else {
        // 这通常不应该发生，除非分块读取或上传逻辑有误
        print("错误: 并非所有分块都已上传 (${uploadedIndices.length} / $totalChunks).");
        throw Exception("并非所有分块都已完成上传");
      }
    } catch (e) {
      // 捕获所有异常
      if (!completer.isCompleted) {
        // 只有未取消的才调用 onError
        print("上传任务 ${task.id} 失败: $e");
        onError(e.toString());
      } else {
        print("上传任务 ${task.id} 已被取消，不再调用 onError");
      }
    } finally {
      // 移除取消器
      _uploadCancelCompleters.remove(task.id);
      print("上传任务 ${task.id} 结束.");
    }
  }

  // --- 下载文件 (增强取消和错误处理) ---
  Future<void> downloadFile({
    required TransferTask task,
    required Function(double) onProgress,
    required Function() onSuccess, // 成功回调
    required Function(String error) onError, // 失败回调
  }) async {
    final file = File(task.filePath);
    RandomAccessFile? raf;
    http.Client? client; // 允许取消 client
    StreamSubscription<List<int>>? subscription; // 允许取消订阅

    try {
      final existingLength = await file.exists() ? await file.length() : 0;
      client = http.Client();
      final userId = await FileService.getUserId();
      // --- 修改 URL，同时发送 user_id 和 file_id ---
      final uri =
          Uri.parse('${Config.baseUrl}/download').replace(queryParameters: {
        'user_id': userId, // <--- 添加 user_id
        'file_id': task.remotePath // <--- 假设 task.remotePath 存储的是文件 ID
        // 如果 task.id 是文件 ID，用 task.id: task.id
      });
      // ---------------------------------------------

      final request = http.Request('GET', uri); // 使用构建好的 URI

      request.headers['Range'] = 'bytes=$existingLength-';
      print("请求下载: URI=$uri, Range=bytes=$existingLength-"); // 更新打印信息

      // 注册 Client 以便取消
      _downloadSubscriptions[task.id] = null; // Placeholder

      final response = await client.send(request);

      // 在收到响应头后立即检查状态码
      if (response.statusCode != 200 && response.statusCode != 206) {
        // 206 Partial Content
        client.close(); // 关闭客户端
        throw Exception('下载失败: 服务器返回 ${response.statusCode}');
      }
      if (response.statusCode == 200 && existingLength > 0) {
        print("服务器返回 200 但本地文件已存在，可能需要重新下载或清空本地文件");
        // 决定是报错还是清空重下，这里先报错
        client.close();
        throw Exception('下载错误：服务器不支持范围请求或文件已更改');
        // 或者:
        // await file.delete();
        // existingLength = 0;
        // // 重新请求？逻辑会复杂
      }

      // content-range 头部可以用来验证服务器返回的范围是否正确 (可选)
      // print("Response headers: ${response.headers}");

      // 如果是 206， contentLength 是剩余部分的大小；如果是 200，是整个文件大小
      final remainingLength = response.contentLength;
      final totalLength = remainingLength != null
          ? existingLength + remainingLength
          : existingLength; // 如果没有 content-length，只能估算

      print(
          "文件总大小 (估算): $totalLength, 已下载: $existingLength, 剩余: $remainingLength");

      if (totalLength == existingLength && totalLength > 0) {
        print("文件已完整下载。");
        onProgress(1.0);
        onSuccess();
        client.close();
        _downloadSubscriptions.remove(task.id);
        return;
      }
      if (remainingLength == 0 && response.statusCode == 206) {
        print("服务器返回空内容范围，可能已下载完成。");
        onProgress(1.0);
        onSuccess();
        client.close();
        _downloadSubscriptions.remove(task.id);
        return;
      }

      raf = await file.open(mode: FileMode.append); // 以追加模式打开
      int received = existingLength;

      final completer = Completer<void>(); // 用于等待 stream 完成或取消

      subscription = response.stream.listen(
        (chunk) {
          try {
            raf?.writeFromSync(chunk); // 同步写入，对于大量小 chunk 可能阻塞 UI，但简单
            received += chunk.length;
            if (totalLength > 0)
              onProgress(min(received / totalLength, 1.0));
            else
              onProgress(0.0); // 如果 totalLength 未知
          } catch (e) {
            print("写入文件块时出错: $e");
            // 关闭资源并尝试完成 completer (带错误)
            raf?.closeSync();
            client?.close();
            if (!completer.isCompleted) completer.completeError(e);
            subscription?.cancel(); // 取消订阅
            _downloadSubscriptions.remove(task.id);
          }
        },
        onDone: () {
          print("下载流处理完成 (onDone)");
          raf?.closeSync(); // 关闭文件
          client?.close(); // 关闭客户端
          if (!completer.isCompleted) completer.complete(); // 正常完成
          _downloadSubscriptions.remove(task.id);
          // 验证文件大小 (如果 totalLength 可靠)
          if (totalLength > 0 && received != totalLength) {
            print("警告：最终接收大小 ($received) 与预期总大小 ($totalLength) 不符");
            onError("下载文件大小不匹配");
          } else {
            onProgress(1.0); // 确保最后是100%
            onSuccess(); // 调用成功回调
          }
        },
        onError: (error) {
          print("下载流出错 (onError): $error");
          raf?.closeSync();
          client?.close();
          if (!completer.isCompleted) completer.completeError(error);
          _downloadSubscriptions.remove(task.id);
          onError(error.toString()); // 调用失败回调
        },
        cancelOnError: true, // 出错时自动取消订阅
      );

      // 将 subscription 存储起来以便外部取消
      _downloadSubscriptions[task.id] = subscription;

      await completer.future; // 等待下载完成或被取消/出错
    } catch (e) {
      print("下载任务 ${task.id} 失败: $e");
      raf?.closeSync(); // 确保文件关闭
      client?.close(); // 确保客户端关闭
      _downloadSubscriptions.remove(task.id); // 移除记录
      onError(e.toString()); // 调用失败回调
    }
  }

  // --- 取消传输 ---
  void cancelTransfer(String taskId) {
    print("请求取消任务: $taskId");
    // 取消上传
    if (_uploadCancelCompleters.containsKey(taskId)) {
      if (!_uploadCancelCompleters[taskId]!.isCompleted) {
        _uploadCancelCompleters[taskId]!.completeError(
            Exception("Upload canceled by user")); // 通过 completeError 触发取消
        print("标记上传任务 $taskId 为取消状态");
      }
      _uploadCancelCompleters.remove(taskId); // 移除记录
    }

    // 取消下载
    if (_downloadSubscriptions.containsKey(taskId)) {
      _downloadSubscriptions[taskId]?.cancel(); // 取消流订阅
      print("取消下载流订阅 for $taskId");
      // 注意：取消订阅可能不会立即停止网络请求，但会停止处理数据
      // 对于下载，没有直接的方法像关闭 client 一样强制停止，除非保存 client 引用并关闭
      // 但这里的 client 是在 downloadFile 内部创建的，无法直接访问
      _downloadSubscriptions.remove(taskId); // 移除记录
    }
  }
}
