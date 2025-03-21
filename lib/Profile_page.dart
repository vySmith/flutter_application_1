import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'file_page.dart';

class ProfilePage extends StatefulWidget {
  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String _username = '加载中...'; // 默认用户名
  String _avatarUrl = '/default_avatar.png'; // 默认头像 URL

  @override
  void initState() {
    super.initState();
    _loadUserInfo(); // 初始化时加载用户信息
  }

  // 从 SharedPreferences 获取用户信息（后续可扩展为从服务器获取）
  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');
    // TODO: 根据 userId 从服务器获取 username 和 avatar_url
    // 这里暂时模拟数据
    setState(() {
      _username = '用户_$userId'; // 模拟用户名
      // _avatarUrl 在实际中应从服务器获取，这里使用默认值
    });
  }

  // 点击头像时显示对话框
  void _showAvatarDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: EdgeInsets.zero,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 放大后的头像
            Container(
              margin: EdgeInsets.all(16.0),
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                image: DecorationImage(
                  image: _avatarUrl == '/default_avatar.png'
                      ? AssetImage('assets/default_avatar.png') as ImageProvider
                      : NetworkImage(_avatarUrl),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            // 操作按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () {
                    // TODO: 实现保存头像到手机相册
                    Navigator.pop(context);
                  },
                  child: Text('保存头像'),
                ),
                TextButton(
                  onPressed: () {
                    // TODO: 实现更换头像（调用相册）
                    Navigator.pop(context);
                  },
                  child: Text('更换头像'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 编辑用户名
  void _editUsername(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        String newUsername = _username;
        return AlertDialog(
          title: Text('编辑用户名'),
          content: TextField(
            onChanged: (value) => newUsername = value,
            controller: TextEditingController(text: _username),
            decoration: InputDecoration(hintText: '请输入新用户名'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('取消'),
            ),
            TextButton(
              onPressed: () {
                // TODO: 将新用户名保存到服务器和本地
                setState(() => _username = newUsername);
                Navigator.pop(context);
              },
              child: Text('确定'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('个人'),
      ),
      body: Column(
        children: [
          // 用户信息内容框
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // 头像
                GestureDetector(
                  onTap: () => _showAvatarDialog(context),
                  child: CircleAvatar(
                    radius: 40,
                    backgroundImage: _avatarUrl == '/default_avatar.png'
                        ? AssetImage('assets/default_avatar.png')
                        : NetworkImage(_avatarUrl) as ImageProvider,
                  ),
                ),
                SizedBox(width: 16),
                // 用户名和编辑图标
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _username,
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: Icon(Icons.edit, size: 20),
                        onPressed: () => _editUsername(context),
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
                  leading: Icon(Icons.delete),
                  title: Text('回收站'),
                  onTap: () {
                    // TODO: 跳转到回收站页面
                  },
                ),
                ListTile(
                  leading: Icon(Icons.lock),
                  title: Text('修改密码'),
                  onTap: () {
                    // TODO: 跳转到修改密码页面
                  },
                ),
                ListTile(
                  leading: Icon(Icons.exit_to_app),
                  title: Text('退出登录'),
                  onTap: () {
                    // TODO: 实现退出登录
                  },
                ),
                ListTile(
                  leading: Icon(Icons.cancel),
                  title: Text('注销账号'),
                  onTap: () {
                    // TODO: 实现注销账号
                  },
                ),
                // 可扩展更多功能项
              ],
            ),
          ),
        ],
      ),
    );
  }
}
