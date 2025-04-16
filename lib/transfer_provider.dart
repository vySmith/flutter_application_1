import 'package:flutter/foundation.dart'; // Use foundation instead of material for ChangeNotifier
import 'database_helper.dart';

// 保持 TransferStatus 枚举不变
enum TransferStatus {
  queued,
  processing,
  completed,
  failed,
  paused,
  canceled
} // 添加 paused 和 canceled

class TransferTask {
  final String id; // 唯一任务 ID (例如 UUID)
  final String filePath; // 本地文件路径 (上传源 / 下载目标)
  final String remotePath; // 远程逻辑路径 (上传目标 / 下载源标识符，可能是 file_id 或 path)
  final String fileName; // 文件名 (方便显示)
  final int totalSize; // 文件总大小 (字节)
  final bool isUpload; // 标记是上传还是下载

  double progress; // 进度 0.0 - 1.0
  TransferStatus status;
  String? errorMessage; // 存储错误信息
  // int speed; // KB/s (速度计算可以放到 Service 或 UI 层临时计算)

  TransferTask({
    required this.id,
    required this.filePath,
    required this.remotePath,
    required this.fileName,
    required this.totalSize,
    required this.isUpload,
    this.progress = 0,
    this.status = TransferStatus.queued,
    this.errorMessage,
    // this.speed = 0,
  });

  // 添加一个 toMap 方法方便持久化
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'filePath': filePath,
      'remotePath': remotePath,
      'fileName': fileName,
      'totalSize': totalSize,
      'isUpload': isUpload,
      'progress': progress,
      'status': status.index, // 存储枚举的索引
      'errorMessage': errorMessage,
    };
  }

  // 添加一个 fromMap 工厂构造函数方便从持久化数据创建
  factory TransferTask.fromMap(Map<String, dynamic> map) {
    return TransferTask(
      id: map['id'],
      filePath: map['filePath'],
      remotePath: map['remotePath'],
      fileName: map['fileName'],
      totalSize: map['totalSize'],
      isUpload: map['isUpload'],
      progress: map['progress'],
      // 从索引恢复枚举状态，注意处理无效索引
      status: TransferStatus.values.length > map['status']
          ? TransferStatus.values[map['status']]
          : TransferStatus.failed, // 默认给个失败状态
      errorMessage: map['errorMessage'],
    );
  }
}

class TransferProvider with ChangeNotifier {
  final List<TransferTask> _tasks = []; // 合并上传和下载到一个列表
  bool _isInitialized = false; // 标记是否已从数据库加载
  List<TransferTask> get tasks => _tasks;
  List<TransferTask> get uploads => _tasks.where((t) => t.isUpload).toList();
  List<TransferTask> get downloads => _tasks.where((t) => !t.isUpload).toList();
  bool get isInitialized => _isInitialized; // 暴露初始化状态

  TransferProvider() {
    _loadTasksFromDb(); // 构造时加载
  }

  // 从数据库加载任务
  Future<void> _loadTasksFromDb() async {
    try {
      final dbTasks = await DatabaseHelper.instance.getAllTasks();
      _tasks.clear();
      _tasks.addAll(dbTasks);
      _isInitialized = true;
      print("从数据库加载了 ${_tasks.length} 个任务");
      // 对于加载后状态为 processing 的任务，可能需要重置为 queued 或 paused
      for (var task in _tasks) {
        if (task.status == TransferStatus.processing) {
          task.status = TransferStatus.paused; // 或 queued，表示需要重新开始/恢复
        }
      }
      notifyListeners();
    } catch (e) {
      print("从数据库加载任务失败: $e");
      _isInitialized = true; // 即使失败也标记为初始化完成，避免无限加载
      notifyListeners(); // 通知 UI 可能需要显示错误
    }
  }

// 添加新任务
  Future<void> addTask(TransferTask task) async {
    if (!_tasks.any((t) => t.id == task.id)) {
      _tasks.add(task);
      notifyListeners();
      try {
        await DatabaseHelper.instance.upsertTask(task); // 持久化
        print("任务 ${task.id} 已添加到数据库");
      } catch (e) {
        print("持久化新任务 ${task.id} 失败: $e");
        // 可以考虑是否移除内存中的任务或标记为错误
      }
    }
  }

  // 添加或替换任务 (例如从持久化加载时)
  void addOrUpdateTask(TransferTask task) {
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index != -1) {
      _tasks[index] = task; // 更新现有任务
    } else {
      _tasks.add(task); // 添加新任务
    }
    // 通常在批量加载后统一 notifyListeners
  }

  // 更新任务进度
  Future<void> updateProgress(String id, double progress) async {
    try {
      final task = _tasks.firstWhere((t) => t.id == id);
      TransferStatus newStatus = task.status;
      if (task.status != TransferStatus.completed &&
          task.status != TransferStatus.failed &&
          task.status != TransferStatus.canceled) {
        task.progress = progress;
        if (task.status == TransferStatus.queued ||
            task.status == TransferStatus.paused) {
          task.status = TransferStatus.processing;
          newStatus = TransferStatus.processing;
        }
        task.errorMessage = null;
        notifyListeners();
        // 持久化进度和状态
        await DatabaseHelper.instance
            .updateTaskProgressStatus(id, progress, newStatus);
      }
    } catch (e) {
      print("更新任务进度/状态失败 (ID: $id): $e");
    }
  }

  // 更新任务状态
  Future<void> updateStatus(String id, TransferStatus status,
      {String? errorMessage}) async {
    try {
      final task = _tasks.firstWhere((t) => t.id == id);
      task.status = status;
      task.errorMessage = errorMessage;
      if (status == TransferStatus.completed) {
        task.progress = 1.0;
      }
      notifyListeners();
      // 持久化状态和错误信息
      await DatabaseHelper.instance
          .updateTaskStatusError(id, status, errorMessage);
    } catch (e) {
      print("更新任务状态失败 (ID: $id): $e");
    }
  }

  // 移除任务
  Future<void> removeTask(String id) async {
    // 先找到要移除的任务的索引
    final indexToRemove = _tasks.indexWhere((t) => t.id == id);

    if (indexToRemove != -1) {
      // 如果找到了匹配的任务
      _tasks.removeAt(indexToRemove); // 使用索引移除
      notifyListeners(); // 通知 UI 更新
      try {
        await DatabaseHelper.instance.deleteTask(id); // 从数据库删除
        print("任务 $id 已从数据库移除");
      } catch (e) {
        print("从数据库移除任务 $id 失败: $e");
        // 可以考虑是否需要错误处理或重试
      }
    } else {
      print("尝试移除任务 $id，但在内存列表中未找到。");
    }
  }

  // 清除已完成的任务
  Future<void> clearCompleted() async {
    _tasks.removeWhere((t) => t.status == TransferStatus.completed);
    notifyListeners();
    try {
      final deletedCount = await DatabaseHelper.instance.deleteCompletedTasks();
      print("从数据库清除了 $deletedCount 个已完成的任务");
    } catch (e) {
      print("从数据库清除已完成任务失败: $e");
    }
  }

  // 获取特定任务
  TransferTask? getTask(String id) {
    try {
      return _tasks.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  // TODO: 添加从持久化存储加载任务的方法 (loadTasks)
  // TODO: 添加持久化任务的方法 (saveTasks / saveTask)
}
