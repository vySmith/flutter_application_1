import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For input formatters
import 'package:shared_preferences/shared_preferences.dart';
import 'trash_page.dart';
// import 'my_shares_page.dart'; // 需要创建这个页面
// import 'share_preview_page.dart'; // 需要创建这个页面
import 'UserService.dart'; // 假设 UserService 用于处理用户相关 API 调用
import 'sharePreview_Page.dart';
import 'myshare_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key}); // 使用 super key

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String _username = '加载中...';
  String _nickname = '加载中...'; // 新增昵称状态
  String? _avatarUrl = '/default_avatar.png'; // 可以为 null

  bool _isLoading = true; // 加载状态

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final userInfo = await UserService.getUserProfile(); // 调用 Service 获取信息
      if (!mounted) return;
      setState(() {
        _username = userInfo['username'] ?? '未知用户';
        _nickname = userInfo['nickname'] ?? '未设置昵称'; // 使用获取到的昵称
        _avatarUrl = userInfo['avatar_url']; // 可以为 null
        _isLoading = false;
      });
    } catch (e) {
      print("加载用户信息失败: $e");
      if (!mounted) return;
      setState(() {
        _username = '加载失败';
        _nickname = '加载失败';
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载用户信息失败: ${e.toString()}')),
      );
    }
  }

  void _showAvatarDialog(BuildContext context) {
    // ... (保持不变，但注意处理 _avatarUrl 可能为 null 的情况) ...
    final imageProvider =
        (_avatarUrl == null || _avatarUrl == '/default_avatar.png')
            ? AssetImage('assets/default_avatar.png') as ImageProvider
            : NetworkImage(_avatarUrl!); // 如果不为 null，则使用 NetworkImage

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        // ... (内容使用 imageProvider) ...
        contentPadding: EdgeInsets.zero,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: EdgeInsets.all(16.0),
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                image: DecorationImage(
                  image: imageProvider,
                  fit: BoxFit.cover,
                  // 添加错误处理 for NetworkImage
                  onError: (exception, stackTrace) {
                    print("Error loading avatar: $exception");
                    // 可以显示一个占位符或默认头像
                  },
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                    onPressed: () {
                      /* TODO */ Navigator.pop(context);
                    },
                    child: Text('保存头像')),
                TextButton(
                    onPressed: () {
                      /* TODO */ Navigator.pop(context);
                    },
                    child: Text('更换头像')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 编辑昵称
  void _editNickname(BuildContext context) {
    final nicknameController =
        TextEditingController(text: _nickname); // 使用 Controller
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('编辑昵称'),
          content: TextField(
            controller: nicknameController, // 绑定 Controller
            autofocus: true,
            maxLength: 50, // 限制长度，与数据库一致
            decoration: InputDecoration(hintText: '请输入新昵称'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                // 改为 async
                final newNickname = nicknameController.text.trim();
                Navigator.pop(context); // 先关闭对话框

                if (newNickname.isEmpty) {
                  // 可以允许空昵称，根据需求调整
                  // 或者不允许空：
                  // ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('昵称不能为空')));
                  // return;
                }

                if (newNickname == _nickname) return; // 没有改变

                try {
                  // 调用 Service 更新昵称
                  await UserService.updateNickname(newNickname);
                  if (!mounted) return;
                  // 更新本地状态
                  setState(() => _nickname = newNickname);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('昵称更新成功')),
                  );
                } catch (e) {
                  print("更新昵称失败: $e");
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('更新昵称失败: ${e.toString()}')),
                  );
                }
              },
              child: Text('确定'),
            ),
          ],
        );
      },
    );
  }

  // 显示输入分享码对话框 (新增)
  void _showEnterShareCodeDialog() {
    final codeController = TextEditingController();
    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('接收分享'),
            content: TextField(
              controller: codeController,
              autofocus: true,
              maxLength: 4, // 限制输入长度为 4
              inputFormatters: [
                // 只允许输入字母和数字
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
              ],
              decoration: InputDecoration(
                hintText: '请输入 4 位分享码',
                counterText: "", // 隐藏默认的长度计数器
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  final code = codeController.text.trim();
                  Navigator.pop(context); // 关闭对话框
                  if (code.length == 4) {
                    // TODO: 跳转到 SharePreviewPage 并传递 code
                    print("准备访问分享码: $code");
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              SharePreviewPage(shareCode: code),
                        ));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('即将打开分享: $code (预览页待实现)')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('请输入有效的 4 位分享码')),
                    );
                  }
                },
                child: Text('确定'),
              ),
            ],
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    // 根据加载状态显示不同内容
    Widget bodyContent;
    if (_isLoading) {
      bodyContent = Center(child: CircularProgressIndicator());
    } else {
      bodyContent = Column(
        children: [
          // 用户信息内容框
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => _showAvatarDialog(context),
                  child: CircleAvatar(
                    radius: 40,
                    backgroundImage: (_avatarUrl == null ||
                            _avatarUrl == '/default_avatar.png')
                        ? AssetImage('assets/default_avatar.png')
                            as ImageProvider
                        : NetworkImage(_avatarUrl!),
                    // 可以添加加载或错误占位符
                    onBackgroundImageError: (exception, stackTrace) {
                      print("Error loading avatar in CircleAvatar: $exception");
                    },
                    child: (_avatarUrl == null ||
                            _avatarUrl == '/default_avatar.png')
                        ? Icon(Icons.person, size: 40)
                        : null, // 默认图标
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    // 改为 Column 显示昵称和用户名
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        // 昵称和编辑按钮
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            // 让昵称可以换行
                            child: Text(
                              _nickname,
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis, // 超长省略
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.edit, size: 20),
                            tooltip: '编辑昵称',
                            onPressed: () => _editNickname(context),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      Text(
                        // 显示用户名 (可选)
                        '用户名: $_username',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(),
          // 功能列表
          Expanded(
            child: ListView(
              children: [
                ListTile(
                  // 新增：我的分享
                  leading: Icon(Icons.share_outlined), // 使用 Outlined 图标
                  title: Text('我的分享'),
                  trailing: Icon(Icons.chevron_right),
                  onTap: () {
                    // TODO: 跳转到 MySharesPage
                    print("跳转到 我的分享 页面 (待实现)");
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => MySharesPage()));
                  },
                ),
                ListTile(
                  // 新增：输入分享码
                  leading:
                      Icon(Icons.qr_code_scanner), // 或 Icons.vpn_key_outlined
                  title: Text('输入分享码'),
                  trailing: Icon(Icons.chevron_right),
                  onTap: _showEnterShareCodeDialog, // 调用显示对话框的函数
                ),
                Divider(), // 分隔符
                ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('回收站'),
                  trailing: Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const TrashPage()),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(Icons.lock_outline),
                  title: Text('修改密码'),
                  trailing: Icon(Icons.chevron_right),
                  onTap: () {
                    // TODO: 跳转到修改密码页面
                  },
                ),
                Divider(),
                ListTile(
                  leading: Icon(Icons.exit_to_app, color: Colors.red),
                  title: Text('退出登录', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    // TODO: 实现退出登录 (清除 SharedPreferences, 返回登录页)
                  },
                ),
                ListTile(
                  leading: Icon(Icons.cancel_outlined, color: Colors.red),
                  title: Text('注销账号', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    // TODO: 实现注销账号 (需要二次确认，调用后端接口)
                  },
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('个人'),
      ),
      body: bodyContent, // 使用根据加载状态选择的 body
    );
  }
}
