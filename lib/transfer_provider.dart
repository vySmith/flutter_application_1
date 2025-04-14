// transfer_provider.dart
import 'package:flutter/material.dart';

enum TransferStatus { queued, uploading, completed, failed, downloading }

class TransferTask {
  final String id;
  final String filePath;
  final String remotePath;
  double progress;
  TransferStatus status;
  int speed; // KB/s

  TransferTask({
    required this.id,
    required this.filePath,
    required this.remotePath,
    this.progress = 0,
    this.status = TransferStatus.queued,
    this.speed = 0,
  });
}

class TransferProvider with ChangeNotifier {
  final List<TransferTask> _uploads = [];
  final List<TransferTask> _downloads = [];

  List<TransferTask> get uploads => _uploads;
  List<TransferTask> get downloads => _downloads;

  void addUpload(TransferTask task) {
    _uploads.add(task);
    notifyListeners();
  }

  void updateProgress(String id, double progress) {
    final task = _uploads.firstWhere((t) => t.id == id);
    task.progress = progress;
    task.status =
        progress < 1 ? TransferStatus.uploading : TransferStatus.completed;
    notifyListeners();
  }

  void markFailed(String id) {
    final task = _uploads.firstWhere((t) => t.id == id);
    task.status = TransferStatus.failed;
    notifyListeners();
  }
}
