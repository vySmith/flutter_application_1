import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'config.dart';

class RegisterPage extends StatefulWidget {
  @override
  _RegisterPageState createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  String _username = '';
  String _password = '';
  bool _obscurePassword = true; // 控制密码显示

  Future<void> _register() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      print('Sending register request for username: $_username'); // 调试信息
      try {
        final response = await http.post(
          Uri.parse('${Config.baseUrl}/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': _username, 'password': _password}),
        );
        print('Response status: ${response.statusCode}'); // 调试信息
        print('Response body: ${response.body}'); // 调试信息
        if (response.statusCode == 201) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('注册成功')));
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('注册失败: ${jsonDecode(response.body)['message']}')));
        }
      } catch (e) {
        print('Error: $e'); // 调试信息
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('注册失败: 网络错误')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('注册')),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
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
                onPressed: _register,
                child: Text('注册'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
