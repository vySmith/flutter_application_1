import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'register_page.dart';
import 'home_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart'; // 确保 Config.baseUrl 正确

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  String _username = '';
  String _password = '';
  // 头像不再需要本地状态，可以在登录成功后从 SharedPreferences 读取或在 HomePage 读取
  // String _avatarUrl = 'assets/default_avatar.jpg';
  bool _isLoading = false; // 添加加载状态
  bool _obscurePassword = true;

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      setState(() {
        _isLoading = true;
      }); // 开始加载
      print('Sending login request for username: $_username');
      try {
        final response = await http
            .post(
              Uri.parse('${Config.baseUrl}/login'), // 确保 URL 正确
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'username': _username, 'password': _password}),
            )
            .timeout(const Duration(seconds: 15)); // 添加超时

        print('Response status: ${response.statusCode}');
        print('Response body: ${response.body}');

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          // --- 存储认证信息 ---
          final prefs = await SharedPreferences.getInstance();
          final userId = data['user_id'];
          final nickname = data['nickname'];
          final avatarUrl = data['avatar_url'];
          final accessToken = data['access_token'];
          final refreshToken = data['refresh_token'];
          final expiresAt = data['expires_at']; // 毫秒时间戳

          if (userId == null ||
              accessToken == null ||
              refreshToken == null ||
              expiresAt == null) {
            print("Error: Missing essential data in login response");
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('登录失败: 服务器响应格式错误')));
            setState(() {
              _isLoading = false;
            });
            return;
          }

          await prefs.setString('userId', userId.toString());
          await prefs.setString('access_token', accessToken);
          await prefs.setString('refresh_token', refreshToken);
          await prefs.setInt('token_expires_at', expiresAt); // 存储 int
          // 也可以存储其他用户信息，方便全局使用
          await prefs.setString('nickname', nickname ?? ''); // 处理 null
          await prefs.setString('avatar_url', avatarUrl ?? ''); // 处理 null

          print("Login successful. Tokens and User info saved.");

          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('登录成功')));

          // 使用 pushNamedAndRemoveUntil 清除登录页并导航到主页
          Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
        } else {
          // 处理登录失败
          String errorMessage = '登录失败';
          try {
            final errorData = jsonDecode(response.body);
            errorMessage = errorData['message'] ?? '未知错误';
          } catch (e) {
            errorMessage = '登录失败 (${response.statusCode})';
          }
          print("Login failed: $errorMessage");
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(errorMessage)));
        }
      } catch (e) {
        print('Login Error: $e');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('登录出错: ${'网络或服务器错误'}')));
      } finally {
        setState(() {
          _isLoading = false;
        }); // 结束加载
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CloudS 登录')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Center(
            // 让内容居中
            child: SingleChildScrollView(
              // 避免键盘弹出时溢出
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center, // 垂直居中
                children: [
                  // 可以显示一个默认头像或 Logo
                  const CircleAvatar(
                    radius: 50,
                    // backgroundImage: AssetImage('assets/logo.png'), // 使用你的 Logo
                    child: Icon(Icons.cloud_queue, size: 60), // 或者一个图标
                  ),
                  const SizedBox(height: 30),
                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: '用户名',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '请输入用户名';
                      }
                      return null;
                    },
                    onSaved: (value) => _username = value!,
                  ),
                  const SizedBox(height: 15),
                  TextFormField(
                    decoration: InputDecoration(
                      labelText: '密码',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    obscureText: _obscurePassword,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '请输入密码';
                      }
                      return null;
                    },
                    onSaved: (value) => _password = value!,
                  ),
                  const SizedBox(height: 30),
                  _isLoading
                      ? const CircularProgressIndicator() // 显示加载指示器
                      : ElevatedButton(
                          onPressed: _login,
                          style: ElevatedButton.styleFrom(
                            minimumSize:
                                const Size(double.infinity, 50), // 让按钮更宽
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('登录'),
                        ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () =>
                            Navigator.pushNamed(context, '/register'), // 注册路由
                    child: const Text('还没有账户？立即注册'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
