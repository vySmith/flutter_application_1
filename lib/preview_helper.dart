import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart'; // 导入 PDF 预览库
import 'package:just_audio/just_audio.dart'; // 导入音频播放库
import 'package:http/http.dart' as http; // 用于读取 TXT
import 'dart:convert'; // 用于解码 TXT
import 'dart:io'; // 用于下载临时文件 (如果需要)
import 'package:path_provider/path_provider.dart'; // 用于获取临时目录
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart'; // 导入 Chewie
// 假设这些在别处定义
import 'config.dart';
import 'FileService.dart';
import 'dart:async';
import 'package:photo_view/photo_view.dart';
import 'dart:math'; // <--- 添加这行

// 添加文件类型判断方法
bool isImageFile(String? format) {
  if (format == null) return false;
  return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp']
      .contains(format.toLowerCase());
}

bool isVideoFile(String? format) {
  if (format == null) return false;
  return ['mp4', 'mov', 'avi', 'mkv', 'flv', 'wmv']
      .contains(format.toLowerCase());
}

// 图片预览组件
class PhotoViewGalleryScreen extends StatelessWidget {
  final String imageUrl;

  const PhotoViewGalleryScreen({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: PhotoView(
        imageProvider: NetworkImage(imageUrl),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 2,
      ),
    );
  }
}

// --- 新增：区分文档和音频类型 ---
bool isDocumentFile(String? format) {
  if (format == null) return false;
  final lower = format.toLowerCase();
  // 包含常见的可预览或尝试打开的文档类型
  return ['pdf', 'txt', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'epub']
      .contains(lower);
}

bool isAudioFile(String? format) {
  if (format == null) return false;
  // just_audio 支持很多格式
  return ['mp3', 'wav', 'aac', 'ogg', 'm4a', 'flac']
      .contains(format.toLowerCase());
}

// --- 修改后的预览方法 ---
void previewFile(BuildContext context, Map<String, dynamic> file) async {
  // 使用传递的 ownerId (来自 SharePreviewPage) 或当前用户的 ID (来自 FilePage)
  //final userId = file['user_id'];
  final userId = await FileService.getUserId();
  final int? fileId = file['id'];
  int? physicalfileid = file['physical_file_id'];
  final String? filePath = file['path']?.toString();
  final String format = (file['format'] ?? '').toString().toLowerCase();
  final String fileName = file['name']?.toString() ?? '未知文件'; // 获取文件名

// 如果 physicalfileid 为空，则使用 fileId 作为替代

  physicalfileid ??= fileId;

  if (userId == null ||
      filePath == null ||
      filePath.isEmpty ||
      physicalfileid == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('无法获取预览所需信息')),
    );
    return;
  }

  // 构建文件访问 URL
  // final fileUrlString =
  //     '${Config.baseUrl}/get_file?user_id=$userId&file_path=${Uri.encodeComponent(filePath)}';
  final fileUrlString =
      '${Config.baseUrl}/get_file?user_id=$userId&file_id=$fileId&physical_file_id=$physicalfileid&file_path=${Uri.encodeComponent(filePath!)}';

  print("Attempting to access file via URL: $fileUrlString");

  Uri? fileUri;
  try {
    fileUri = Uri.parse(fileUrlString);
  } catch (e) {
    print("Error parsing URL: $fileUrlString, Error: $e");
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('无法解析文件链接')));
    return;
  }

  // --- 根据文件类型进行预览 ---

  if (isImageFile(format)) {
    print("Navigating to Image Preview");
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => PhotoViewGalleryScreen(imageUrl: fileUrlString)),
    );
  } else if (isVideoFile(format)) {
    print("Navigating to Video Preview");
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => VideoPreviewScreen(
              videoUrl: fileUrlString, title: fileName)), // 传递标题
    );
  } else if (format == 'pdf') {
    print("Navigating to PDF Preview");
    // PDF 通常需要先下载到本地临时文件才能预览
    _downloadAndPreviewPdf(context, fileUri, fileName);
  } else if (format == 'txt') {
    print("Attempting to preview TXT");
    _previewTxt(context, fileUri, fileName);
  } else if (isAudioFile(format)) {
    print("Navigating to Audio Player");
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) =>
              AudioPlayerScreen(audioUrl: fileUrlString, title: fileName)),
    );
  } else if (isDocumentFile(format)) {
    // 其他文档类型 (Word, Excel, PPT, EPUB...)
    print("Attempting to launch external app for Document: $format");
    _launchExternalApp(context, fileUri);
  } else {
    // 其他未知类型
    print("Attempting to launch external app for Unknown Type: $format");
    _launchExternalApp(context, fileUri);
  }
}

