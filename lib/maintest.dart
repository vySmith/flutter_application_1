import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 导入 shared_preferences
// 导入你的 Provider 和 Service
import 'transfer_provider.dart';
import 'transfer_service.dart';

// 导入你的页面组件
import 'login_page.dart';
import 'register_page.dart';
import 'home_page.dart';
import 'upload_page.dart'; // 确保导入 UploadPage
// import 'my_shares_page.dart'; // 如果有，也导入
// import 'share_preview_page.dart'; // 如果有，也导入
// import 'trash_page.dart'; // 如果有，也导入

void main() {
  // WidgetsFlutterBinding.ensureInitialized(); // 如果需要插件在 runApp 前初始化
  runApp(const MyApp()); // 直接运行 MyApp
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
          // TODO: 在这里添加刷新 Token 的逻辑 (调用后端 /refresh_token)
          // 如果刷新成功，返回 '/home'，否则返回 '/login'
          // 暂时简单处理为过期则去登录
          return '/login';
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
    // 将 MultiProvider 放在这里，包裹 MaterialApp
    return MultiProvider(
      providers: [
        // 提供状态管理
        ChangeNotifierProvider(create: (_) => TransferProvider()),
        // 提供服务实例
        Provider(create: (_) => TransferService()),
        // 你可以在这里添加其他的全局 Provider 或 Service
      ],
      child: MaterialApp(
        title: 'CloudS', // 你的应用名称
        theme: ThemeData(
          primarySwatch: Colors.blue, // 主题颜色
          visualDensity: VisualDensity.adaptivePlatformDensity,
          // 可以定义全局背景色、字体等
          // scaffoldBackgroundColor: Colors.white,
        ),
        debugShowCheckedModeBanner: false, // 隐藏右上角的 DEBUG 标签 (发布时设为 false)

        // --- 路由管理 ---
        // 设置初始路由
        initialRoute: '/login',

        // 使用 onGenerateRoute 来处理所有路由（特别是需要传递参数的）
        // 这样可以更灵活地处理参数和页面构建
        onGenerateRoute: (settings) {
          print(
              "Navigating to ${settings.name} with arguments: ${settings.arguments}"); // 调试路由

          // 根据路由名称 (settings.name) 返回对应的 MaterialPageRoute
          switch (settings.name) {
            case '/login':
              return MaterialPageRoute(builder: (_) => LoginPage());
            case '/register':
              return MaterialPageRoute(builder: (_) => RegisterPage());
            case '/home':
              // HomePage 通常不需要参数
              return MaterialPageRoute(builder: (_) => HomePage());
            case '/upload':
              // 从 arguments 安全地获取参数
              final args = settings.arguments as Map<String, dynamic>? ?? {};
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

            // 如果没有匹配的路由名称，可以返回默认页面（例如登录页或 404 页面）
            default:
              print("Warning: Unknown route ${settings.name}");
              // 可以创建一个专门的 NotFoundPage
              // return MaterialPageRoute(builder: (_) => NotFoundPage());
              // 或者返回登录页
              return MaterialPageRoute(builder: (_) => LoginPage());
          }
        },
      ),
    );
  }
}
