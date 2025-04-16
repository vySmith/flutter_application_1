import 'package:flutter/material.dart';
import 'file_page.dart'; // 确保导入 FilePage
import 'Profile_page.dart';
import 'transfer_page.dart';

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    FilePage(), // 文件页
    //Center(child: Text('传输页面')),
    TransferPage(), // 占位页面
    ProfilePage(),
    //Center(child: Text('个人页面')), // 占位页面
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.folder), label: '文件'),
          BottomNavigationBarItem(icon: Icon(Icons.swap_horiz), label: '传输'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: '个人'),
        ],
      ),
    );
  }
}
