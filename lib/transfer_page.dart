import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p; // 确保导入
import 'dart:io'; // 用于 File 操作 (如果需要)
import 'transfer_provider.dart'; // 导入 Provider 和 Task
import 'transfer_service.dart'; // 导入 Service

class TransferPage extends StatelessWidget {
  // 改回 StatelessWidget，因为状态由 Provider 管理
  const TransferPage({Key? key}) : super(key: key);

  // --- 启动/重试任务的统一入口 ---
  // 这个函数现在是静态的或者需要从外部调用，因为它不再属于 State
  // 或者，让 TransferListItem 自己处理启动/重试的逻辑更佳
  // 这里暂时保留，假设可以从列表项回调中调用
  static void startTransferTask(BuildContext context, TransferTask task) {
    final provider = Provider.of<TransferProvider>(context, listen: false);
    final service =
        Provider.of<TransferService>(context, listen: false); // 通过 Provider 获取
    print("==> startTransferTask 被调用，任务 ID: ${task.id}"); // <--- 添加这行
    // 更新状态为处理中 (避免 UI 延迟)
    // 注意：如果任务已经是 processing，重复调用可能没问题，但需注意逻辑
    provider.updateStatus(task.id, TransferStatus.processing);

    if (task.isUpload) {
      service.uploadFile(
        task: task,
        onProgress: (progress) {
          // 使用 Provider 更新，不需要 context (如果 Provider 设计得好)
          // 需要确保 Provider 在异步回调后仍然有效
          try {
            provider.updateProgress(task.id, progress);
          } catch (e) {
            print("Error updating progress in callback for ${task.id}: $e");
          }
        },
        onSuccess: (finalPath) {
          try {
            provider.updateStatus(task.id, TransferStatus.completed);
          } catch (e) {
            print(
                "Error updating status (success) in callback for ${task.id}: $e");
          }
        },
        onError: (error) {
          try {
            provider.updateStatus(task.id, TransferStatus.failed,
                errorMessage: error);
          } catch (e) {
            print(
                "Error updating status (error) in callback for ${task.id}: $e");
          }
        },
      );
    } else {
      // 下载
      service.downloadFile(
        task: task,
        onProgress: (progress) {
          try {
            provider.updateProgress(task.id, progress);
          } catch (e) {
            print("Error updating progress in callback for ${task.id}: $e");
          }
        },
        onSuccess: () {
          try {
            provider.updateStatus(task.id, TransferStatus.completed);
          } catch (e) {
            print(
                "Error updating status (success) in callback for ${task.id}: $e");
          }
        },
        onError: (error) {
          try {
            provider.updateStatus(task.id, TransferStatus.failed,
                errorMessage: error);
          } catch (e) {
            print(
                "Error updating status (error) in callback for ${task.id}: $e");
          }
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final transferProvider = context.watch<TransferProvider>();

    if (!transferProvider.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('传输列表')),
        body: const Center(
            child: CircularProgressIndicator(key: ValueKey('loading'))),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('传输列表'),
          actions: [
            IconButton(
              icon: Icon(Icons.delete_sweep_outlined),
              tooltip: '清除已完成',
              onPressed: transferProvider.tasks
                      .any((t) => t.status == TransferStatus.completed)
                  ? () => transferProvider.clearCompleted()
                  : null,
            ),
            // 移除了模拟添加按钮
          ],
          bottom: const TabBar(
            key: ValueKey('tabbar'),
            tabs: [
              Tab(text: '上传'),
              Tab(text: '下载'),
            ],
          ),
        ),
        body: TabBarView(
          key: ValueKey('tabbarview'),
          children: [
            // 直接从 Provider 获取过滤后的列表
            _buildTaskList(context, transferProvider.uploads, true),
            _buildTaskList(context, transferProvider.downloads, false),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskList(
      BuildContext context, List<TransferTask> tasks, bool isUpload) {
    if (tasks.isEmpty) {
      return Center(child: Text('没有${isUpload ? '上传' : '下载'}任务'));
    }

    return RefreshIndicator(
      onRefresh: () async {
        // 实际下拉刷新逻辑：可以尝试重新加载 Provider 数据或重试失败任务
        // Provider.of<TransferProvider>(context, listen: false).retryFailedTasks(); // 假设有此方法
        await Future.delayed(Duration(milliseconds: 500));
      },
      child: ListView.builder(
          itemCount: tasks.length,
          itemBuilder: (ctx, index) {
            final task = tasks[index];
            return TransferListItem(
              key: ValueKey(task.id),
              task: task,
              onRetry: () => startTransferTask(context, task), // 调用静态或可访问的启动函数
              onCancel: (taskId) {
                final provider =
                    Provider.of<TransferProvider>(context, listen: false);
                // 取消逻辑现在也需要能访问 service
                final service =
                    Provider.of<TransferService>(context, listen: false);
                service.cancelTransfer(taskId);
                provider.removeTask(taskId);
              },
            );
          }),
    );
  }
}

// --- 单个传输列表项 Widget (TransferListItem) ---
// (代码与上一个回答中的 TransferListItem 保持一致)
class TransferListItem extends StatelessWidget {
  final TransferTask task;
  final VoidCallback onRetry;
  final Function(String) onCancel;

  const TransferListItem({
    Key? key,
    required this.task,
    required this.onRetry,
    required this.onCancel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    IconData leadingIcon =
        task.isUpload ? Icons.upload_file : Icons.download_for_offline;
    String statusText = '';
    Color? statusColor;

    switch (task.status) {
      case TransferStatus.queued:
        statusText = '排队中';
        break;
      case TransferStatus.processing:
        statusText = '进行中';
        break;
      case TransferStatus.completed:
        statusText = '已完成';
        statusColor = Colors.green;
        leadingIcon = Icons.check_circle;
        break;
      case TransferStatus.failed:
        statusText = '失败';
        statusColor = Colors.red;
        leadingIcon = Icons.error;
        break;
      case TransferStatus.paused:
        statusText = '已暂停';
        statusColor = Colors.orange;
        break;
      case TransferStatus.canceled:
        statusText = '已取消';
        statusColor = Colors.grey;
        break;
    }

    String fileSizeFormatted =
        '${(task.totalSize / (1024 * 1024)).toStringAsFixed(2)} MB';
    if (task.totalSize < 1024 * 1024) {
      fileSizeFormatted = '${(task.totalSize / 1024).toStringAsFixed(1)} KB';
    }
    if (task.totalSize < 1024) {
      fileSizeFormatted = '${task.totalSize} B';
    }

    return ListTile(
      leading: Icon(leadingIcon, color: statusColor),
      title: Text(
        task.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (task.status != TransferStatus.completed &&
              task.status != TransferStatus.canceled)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: LinearProgressIndicator(
                value: task.progress,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(
                    task.status == TransferStatus.failed
                        ? Colors.red
                        : Theme.of(context).primaryColor),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${(task.progress * 100).toStringAsFixed(0)}%  ($statusText)',
                style: TextStyle(
                    fontSize: 12, color: statusColor ?? Colors.grey[600]),
              ),
              Text(
                fileSizeFormatted,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
          if (task.status == TransferStatus.failed && task.errorMessage != null)
            Padding(
              // Add padding for error message
              padding: const EdgeInsets.only(top: 2.0),
              child: Text(
                task.errorMessage!,
                style: TextStyle(fontSize: 11, color: Colors.red),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
      trailing: _buildActionButtons(context),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    List<Widget> buttons = [];

    if (task.status == TransferStatus.failed) {
      buttons.add(
        IconButton(
          icon: Icon(Icons.refresh),
          iconSize: 20,
          splashRadius: 20,
          tooltip: task.isUpload ? "重试上传" : "重试下载",
          onPressed: onRetry,
        ),
      );
    }

    if (task.status != TransferStatus.completed &&
        task.status != TransferStatus.canceled) {
      buttons.add(
        IconButton(
          icon: Icon(Icons.cancel_outlined),
          iconSize: 20,
          splashRadius: 20,
          color: Colors.redAccent,
          tooltip: task.isUpload ? "取消上传" : "取消下载",
          onPressed: () => onCancel(task.id),
        ),
      );
    }

    if (buttons.isEmpty && task.status == TransferStatus.completed) {
      return Icon(Icons.check_circle, color: Colors.green, size: 20);
    } else if (buttons.isEmpty) {
      return SizedBox(width: 40);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: buttons,
    );
  }
}
