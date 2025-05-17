// /// --- 下载处理函数 ---
//   Future<void> _handleDownload() async {
//     // 检查选中项是否为空
//     if (_selectedFiles.isEmpty) {
//       print("没有文件被选中用于下载。");
//       // 可以选择不显示提示，或者显示一个温和的提示
//       // ScaffoldMessenger.of(context).showSnackBar(
//       //   const SnackBar(content: Text('请先选择要下载的文件')),
//       // );
//       return;
//     }

//     // 检查选中的是否都是文件
//     final List<Map<String, dynamic>> filesToDownload = [];
//     for (final fileId in _selectedFiles) {
//       final file = _allFiles.firstWhere(
//         (f) => f['id']?.toString() == fileId,
//         orElse: () => <String, dynamic>{},
//       );
//       if (file.isNotEmpty && file['type'] == 'file') {
//         filesToDownload.add(file);
//       } else {
//         // 如果选中的包含文件夹，则提示用户或禁用下载按钮
//         print("选中的项目包含文件夹或无效项，无法下载。");
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(content: Text('只能下载文件，不能下载文件夹')),
//         );
//         return; // 中断下载流程
//       }
//     }

//     // 如果 filesToDownload 为空 (虽然前面的检查理论上避免了，但加一层保险)
//     if (filesToDownload.isEmpty) {
//       print("没有有效的文件可供下载。");
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text('未找到可下载的文件')),
//       );
//       return;
//     }

//     String? downloadDirPath;
//     // 1. 获取下载目录
//     try {
//       // final Directory? externalDir =
//       //     await getExternalStorageDirectory(); // 尝试获取公共下载目录
//       final Directory? externalDir =
//           await getDownloadsDirectory(); // 尝试获取公共下载目录

//       if (externalDir != null) {
//         // 在公共下载目录下创建一个应用专属子目录（推荐）
//         downloadDirPath =
//             p.join(externalDir.path, 'CloudS_Downloads'); // 应用名+Downloads
//       } else {
//         // 如果无法获取公共目录（例如 iOS 或权限问题），回退到应用文档目录
//         final Directory docDir = await getApplicationDocumentsDirectory();
//         downloadDirPath = p.join(docDir.path, 'Downloads');
//         print("无法访问外部存储，将下载到应用文档目录。");
//       }

//       final downloadDir = Directory(downloadDirPath);
//       if (!await downloadDir.exists()) {
//         await downloadDir.create(recursive: true);
//       }
//       print("将文件下载到目录: $downloadDirPath");
//     } catch (e) {
//       print("获取/创建下载目录失败: $e");
//       if (!mounted) return;
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text('无法准备下载目录: $e')),
//       );
//       return;
//     }

//     // 2. 创建并添加下载任务
//     final provider = Provider.of<TransferProvider>(context, listen: false);
//     final List<TransferTask> tasksToStart = [];
//     int addedCount = 0;

//     for (final file in filesToDownload) {
//       final String? remoteIdentifier = file['id']?.toString(); // 使用 ID
//       // final String? remoteIdentifier = file['path']?.toString(); // 或者使用 Path，取决于后端
//       final String fileName = file['name'] ?? 'unknown_file';
//       final int totalSize = file['size'] ?? 0;
//       final String localSavePath = p.join(downloadDirPath, fileName); // 本地保存路径

//       // (可选) 检查本地是否已存在同名文件，可以提示用户或自动重命名
//       // if (await File(localSavePath).exists()) { ... }

//       if (remoteIdentifier == null) {
//         print("跳过文件 $fileName: 缺少有效的远程标识符 (ID 或 Path)");
//         continue;
//       }

//       final task = TransferTask(
//         id: Uuid().v4(),
//         filePath: localSavePath,
//         remotePath: remoteIdentifier, // 确认与后端 /download 接口匹配！
//         fileName: fileName,
//         totalSize: totalSize,
//         isUpload: false,
//         status: TransferStatus.queued,
//       );
//       tasksToStart.add(task);
//       addedCount++;
//     }

//     // 3. 添加到 Provider 并启动
//     if (tasksToStart.isNotEmpty) {
//       for (final task in tasksToStart) {
//         await provider.addTask(task); // 添加到 Provider

//         TransferPage.startTransferTask(context, task); // 使用静态方法启动
//       }

//       if (!mounted) return;
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text('$addedCount 个文件已添加到下载队列')),
//       );
//       // 使用 post-frame callback 安全跳转
//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         if (mounted) {
//           Navigator.push(
//               context, MaterialPageRoute(builder: (_) => const TransferPage()));
//         }
//       });
//     } else {
//       // 这个分支理论上不会执行，因为前面已经检查过 filesToDownload 是否为空
//       if (!mounted) return;
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text('未能添加任何下载任务')),
//       );
//     }

//     _exitSelectionMode(); // 退出选择模式
//   }
