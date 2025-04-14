import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For Clipboard
import 'FileService.dart'; // 导入你的服务类
// 推荐使用 intl 包格式化日期
// import 'package:intl/intl.dart';

class MySharesPage extends StatefulWidget {
  const MySharesPage({Key? key}) : super(key: key);

  @override
  _MySharesPageState createState() => _MySharesPageState();
}

class _MySharesPageState extends State<MySharesPage> {
  Future<List<Map<String, dynamic>>>? _mySharesFuture;

  @override
  void initState() {
    super.initState();
    _loadMyShares(); // 初始化时加载
  }

  // 加载我的分享列表
  void _loadMyShares() {
    setState(() {
      _mySharesFuture = FileService.getMyShares();
    });
  }

  // 格式化日期时间 (基本)
  String _formatDateTime(String? dateTimeString) {
    if (dateTimeString == null) return 'N/A';
    try {
      final dt = DateTime.parse(dateTimeString).toLocal();
      // 使用 intl 包可以获得更好的格式化: return DateFormat('yyyy-MM-dd HH:mm').format(dt);
      return dt.toString().substring(0, 16); // 基本格式
    } catch (e) {
      return '无效日期';
    }
  }

  // 计算过期状态或剩余天数
  String _getExpiryStatus(String? expiresAtString) {
    if (expiresAtString == null) return '永不'; // 没有设置过期时间
    try {
      final expiryDate = DateTime.parse(expiresAtString);
      final now = DateTime.now();
      if (expiryDate.isBefore(now)) {
        return '已过期';
      }
      final remaining = expiryDate.difference(now);
      if (remaining.inDays > 0) {
        return '剩余 ${remaining.inDays} 天';
      } else if (remaining.inHours > 0) {
        return '剩余 ${remaining.inHours} 小时';
      } else {
        return '即将过期';
      }
    } catch (e) {
      return '无效日期';
    }
  }

  // 取消分享的处理逻辑
  Future<void> _handleCancelShare(String shareCode, String fileName) async {
    // 二次确认
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('确认取消分享'),
        content: Text('确定要取消对 "$fileName" (分享码: $shareCode) 的分享吗？链接将立即失效。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: Text('关闭')),
          TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('确认取消')),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FileService.cancelShare(shareCode);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享 "$shareCode" 已取消')),
      );
      _loadMyShares(); // 重新加载列表
    } catch (e) {
      print("取消分享失败: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('取消分享失败: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('我的分享'),
        actions: [
          IconButton(
            // 添加刷新按钮
            icon: Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _loadMyShares,
          )
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _mySharesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                  '加载分享列表失败: ${snapshot.error.toString().replaceFirst("Exception: ", "")}'),
            );
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('你还没有分享过任何文件。'));
          }

          final myShares = snapshot.data!;

          return RefreshIndicator(
            // 添加下拉刷新
            onRefresh: () async => _loadMyShares(),
            child: ListView.builder(
              itemCount: myShares.length,
              itemBuilder: (context, index) {
                final share = myShares[index];
                final String shareCode = share['share_code'] ?? '----';
                final String fileName = share['file_name'] ?? '未知文件';
                // final String filePath = share['file_path'] ?? ''; // 可能需要
                final String fileType = share['file_type'] ?? 'file';
                final String createdAt = _formatDateTime(share['created_at']);
                final String expiryStatus =
                    _getExpiryStatus(share['expires_at']);

                return Card(
                  // 使用 Card 增加区分度
                  margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    leading: Icon(
                      fileType == 'folder'
                          ? Icons.folder_outlined
                          : Icons.insert_drive_file_outlined,
                      color: fileType == 'folder'
                          ? Colors.orangeAccent
                          : Colors.grey,
                    ),
                    title: Text(fileName,
                        style: TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          // 分享码和复制按钮
                          children: [
                            Text('分享码: ', style: TextStyle(fontSize: 12)),
                            Text(shareCode,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).primaryColor)),
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints(), // 移除默认 padding
                              iconSize: 16,
                              splashRadius: 16,
                              icon: Icon(Icons.copy),
                              tooltip: '复制分享码',
                              onPressed: () {
                                Clipboard.setData(
                                    ClipboardData(text: shareCode));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('分享码 $shareCode 已复制')),
                                );
                              },
                            )
                          ],
                        ),
                        Text('创建时间: $createdAt',
                            style: TextStyle(fontSize: 12)),
                        Text('状态: $expiryStatus',
                            style: TextStyle(
                                fontSize: 12,
                                color:
                                    expiryStatus == '已过期' ? Colors.red : null)),
                      ],
                    ),
                    trailing: IconButton(
                      // 取消分享按钮
                      icon: Icon(Icons.link_off, color: Colors.redAccent),
                      tooltip: '取消分享',
                      onPressed: () => _handleCancelShare(shareCode, fileName),
                    ),
                    // 可以添加 onTap 跳转到文件位置 (如果需要)
                    // onTap: () { ... }
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
