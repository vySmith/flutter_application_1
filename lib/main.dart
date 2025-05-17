import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async'; // For Future

// 服务和 Provider
import 'authService.dart'; // 导入 AuthService
import 'transfer_provider.dart';
import 'transfer_service.dart';

// 页面
import 'login_page.dart';
import 'register_page.dart';
import 'home_page.dart';
import 'upload_page.dart';
import 'splash_screen.dart'; // 新建一个启动屏文件

void main() {
  WidgetsFlutterBinding.ensureInitialized(); // 确保插件初始化
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // --- 检查登录状态并决定初始路由 ---
  Future<String> _getInitialRoute() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      final refreshToken = prefs.getString('refresh_token');
      final expiresAtMillis = prefs.getInt('token_expires_at');
      final userId = prefs.getString('userId'); // 也检查 userId

      if (accessToken != null && userId != null) {
        bool isAccessTokenExpired = true; // 默认过期，除非检查通过
        if (expiresAtMillis != null) {
          final expiresAt =
              DateTime.fromMillisecondsSinceEpoch(expiresAtMillis);
          // 加一点缓冲时间 (例如 60 秒) 以避免边缘情况
          isAccessTokenExpired = DateTime.now()
              .add(const Duration(seconds: 60))
              .isAfter(expiresAt);
          print("Access Token Expires At: $expiresAt");
          print("Is Access Token Expired: $isAccessTokenExpired");
        }

        if (!isAccessTokenExpired) {
          print("Access token valid. Navigating to home.");
          // 可以在这里做一次后台的 token 验证（可选，更安全）
          // await AuthService.verifyToken(accessToken); // 假设有这个方法
          return '/home'; // Access Token 有效，去主页
        } else {
          // Access Token 过期，尝试刷新
          print("Access token expired. Attempting refresh...");
          if (refreshToken != null) {
            bool refreshed = await AuthService.refreshToken(refreshToken);
            if (refreshed) {
              print("Token refresh successful. Navigating to home.");
              return '/home'; // 刷新成功，去主页
            } else {
              print(
                  "Token refresh failed. Clearing tokens and navigating to login.");
              // 刷新失败 (Refresh Token 可能也过期或无效)
              await _clearAuthData(prefs); // 清除所有认证数据
              return '/login';
            }
          } else {
            print(
                "Access token expired, but no refresh token found. Navigating to login.");
            await _clearAuthData(prefs); // 清除可能残留的数据
            return '/login'; // 没有 Refresh Token，去登录
          }
        }
      } else {
        print("No valid tokens or user ID found. Navigating to login.");
        await _clearAuthData(prefs); // 确保清理
        return '/login'; // 没有有效凭证，去登录页
      }
    } catch (e) {
      print("Error checking initial route: $e");
      // 发生错误时，最好也清除数据并要求重新登录
      try {
        final prefs = await SharedPreferences.getInstance();
        await _clearAuthData(prefs);
      } catch (_) {} // 忽略清除时的错误
      return '/login'; // 出错也去登录页
    }
  }

  // 辅助函数：清除认证相关的 SharedPreferences 数据
  Future<void> _clearAuthData(SharedPreferences prefs) async {
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('token_expires_at');
    await prefs.remove('userId');
    // 如果还存了 nickname, avatar_url 等，也一并清除
    await prefs.remove('nickname');
    await prefs.remove('avatar_url');
    print("Authentication data cleared from SharedPreferences.");
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TransferProvider()),
        Provider(create: (_) => TransferService()),
        Provider(create: (_) => AuthService()), // 提供 AuthService 实例
      ],
      child: MaterialApp(
        title: 'CloudS',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        debugShowCheckedModeBanner: false,

        // --- 使用 FutureBuilder 来决定初始路由 ---
        home: FutureBuilder<String>(
          future: _getInitialRoute(), // 异步获取初始路由
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              // 正在检查登录状态，显示启动屏或加载指示器
              return const SplashScreen(); // 或者一个简单的 CircularProgressIndicator
            } else if (snapshot.hasError) {
              // 获取路由出错，显示错误信息或直接去登录页
              print("Error in FutureBuilder: ${snapshot.error}");
              // 这里可能需要一个错误页面，或者简单地导航到登录页
              return LoginPage(); // 兜底到登录页
            } else {
              // 获取到初始路由，根据结果导航
              final initialRoute = snapshot.data ?? '/login'; // 默认到登录页
              print("Initial route determined: $initialRoute");
              // 不能直接设置 initialRoute，因为 MaterialApp 已经构建
              // 我们需要立即导航到目标页面
              // 使用 WidgetsBinding.instance.addPostFrameCallback 确保在第一帧后导航
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (Navigator.of(context).canPop()) {
                  // 如果当前堆栈不是空的 (例如从启动屏过来), 避免重复推送
                  Navigator.of(context)
                      .pushNamedAndRemoveUntil(initialRoute, (route) => false);
                } else {
                  Navigator.of(context).pushReplacementNamed(initialRoute);
                }
              });
              // 返回一个占位符或者启动屏，因为导航会在下一帧发生
              return const SplashScreen(); // 或者 Scaffold()
            }
          },
        ),

        // --- 路由管理 ---
        // routes 属性更适合简单的命名路由，如果 onGenerateRoute 满足需求，可以用它
        routes: {
          // 不再需要 initialRoute，由 home+FutureBuilder 处理
          '/login': (context) => LoginPage(),
          '/register': (context) => RegisterPage(),
          '/home': (context) => HomePage(),
          '/splash': (context) => const SplashScreen(), // 定义启动屏路由
          // '/upload' 路由需要参数，继续使用 onGenerateRoute
        },
        onGenerateRoute: (settings) {
          print(
              "onGenerateRoute: Navigating to ${settings.name} with arguments: ${settings.arguments}");

          switch (settings.name) {
            // onGenerateRoute 可以覆盖 routes 中定义的路由，如果需要传递参数
            case '/login':
              return MaterialPageRoute(builder: (_) => LoginPage());
            case '/register':
              return MaterialPageRoute(builder: (_) => RegisterPage());
            case '/home':
              return MaterialPageRoute(builder: (_) => HomePage());
            case '/splash':
              return MaterialPageRoute(builder: (_) => const SplashScreen());

            case '/upload':
              final args = settings.arguments as Map<String, dynamic>? ?? {};
              final uploadType = args['uploadType'] as String? ?? 'other';
              final currentPath = args['currentPath'] as String? ?? '/';
              return MaterialPageRoute(
                builder: (_) => UploadPage(
                  uploadType: uploadType,
                  currentPath: currentPath,
                ),
              );
            default:
              print(
                  "Warning: Unknown route ${settings.name}, navigating to login.");
              return MaterialPageRoute(builder: (_) => LoginPage());
          }
        },
      ),
    );
  }
}
