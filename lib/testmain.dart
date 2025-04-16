import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 导入 shared_preferences
// 导入你的 Provider 和 Service
import 'transfer_provider.dart';
import 'transfer_service.dart';
import 'authService.dart';
// 导入你的页面组件
import 'login_page.dart';
import 'register_page.dart';
import 'home_page.dart';
import 'upload_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // --- 检查登录状态的 Future ---
  Future<String> _getInitialRoute() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');
      final expiresAtMillis = prefs.getInt('token_expires_at'); // 假设存储的是毫秒时间戳
      final userId = prefs.getString('userId');

      if (token != null && userId != null) {
        // 简单的过期检查 (实际应考虑时间戳格式和刷新逻辑)
        bool isExpired = false;
        if (expiresAtMillis != null) {
          isExpired = DateTime.now().millisecondsSinceEpoch > expiresAtMillis;
        }

        if (!isExpired) {
          print("Token found and valid, navigating to home.");
          return '/home'; // 已登录，去主页
        } else {
          print("Token found but expired.");
          // --- !!! 实际的刷新 Token 逻辑需要在这里实现 !!! ---
          final refreshToken = prefs.getString('refresh_token');
          if (refreshToken != null) {
            try {
              print("Attempting to refresh token...");
              // 假设 AuthService 有 refreshToken 方法
              final bool refreshed =
                  await AuthService.refreshToken(refreshToken);
              if (refreshed) {
                print("Token refreshed successfully.");
                return '/home'; // 刷新成功，去主页
              } else {
                print("Token refresh failed.");
                await prefs.clear(); // 清除无效凭证
                return '/login';
              }
            } catch (e) {
              print("Error during token refresh: $e");
              await prefs.clear(); // 出错也清除
              return '/login';
            }
          } else {
            print("No refresh token found.");
            await prefs.clear(); // 清除无效凭证
            return '/login';
          }
        }
      } else {
        print("No valid token or user ID found.");
        return '/login'; // 没有有效凭证，去登录页
      }
    } catch (e) {
      print("Error checking initial route: $e");
      return '/login'; // 出错也去登录页
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TransferProvider()),
        Provider(create: (_) => TransferService()),
      ],
      child: FutureBuilder<String>(
          // 使用 FutureBuilder 确定初始路由
          future: _getInitialRoute(), // 调用检查函数
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              print("FutureBuilder error: ${snapshot.error}");
              return MaterialApp(
                home: Scaffold(
                    body: Center(child: Text("Error: ${snapshot.error}"))),
              );
            }

            // 在 Future 完成前可以显示加载界面
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const MaterialApp(
                debugShowCheckedModeBanner: false,
                home:
                    Scaffold(body: Center(child: CircularProgressIndicator())),
              );
            }

            // 根据 Future 的结果设置 initialRoute
            final initialRoute = snapshot.hasData && snapshot.data != null
                ? snapshot.data!
                : '/login';
            print("Initial route determined: $initialRoute");

            return MaterialApp(
              title: 'CloudS',
              theme: ThemeData(
                primarySwatch: Colors.blue,
                visualDensity: VisualDensity.adaptivePlatformDensity,
              ),
              debugShowCheckedModeBanner: false,
              initialRoute: initialRoute, // <--- 使用动态获取的初始路由
              onGenerateRoute: (settings) {
                // <--- 保持 onGenerateRoute
                // ... (你的路由生成逻辑) ...
                switch (settings.name) {
                  case '/login':
                    return MaterialPageRoute(builder: (_) => LoginPage());
                  case '/home':
                    return MaterialPageRoute(builder: (_) => HomePage());
                  // ... 其他路由
                  case '/upload':
                    // 从 arguments 安全地获取参数
                    final args =
                        settings.arguments as Map<String, dynamic>? ?? {};
                    final uploadType =
                        args['uploadType'] as String? ?? 'other'; // 提供默认值
                    final currentPath =
                        args['currentPath'] as String? ?? '/'; // 提供默认值
                    return MaterialPageRoute(
                      builder: (_) => UploadPage(
                        // 传递参数给 UploadPage
                        uploadType: uploadType,
                        currentPath: currentPath,
                      ),
                    );
                  default:
                    return MaterialPageRoute(builder: (_) => LoginPage());
                }
              },
            );
          }),
    );
  }
}
