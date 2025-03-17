import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'register_page.dart';
import 'home_page.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 导入 shared_preferences
import 'config.dart';

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  String _username = '';
  String _password = '';
  String _avatarUrl = 'assets/default_avatar.jpg';
  bool _obscurePassword = true;

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      print('Sending login request for username: $_username');
      try {
        final response = await http.post(
          Uri.parse('${Config.baseUrl}/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': _username, 'password': _password}),
        );
        print('Response status: ${response.statusCode}');
        print('Response body: ${response.body}');
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          setState(() {
            _avatarUrl = data['avatar_url'];
          });
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('登录成功')));

          // 获取 SharedPreferences 实例
          final prefs = await SharedPreferences.getInstance();
          // TODO: 后端登录接口应该返回 user_id，这里假设返回了 'user_id' 字段
          final userId = data['user_id']; // 从登录接口返回的数据中获取 user_id
          await prefs.setString('userId', userId.toString()); // 存储 user_id

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => HomePage()),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('登录失败: ${jsonDecode(response.body)['message']}')));
        }
      } catch (e) {
        print('Error: $e');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('登录失败: 网络错误')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('CloudS')),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              CircleAvatar(
                radius: 50,
                backgroundImage: _avatarUrl.startsWith('http')
                    ? NetworkImage(_avatarUrl)
                    : AssetImage(_avatarUrl) as ImageProvider,
              ),
              SizedBox(height: 20),
              TextFormField(
                decoration: InputDecoration(labelText: '用户名'),
                validator: (value) => value!.isEmpty ? '请输入用户名' : null,
                onSaved: (value) => _username = value!,
              ),
              TextFormField(
                decoration: InputDecoration(
                  labelText: '密码',
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
                validator: (value) => value!.isEmpty ? '请输入密码' : null,
                onSaved: (value) => _password = value!,
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _login,
                child: Text('登录'),
              ),
              TextButton(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (context) => RegisterPage())),
                child: Text('注册'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