// --- 辅助方法：启动外部应用 ---
Future<void> _launchExternalApp(BuildContext context, Uri fileUri) async {
  if (await canLaunchUrl(fileUri)) {
    try {
      await launchUrl(fileUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      print("Error launching URL: $fileUri, Error: $e");
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('启动外部应用失败: $e')));
    }
  } else {
    print('Cannot launch URL: $fileUri');
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('未找到可打开此文件类型的应用')));
  }
}

// --- 辅助方法：下载并预览 PDF ---
Future<void> _downloadAndPreviewPdf(
    BuildContext context, Uri fileUri, String title) async {
  try {
    // 显示加载指示器
    showDialog(
        context: context,
        builder: (_) => Center(child: CircularProgressIndicator()),
        barrierDismissible: false);

    final response = await http.get(fileUri);
    Navigator.pop(context); // 关闭加载指示器

    if (response.statusCode == 200) {
      // 获取临时目录
      final tempDir = await getTemporaryDirectory();
      final tempPath =
          '${tempDir.path}/${title.replaceAll(RegExp(r'[/\?%*:|"<>]'), '_')}.pdf'; // 清理文件名
      final file = File(tempPath);
      await file.writeAsBytes(response.bodyBytes);
      print("PDF downloaded to temporary path: $tempPath");

      // 跳转到 PDF 预览页面，传递本地文件路径
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PDFScreen(path: tempPath, title: title),
        ),
      );
    } else {
      throw Exception('下载 PDF 失败 (HTTP ${response.statusCode})');
    }
  } catch (e) {
    print("Error downloading or previewing PDF: $e");
    if (Navigator.canPop(context)) Navigator.pop(context); // 确保关闭加载指示器
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('预览 PDF 失败: ${e.toString()}')));
  }
}

// --- 辅助方法：预览 TXT ---
Future<void> _previewTxt(
    BuildContext context, Uri fileUri, String title) async {
  try {
    showDialog(
        context: context,
        builder: (_) => Center(child: CircularProgressIndicator()),
        barrierDismissible: false);
    final response = await http.get(fileUri);
    Navigator.pop(context);

    if (response.statusCode == 200) {
      String content;
      try {
        // 尝试用 UTF-8 解码，如果失败，尝试 Latin1 (或 GBK 如果后端是中文环境)
        content = utf8.decode(response.bodyBytes);
      } catch (_) {
        try {
          content = latin1.decode(response.bodyBytes);
        } catch (e2) {
          print("Failed to decode TXT content: $e2");
          throw Exception("无法解码文本文件内容");
        }
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TxtViewerScreen(content: content, title: title),
        ),
      );
    } else {
      throw Exception('加载 TXT 文件失败 (HTTP ${response.statusCode})');
    }
  } catch (e) {
    print("Error previewing TXT: $e");
    if (Navigator.canPop(context)) Navigator.pop(context);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('预览 TXT 失败: ${e.toString()}')));
  }
}

// --- 新增：PDF 预览屏幕 ---
class PDFScreen extends StatefulWidget {
  final String path;
  final String title;

  const PDFScreen({Key? key, required this.path, required this.title})
      : super(key: key);

  @override
  _PDFScreenState createState() => _PDFScreenState();
}

class _PDFScreenState extends State<PDFScreen> {
  int? pages = 0;
  int? currentPage = 0;
  bool isReady = false;
  String errorMessage = '';
  // 使用 Completer 来获取 Controller
  final Completer<PDFViewController> _controller =
      Completer<PDFViewController>();
  PDFViewController? _pdfViewController; // 或者直接保存 Controller

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        // (可选) 在 AppBar 中显示页码
        actions: <Widget>[
          if (isReady && pages != null && pages! > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Center(child: Text("${currentPage! + 1}/$pages")),
            ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          PDFView(
            filePath: widget.path,
            enableSwipe: true,
            swipeHorizontal: false,
            autoSpacing: false,
            pageFling: true,
            pageSnap: true,
            defaultPage: currentPage!,
            fitPolicy: FitPolicy.BOTH,
            preventLinkNavigation: false,
            onRender: (_pages) {
              if (!mounted) return;
              setState(() {
                pages = _pages;
                isReady = true;
              });
              print("PDF rendered with $pages pages.");
            },
            onError: (error) {
              if (!mounted) return;
              setState(() {
                errorMessage = error.toString();
                isReady = false; // 加载失败
              });
              print("PDFView error: $error");
            },
            onPageError: (page, error) {
              if (!mounted) return;
              setState(() {
                errorMessage = '页面 $page 加载错误: ${error.toString()}';
              });
              print('Page $page error: ${error.toString()}');
            },
            onViewCreated: (PDFViewController pdfViewController) {
              print("PDFView created.");
              // --- 获取 Controller ---
              if (!_controller.isCompleted) {
                _controller.complete(pdfViewController);
              }
              // 或者直接赋值
              // setState(() {
              //    _pdfViewController = pdfViewController;
              // });
              // ----------------------
            },
            onPageChanged: (int? page, int? total) {
              if (!mounted || page == null) return;
              print('page change: $page/$total');
              setState(() {
                currentPage = page;
              });
            },
          ),
          // --- 错误和加载状态显示 ---
          if (errorMessage.isNotEmpty)
            Center(
                child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text("加载 PDF 出错:\n$errorMessage",
                        style: TextStyle(color: Colors.red),
                        textAlign: TextAlign.center)))
          else if (!isReady)
            const Center(child: CircularProgressIndicator()) // 初始加载 PDF 时显示
          // --------------------------
        ],
      ),
      // --- 悬浮按钮，使用 Completer 的 Future ---
      floatingActionButton: FloatingActionButton.extended(
        label: Text("跳至首页"), // 示例
        icon: Icon(Icons.first_page),
        onPressed: () async {
          // 等待 Controller 可用
          if (_controller.isCompleted) {
            final controller = await _controller.future;
            await controller.setPage(0); // 跳转到第一页 (索引为 0)
          } else {
            print("PDF Controller not ready yet.");
          }
          // 或者使用保存的状态变量
          // if (_pdfViewController != null) {
          //    await _pdfViewController!.setPage(0);
          // }
        },
      ),
    );
  }
}

