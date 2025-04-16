// // 视频预览组件
// class VideoPreviewScreen extends StatefulWidget {
//   final String videoUrl;

//   const VideoPreviewScreen({required this.videoUrl});

//   @override
//   _VideoPreviewScreenState createState() => _VideoPreviewScreenState();
// }

// class _VideoPreviewScreenState extends State<VideoPreviewScreen> {
//   late VideoPlayerController _controller;
//   bool _initialized = false; // 标记初始化状态
//   bool _hasError = false; // 标记是否有错误

//   @override
//   void initState() {
//     super.initState();
//     print(
//         "VideoPreviewScreen initState: Initializing video from ${widget.videoUrl}");
//     Uri? videoUri;
//     try {
//       videoUri = Uri.parse(widget.videoUrl); // 解析 Uri
//     } catch (e) {
//       print("Error parsing video URL: ${widget.videoUrl}, Error: $e");
//       setState(() {
//         _hasError = true; // 标记错误状态
//       });
//       return; // 如果 URL 无效，则不继续初始化
//     }

//     _controller = VideoPlayerController.networkUrl(videoUri)
//       ..initialize().then((_) {
//         setState(() {
//           _initialized = true;
//           _hasError = false;
//         });
//         _controller.play();
//         _controller.setLooping(true); // 可以选择循环播放
//       }).catchError((error) {
//         // 初始化失败
//         print("Error initializing video player: $error");
//         setState(() {
//           _initialized = false; // 确保 initialized 为 false
//           _hasError = true; // 标记错误状态
//         });
//       });
//   }

//   @override
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(),
//       body: _controller.value.isInitialized
//           ? AspectRatio(
//               aspectRatio: _controller.value.aspectRatio,
//               child: VideoPlayer(_controller),
//             )
//           : Center(child: CircularProgressIndicator()),
//     );
//   }

//   @override
//   void dispose() {
//     _controller.dispose();
//     super.dispose();
//   }
// }
