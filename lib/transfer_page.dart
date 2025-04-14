// transfer_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'transfer_provider.dart';
import 'TransferService.dart';

class TransferPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('传输列表'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '上传'),
              Tab(text: '下载'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildUploadList(),
            _buildDownloadList(),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadList() {
    return Consumer<TransferProvider>(
      builder: (context, provider, _) => ListView.builder(
        itemCount: provider.uploads.length,
        itemBuilder: (ctx, index) => _UploadItem(task: provider.uploads[index]),
      ),
    );
  }

  Widget _buildDownloadList() {
    return Consumer<TransferProvider>(
      builder: (context, provider, _) => ListView.builder(
        itemCount: provider.downloads.length,
        itemBuilder: (ctx, index) =>
            _DownloadItem(task: provider.downloads[index]),
      ),
    );
  }
}

// transfer_page.dart

class _UploadItem extends StatelessWidget {
  final TransferTask task;

  const _UploadItem({required this.task});

  void _retryUpload(BuildContext context) {
    final provider = Provider.of<TransferProvider>(context, listen: false);
    final service = Provider.of<TransferService>(context, listen: false);

    task.status = TransferStatus.queued;
    provider.notifyListeners();

    service
        .uploadFile(
      task: task,
      onProgress: (progress) {
        task.progress = progress;
        provider.notifyListeners();
      },
    )
        .catchError((e) {
      task.status = TransferStatus.failed;
      provider.notifyListeners();
    });
  }

  void _cancelUpload(BuildContext context) {
    final provider = Provider.of<TransferProvider>(context, listen: false);
    final service = Provider.of<TransferService>(context, listen: false);

    service.cancelTransfer(task.id);
    provider.uploads.removeWhere((t) => t.id == task.id);
    provider.notifyListeners();
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.upload),
      title: LinearProgressIndicator(value: task.progress),
      subtitle: _buildSubtitle(),
      trailing: _buildActionButtons(context),
    );
  }

  Widget _buildSubtitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('文件: ${task.filePath.split('/').last}'),
        if (task.status == TransferStatus.uploading)
          Text('速度: ${task.speed} KB/s'),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    switch (task.status) {
      case TransferStatus.failed:
        return IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => _retryUpload(context),
        );
      default:
        return IconButton(
          icon: const Icon(Icons.cancel),
          onPressed: () => _cancelUpload(context),
        );
    }
  }
}

// transfer_page.dart
class _DownloadItem extends StatelessWidget {
  final TransferTask task;

  const _DownloadItem({required this.task});
  void _retryDownload(BuildContext context) {
    final provider = Provider.of<TransferProvider>(context, listen: false);
    final service = Provider.of<TransferService>(context, listen: false);

    task.status = TransferStatus.queued;
    provider.notifyListeners();

    service
        .downloadFile(
      task: task,
      onProgress: (progress) {
        task.progress = progress;
        provider.notifyListeners();
      },
    )
        .catchError((e) {
      task.status = TransferStatus.failed;
      provider.notifyListeners();
    });
  }

  void _cancelDownload(BuildContext context) {
    final provider = Provider.of<TransferProvider>(context, listen: false);
    final service = Provider.of<TransferService>(context, listen: false);

    service.cancelTransfer(task.id);
    provider.downloads.removeWhere((t) => t.id == task.id);
    provider.notifyListeners();
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.download),
      title: LinearProgressIndicator(value: task.progress),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('文件: ${task.filePath.split('/').last}'),
          if (task.status == TransferStatus.downloading)
            Text('速度: ${task.speed} KB/s'),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (task.status == TransferStatus.failed)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _retryDownload(context),
            ),
          IconButton(
            icon: const Icon(Icons.cancel),
            onPressed: () => _cancelDownload(context),
          ),
        ],
      ),
    );
  }
}