// --- 新增：TXT 预览屏幕 ---
class TxtViewerScreen extends StatelessWidget {
  final String content;
  final String title;

  const TxtViewerScreen({Key? key, required this.content, required this.title})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        // 允许滚动
        padding: const EdgeInsets.all(16.0),
        child: Text(content),
      ),
    );
  }
}

// --- 新增：音频播放屏幕 ---
class AudioPlayerScreen extends StatefulWidget {
  final String audioUrl;
  final String title;

  const AudioPlayerScreen(
      {Key? key, required this.audioUrl, required this.title})
      : super(key: key);

  @override
  _AudioPlayerScreenState createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> {
  late AudioPlayer _player;
  bool _isLoading = true;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _initAudioPlayer();
  }

  Future<void> _initAudioPlayer() async {
    try {
      print("Initializing audio player for URL: ${widget.audioUrl}");
      // 设置 URL 并等待加载完成
      // just_audio 会处理缓冲
      await _player.setUrl(widget.audioUrl);

      _player.playerStateStream.listen((state) {
        if (!mounted) return;
        setState(() {
          _isPlaying = state.playing;
          // 加载完成或可以播放时隐藏加载指示器
          if (state.processingState == ProcessingState.ready ||
              state.processingState == ProcessingState.completed) {
            _isLoading = false;
          } else if (state.processingState == ProcessingState.loading ||
              state.processingState == ProcessingState.buffering) {
            _isLoading = true;
          }
        });
      });

      _player.durationStream.listen((duration) {
        if (!mounted || duration == null) return;
        setState(() {
          _duration = duration;
        });
      });

      _player.positionStream.listen((position) {
        if (!mounted) return;
        setState(() {
          _position = position;
        });
      });

      // 自动播放（可选）
      // _player.play();
    } catch (e) {
      print("Error initializing audio player: $e");
      if (mounted) {
        setState(() {
          _isLoading = false; // 出错也停止加载
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载音频失败: ${e.toString()}')),
        );
      }
    }
  }

  @override
  void dispose() {
    _player.dispose(); // 释放播放器资源
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: _isLoading
            ? CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(widget.title,
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center),
                    SizedBox(height: 40),
                    // 进度条
                    Slider(
                      min: 0,
                      max: _duration.inSeconds.toDouble() + 1.0, // 防止除零
                      value: _position.inSeconds.toDouble().clamp(
                          0, _duration.inSeconds.toDouble()), // 限制 value 范围
                      onChanged: (value) async {
                        final position = Duration(seconds: value.toInt());
                        await _player.seek(position);
                        // 可以选择在拖动结束后再播放
                        // await _player.play();
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_formatDuration(_position)),
                          Text(_formatDuration(_duration)),
                        ],
                      ),
                    ),
                    SizedBox(height: 30),
                    // 播放控制按钮
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          // 减速 (示例)
                          icon: Icon(Icons.fast_rewind),
                          iconSize: 48,
                          onPressed: () => _player.setSpeed(
                              max(0.5, _player.speed - 0.25)), // 减速，最低0.5
                        ),
                        SizedBox(width: 20),
                        IconButton(
                          icon: Icon(_isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled),
                          iconSize: 64,
                          onPressed: () {
                            if (_isPlaying) {
                              _player.pause();
                            } else {
                              _player.play();
                            }
                          },
                        ),
                        SizedBox(width: 20),
                        IconButton(
                          // 加速 (示例)
                          icon: Icon(Icons.fast_forward),
                          iconSize: 48,
                          onPressed: () => _player.setSpeed(
                              min(2.0, _player.speed + 0.25)), // 加速，最高2.0
                        ),
                      ],
                    ),
                    SizedBox(height: 20),
                    // 显示当前播放速度 (示例)
                    StreamBuilder<double>(
                        stream: _player.speedStream,
                        builder: (context, snapshot) => Text(
                            '播放速度: ${snapshot.data?.toStringAsFixed(2) ?? 1.0}x')),
                  ],
                ),
              ),
      ),
    );
  }

  // 格式化 Duration 为 mm:ss
  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}

class VideoPreviewScreen extends StatefulWidget {
  final String videoUrl;
  final String? title; // 可选标题

  const VideoPreviewScreen({Key? key, required this.videoUrl, this.title})
      : super(key: key);

  @override
  _VideoPreviewScreenState createState() => _VideoPreviewScreenState();
}

class _VideoPreviewScreenState extends State<VideoPreviewScreen> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController; // Chewie 控制器，可空
  bool _isLoading = true; // 加载状态
  String? _errorMessage; // 错误信息

  @override
  void initState() {
    super.initState();
    initializePlayer();
  }

  Future<void> initializePlayer() async {
    print("VideoPreviewScreen: Initializing video from ${widget.videoUrl}");
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    Uri? videoUri;
    try {
      videoUri = Uri.parse(widget.videoUrl);
    } catch (e) {
      print("Error parsing video URL: ${widget.videoUrl}, Error: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '无效的视频链接';
        });
      }
      return;
    }

    _videoPlayerController = VideoPlayerController.networkUrl(videoUri);

    try {
      await _videoPlayerController.initialize(); // 等待初始化完成
      _createChewieController(); // 创建 Chewie 控制器
      if (mounted) {
        setState(() {
          _isLoading = false; // 初始化完成，停止加载
        });
      }
    } catch (error) {
      print("Error initializing video player: $error");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '加载视频失败: ${error.toString()}';
        });
      }
    }
  }

  void _createChewieController() {
    // 创建 ChewieController
    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController,
      autoPlay: true, // 自动播放
      //looping: false, // 不循环播放 (可以设为 true)
      // 可以自定义宽高比
      // aspectRatio: 16 / 9,
      // 允许全屏
      allowFullScreen: true,
      // 允许调节播放速度
      //allowPlaybackSpeedChanging: true,
      //playbackSpeeds: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0], // 可选的播放速度
      // 错误构建器
      errorBuilder: (context, errorMessage) {
        return Center(
          child: Text(
            '播放出错: $errorMessage',
            style: TextStyle(color: Colors.white),
          ),
        );
      },
      // 可以自定义占位符
      placeholder: Container(
        color: Colors.black,
      ),
      // 自动初始化
      autoInitialize: true,
    );
    print("Chewie controller created.");
  }

  @override
  void dispose() {
    _videoPlayerController.dispose(); // 释放 video_player 资源
    _chewieController?.dispose(); // 释放 chewie 资源
    print("Video controllers disposed.");
    super.dispose();
  }

  @override
  // Widget build(BuildContext context) {
  //   return Scaffold(
  //     // 如果需要，可以动态显示标题
  //     appBar: AppBar(title: Text(widget.title ?? '视频预览')),
  //     body: Center(
  //       child: _isLoading
  //           ? const CircularProgressIndicator() // 加载中
  //           : _errorMessage != null
  //               ? Text(_errorMessage!,
  //                   style: TextStyle(color: Colors.red)) // 显示错误
  //               : _chewieController != null
  //                   ? Chewie(controller: _chewieController!) // 使用 Chewie Widget
  //                   : const Text('无法加载播放器'), // Chewie 控制器未初始化
  //     ),
  //   );
  // }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? '视频预览')),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : _errorMessage != null
                ? Text(_errorMessage!, style: TextStyle(color: Colors.red))
                : _videoPlayerController
                        .value.isInitialized // 直接检查 video controller
                    ? AspectRatio(
                        // 使用 AspectRatio
                        aspectRatio: _videoPlayerController.value.aspectRatio,
                        child: VideoPlayer(
                            _videoPlayerController), // 直接渲染 VideoPlayer
                      )
                    : const Text('播放器初始化中...'), // 或者其他占位符
      ),
      // 可以添加简单的播放/暂停按钮进行测试
      floatingActionButton: _videoPlayerController.value.isInitialized
          ? FloatingActionButton(
              onPressed: () {
                setState(() {
                  _videoPlayerController.value.isPlaying
                      ? _videoPlayerController.pause()
                      : _videoPlayerController.play();
                });
              },
              child: Icon(
                _videoPlayerController.value.isPlaying
                    ? Icons.pause
                    : Icons.play_arrow,
              ),
            )
          : null,
    );
  }
}
