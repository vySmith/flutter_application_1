import 'package:flutter/material.dart';
import 'upload_page.dart'; // 导入上传页面
import 'config.dart'; // 替换 your_project_name 为你的项目名
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart'; // 导入 shared_preferences
import 'upload_photo_page.dart'; // Assuming this exists or remove if not used
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:photo_view/photo_view.dart';
// import 'package:photo_view/photo_view_gallery.dart'; // Not used in PhotoViewGalleryScreen currently
import 'FileService.dart'; // Assuming your FileService is correctly defined here
// For robust date formatting, add intl package: flutter pub add intl
// import 'package:intl/intl.dart';

// --- Helper Functions ---

bool isImageFile(String? format) {
  if (format == null) return false;
  // Consider adding more image types if needed (svg, tiff, etc.)
  return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp']
      .contains(format.toLowerCase());
}

bool isVideoFile(String? format) {
  if (format == null) return false;
  return ['mp4', 'mov', 'avi', 'mkv', 'flv', 'wmv']
      .contains(format.toLowerCase());
}

// --- Preview Widgets ---

// 图片预览组件
class PhotoViewGalleryScreen extends StatelessWidget {
  final String imageUrl;

  const PhotoViewGalleryScreen({Key? key, required this.imageUrl})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    print("PhotoViewGalleryScreen: Loading image from $imageUrl");
    return Scaffold(
      appBar: AppBar(),
      body: PhotoView(
        imageProvider:
            NetworkImage(imageUrl), // NetworkImage handles String URL
        loadingBuilder: (context, event) => Center(
          // Added Loading Indicator
          child: CircularProgressIndicator(
            value: event == null || event.expectedTotalBytes == null
                ? null
                : event.cumulativeBytesLoaded / event.expectedTotalBytes!,
          ),
        ),
        errorBuilder: (context, error, stackTrace) => Center(
            // Added Error Indicator
            child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image, color: Colors.red, size: 50),
            SizedBox(height: 10),
            Text('无法加载图片', style: TextStyle(color: Colors.red)),
          ],
        )),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 2,
      ),
    );
  }
}

// 视频预览组件
class VideoPreviewScreen extends StatefulWidget {
  final String videoUrl; // Still receives String URL

  const VideoPreviewScreen({Key? key, required this.videoUrl})
      : super(key: key);

  @override
  _VideoPreviewScreenState createState() => _VideoPreviewScreenState();
}

class _VideoPreviewScreenState extends State<VideoPreviewScreen> {
  late VideoPlayerController _controller;
  bool _initialized = false; // Flag for initialization state
  bool _hasError = false; // Flag for errors

  @override
  void initState() {
    super.initState();
    print(
        "VideoPreviewScreen initState: Initializing video from ${widget.videoUrl}");
    Uri? videoUri;
    try {
      videoUri = Uri.parse(widget.videoUrl); // Parse Uri
    } catch (e) {
      print("Error parsing video URL: ${widget.videoUrl}, Error: $e");
      if (mounted) {
        // Check if widget is still in the tree
        setState(() {
          _hasError = true; // Mark error state
        });
      }
      return; // Stop initialization if URL is invalid
    }

    // Use networkUrl and pass Uri
    _controller = VideoPlayerController.networkUrl(videoUri)
      ..initialize().then((_) {
        // Initialization successful
        print("Video player initialized successfully.");
        if (mounted) {
          setState(() {
            _initialized = true;
            _hasError = false;
          });
          _controller.play(); // Start playback
          _controller.setLooping(true); // Optionally loop
        }
      }).catchError((error) {
        // Initialization failed
        print("Error initializing video player: $error");
        if (mounted) {
          setState(() {
            _initialized = false; // Ensure initialized is false
            _hasError = true; // Mark error state
          });
        }
      });
  }

  @override
  void dispose() {
    print("Disposing video controller.");
    _controller.dispose(); // Very important: release resources
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("视频预览")), // Added title
      body: Center(
        child: _hasError // If there was an error
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, color: Colors.red, size: 50),
                  SizedBox(height: 10),
                  Text('无法加载视频', style: TextStyle(color: Colors.red)),
                  SizedBox(height: 5),
                  Text('请检查网络连接或文件链接', style: TextStyle(fontSize: 12)),
                ],
              )
            : _initialized // If initialized successfully
                ? AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller), // Show the video player
                  )
                : CircularProgressIndicator(), // Show loading indicator
      ),
      floatingActionButton: _initialized // Show FAB only when initialized
          ? FloatingActionButton(
              onPressed: () {
                if (mounted) {
                  setState(() {
                    _controller.value.isPlaying
                        ? _controller.pause()
                        : _controller.play();
                  });
                }
              },
              child: Icon(
                _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
            )
          : null, // No button if not initialized
    );
  }
}

// --- File Page Widget ---

class FilePage extends StatefulWidget {
  final String path; // Current path, defaults to root
  const FilePage({Key? key, this.path = '/'}) : super(key: key);

  @override
  _FilePageState createState() => _FilePageState();
}

class _FilePageState extends State<FilePage> {
  final TextEditingController _searchController = TextEditingController();
  String _sortBy = '文件名'; // Default sort order
  List<Map<String, dynamic>> _allFiles = []; // Full list of files
  List<Map<String, dynamic>> _filteredFiles =
      []; // Files displayed (after filtering/search)
  bool _isLoading = true; // Loading state
  String? _userId; // User ID

  // Selection state variables
  Set<String> _selectedFiles = {}; // Stores selected file IDs (as Strings)
  bool _isSelectionMode = false; // Tracks if selection mode is active

  @override
  void initState() {
    super.initState();
    _fetchFileList(); // Load file list on init
  }

  // Exit selection mode and clear selections
  void _exitSelectionMode() {
    if (!mounted) return;
    setState(() {
      _isSelectionMode = false;
      _selectedFiles.clear();
    });
  }

  // Toggle selecting/deselecting all *visible* files
  void _toggleSelectAll() {
    //if (!mounted) return;
    setState(() {
      // Important: Operate only on the currently visible/filtered files
      final allVisibleFileIds =
          _filteredFiles.map((f) => f['id'].toString()).toSet();
      if (_selectedFiles.length == allVisibleFileIds.length) {
        // If all visible are selected, deselect all
        _selectedFiles.clear();
      } else {
        // Otherwise, select all visible
        _selectedFiles = allVisibleFileIds;
      }
    });
  }

  // Helper to build action buttons in the bottom bar
  Widget _buildActionButton(
      IconData icon, String label, VoidCallback onPressed) {
    return InkWell(
      // Use InkWell for better visual feedback
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24), // Slightly larger icon
            SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  // Fetch file list from the service
  Future<void> _fetchFileList() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      // Assume FileService handles getting userId internally if needed or pass it
      final files = await FileService.getFileList(
        path: widget.path,
        sortBy: _sortBy, // Pass sorting preference
      );
      // Get userId separately or ensure FileService provides it if needed for URLs
      final userId = await FileService.getUserId(); // Assuming this exists

      if (!mounted) return;
      setState(() {
        _userId = userId; // Store userId
        _allFiles = files;
        // Apply search filter immediately if search text exists
        _applySearchFilter();
        _isLoading = false;
      });
    } catch (e) {
      print("Error fetching file list: $e"); // Log error
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载文件列表失败: ${e.toString()}')),
      );
      setState(
          () => _isLoading = false); // Ensure loading state is reset on error
    }
  }

  // Apply search filter based on _searchController text
  void _applySearchFilter() {
    final searchTerm = _searchController.text.toLowerCase();
    if (!mounted) return;
    setState(() {
      if (searchTerm.isEmpty) {
        _filteredFiles = List.from(_allFiles); // Show all if search is empty
      } else {
        _filteredFiles = _allFiles.where((file) {
          final fileName = file['name']?.toString().toLowerCase() ?? '';
          return fileName.contains(searchTerm);
        }).toList();
      }
      // If in selection mode, ensure selected files still exist in the filtered list
      if (_isSelectionMode) {
        final visibleFileIds =
            _filteredFiles.map((f) => f['id'].toString()).toSet();
        _selectedFiles.removeWhere((id) => !visibleFileIds.contains(id));
      }
    });
  }

  // Toggle selection state for a single file
  void _toggleFileSelection(Map<String, dynamic> file) {
    if (!mounted) return;
    final fileId = file['id']?.toString(); // Use null-safe access
    if (fileId == null) return; // Do nothing if ID is missing

    setState(() {
      if (_selectedFiles.contains(fileId)) {
        _selectedFiles.remove(fileId);
        // Option: Exit selection mode if last item is deselected
        // if (_selectedFiles.isEmpty) _exitSelectionMode();
      } else {
        _selectedFiles.add(fileId);
        // Ensure selection mode is active (should already be, but safe)
        // _isSelectionMode = true;
      }
    });
  }

  // Enter selection mode when a file is long-pressed
  void _enterSelectionMode(Map<String, dynamic> initialFile) {
    if (!mounted) return;
    final fileId = initialFile['id']?.toString();
    if (fileId == null) return;

    setState(() {
      _isSelectionMode = true;
      _selectedFiles.clear(); // Start fresh
      _selectedFiles.add(fileId); // Select the long-pressed file
    });
  }

  // Build the main file list view
  Widget _buildFileList() {
    if (_filteredFiles.isEmpty && !_isLoading) {
      return Center(child: Text('此文件夹为空或无搜索结果'));
    }

    return ListView.builder(
      itemCount: _filteredFiles.length,
      itemBuilder: (context, index) {
        final file = _filteredFiles[index];
        final fileId = file['id']?.toString();
        final isSelected = fileId != null && _selectedFiles.contains(fileId);

        // Determine the leading icon
        Widget leadingIcon;
        if (isImageFile(file['format'])) {
          final imageUrl =
              '${Config.baseUrl}/get_file?user_id=$_userId&file_path=${Uri.encodeComponent(file['path'] ?? '')}';
          leadingIcon = Image.network(
            imageUrl,
            width: 50, // Slightly smaller thumbnail
            height: 50,
            fit: BoxFit.cover,
            // Provide hints for caching smaller images
            cacheWidth:
                80, // Request slightly larger for better quality if device pixel ratio > 1
            cacheHeight: 80,
            errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.image,
                size: 40), // Default image icon on error
          );
        } else if (file['type'] == 'folder') {
          leadingIcon = const Icon(Icons.folder,
              size: 40, color: Colors.orangeAccent); // Colored folder
        } else {
          leadingIcon = const Icon(Icons.insert_drive_file,
              size: 40, color: Colors.grey); // Default file icon
        }

        // Format date string (basic, consider using intl package for better formatting)
        String formattedDate = '未知日期';
        if (file['updated_at'] != null) {
          try {
            // Attempt to parse and format, fallback to toString
            DateTime dt = DateTime.parse(file['updated_at'].toString());
            // formattedDate = DateFormat('yyyy-MM-dd HH:mm').format(dt); // Example using intl
            formattedDate = dt
                .toLocal()
                .toString()
                .substring(0, 16); // Basic local time string
          } catch (e) {
            formattedDate = file['updated_at'].toString(); // Fallback
          }
        }

        return ListTile(
          key: ValueKey(fileId ?? index), // *** BUG FIX: Add unique key ***
          leading: leadingIcon,
          title: Text(file['name'] ?? '未知名称',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: _isSelectionMode
              ? Checkbox(
                  value: _selectedFiles.contains(file['id'].toString()),
                  onChanged: (_) => _toggleFileSelection(file),
                  activeColor:
                      Theme.of(context).primaryColor, // Use theme color
                )
              : null, // No trailing widget if not in selection mode
          subtitle: Text(
            '大小: ${file['size'] ?? '?'} bytes, 更新于: $formattedDate',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          onTap: () {
            if (_isSelectionMode) {
              _toggleFileSelection(
                  file); // Toggle selection if in selection mode
            } else if (file['type'] == 'folder') {
              // Navigate into folder
              final folderPath = file['path'];
              if (folderPath != null) {
                // Ensure trailing slash for folder navigation consistency
                final nextPath =
                    folderPath.endsWith('/') ? folderPath : '$folderPath/';
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FilePage(path: nextPath),
                  ),
                  // Refresh list when returning from subfolder if needed
                ).then((_) => _fetchFileList()); // Refresh on pop
              }
            } else {
              _previewFile(file);
            }
          },
          onLongPress: () {
            if (!_isSelectionMode) {
              _enterSelectionMode(file); // Enter selection mode on long press
            }
          },
        );
      },
    );
  }

  // Build the default AppBar (search and back button)
  AppBar _buildDefaultAppBar() {
    return AppBar(
      leading: widget.path != '/'
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            )
          : null, // No back button in root
      title: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: '搜索...',
          border: InputBorder.none,
          hintStyle: TextStyle(color: Colors.black),
        ),
        style: TextStyle(color: Colors.black), // Search text color
        onChanged: (value) => _applySearchFilter(), // Filter as user types
      ),
      actions: [
        // Optional: Add a clear search button
        if (_searchController.text.isNotEmpty)
          IconButton(
            icon: Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              _applySearchFilter();
            },
          ),
      ],
    );
  }

  // Build the AppBar used during selection mode
  AppBar _buildSelectionAppBar() {
    return AppBar(
      leading: IconButton(
        icon: Icon(Icons.close),
        onPressed: _exitSelectionMode, // Button to exit selection mode
      ),
      title: Text('已选择 ${_selectedFiles.length} 项'),
      actions: [
        IconButton(
          // Icon changes based on whether all visible items are selected
          icon: Icon(_selectedFiles.isNotEmpty &&
                      _selectedFiles.length == _filteredFiles.length
                  ? Icons.check_box // All visible selected
                  : Icons
                      .check_box_outline_blank // Not all selected or none selected
              ),
          tooltip: "全选/取消全选",
          onPressed: _toggleSelectAll, // Toggle select all visible files
        ),
      ],
    );
  }

  // Build the bottom action bar shown during selection mode
  Widget _buildBottomActionBar() {
    // Disable buttons if nothing is selected (shouldn't happen if bar is shown, but safe)
    final bool enableActions = _selectedFiles.isNotEmpty;

    return BottomAppBar(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Example Actions: Add more as needed (Download, Share, Move, Rename)
          _buildActionButton(
              Icons.download, '下载', enableActions ? _handleDownload : () {}),
          _buildActionButton(
              Icons.share, '分享', enableActions ? _handleShare : () {}),
          _buildActionButton(Icons.delete_outline, '删除',
              enableActions ? _handleDelete : () {}), // Use outline icon
          _buildActionButton(Icons.drive_file_move_outline, '移动',
              enableActions ? _handleMove : () {}),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          _isSelectionMode ? _buildSelectionAppBar() : _buildDefaultAppBar(),
      body: RefreshIndicator(
        // Added pull-to-refresh
        onRefresh: _fetchFileList, // Refresh action re-fetches the list
        child: Column(
          children: [
            // Consider making the function bar optional or placed differently
            // buildFunctionBar(), // This was the sort/filter bar
            // File list takes remaining space
            Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildFileList() // Display the file list or empty message
                )
          ],
        ),
      ),
      bottomNavigationBar: _isSelectionMode
          ? _buildBottomActionBar()
          : null, // Show bottom bar only in selection mode
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Show options for adding content
          showModalBottomSheet(
            context: context,
            builder: (context) =>
                _buildAddContentSheet(), // Extracted sheet content
          );
        },
        child: const Icon(Icons.add),
        tooltip: '添加内容', // Added tooltip
      ),
    );
  }

  // Extracted BottomSheet content for clarity
  Widget _buildAddContentSheet() {
    return Wrap(
      // Use Wrap for better layout if many items
      children: [
        ListTile(
          leading:
              const Icon(Icons.photo_library_outlined), // Use outlined icons
          title: const Text('上传照片'),
          onTap: () => _handleUpload('photo'),
        ),
        ListTile(
          leading: const Icon(Icons.video_library_outlined),
          title: const Text('上传视频'),
          onTap: () => _handleUpload('video'),
        ),
        ListTile(
          leading: const Icon(Icons.file_present_outlined),
          title: const Text('上传文档'),
          onTap: () => _handleUpload('document'),
        ),
        ListTile(
          leading: const Icon(Icons.audiotrack_outlined),
          title: const Text('上传音频'),
          onTap: () => _handleUpload('audio'),
        ),
        ListTile(
          leading: const Icon(Icons.upload_file_outlined),
          title: const Text('上传其他文件'),
          onTap: () => _handleUpload('other'),
        ),
        Divider(), // Separator
        ListTile(
          leading: const Icon(Icons.create_new_folder_outlined),
          title: const Text('创建文件夹'),
          onTap: () {
            Navigator.pop(context); // Close sheet first
            _showCreateFolderDialog(); // Then show dialog
          },
        ),
        // ListTile( // Example for future feature
        //   leading: const Icon(Icons.note_add_outlined),
        //   title: const Text('新建笔记'),
        //   onTap: () {
        //     Navigator.pop(context);
        //     // TODO: Implement note creation
        //   },
        // ),
      ],
    );
  }

  // Common handler for Upload actions
  Future<void> _handleUpload(String uploadType) async {
    Navigator.pop(context); // Close bottom sheet
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            UploadPage(uploadType: uploadType, currentPath: widget.path),
      ),
    );
    // If UploadPage returns true, refresh the list
    if (result == true && mounted) {
      _fetchFileList();
    }
  }

  // --- Action Handlers ---

  // Preview file (Image, Video, or launch external)
  void _previewFile(Map<String, dynamic> file) async {
    if (_userId == null || file['path'] == null) {
      print("Error: Missing userId or file path for preview.");
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('无法获取文件预览链接')));
      return;
    }

    final String filePath = file['path'];
    final fileUrlString =
        '${Config.baseUrl}/get_file?user_id=$_userId&file_path=${Uri.encodeComponent(filePath)}';

    print('Attempting to preview: $fileUrlString');

    Uri? fileUri;
    try {
      fileUri = Uri.parse(fileUrlString);
    } catch (e) {
      print("Error parsing URL: $fileUrlString, Error: $e");
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('无法解析文件链接')));
      return;
    }

    final String format = (file['format'] ?? '').toString().toLowerCase();

    if (isImageFile(format)) {
      // Image Preview
      print('Navigating to PhotoViewGalleryScreen for image');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PhotoViewGalleryScreen(imageUrl: fileUrlString),
        ),
      );
    } else if (isVideoFile(format)) {
      // Video Preview
      print('Navigating to VideoPreviewScreen for video');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoPreviewScreen(videoUrl: fileUrlString),
        ),
      );
    } else {
      // Other files: attempt to launch external app
      print('Attempting to launch external app for: $fileUri');
      if (await canLaunchUrl(fileUri)) {
        // Use updated API
        try {
          await launchUrl(fileUri,
              mode: LaunchMode.externalApplication); // Use updated API
        } catch (e) {
          print("Error launching URL: $fileUri, Error: $e");
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('启动外部应用失败: $e')));
        }
      } else {
        print('Cannot launch URL: $fileUri');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法找到应用打开此文件类型')));
      }
    }
  }

  // Show the dialog to create a new folder
  Future<void> _showCreateFolderDialog() async {
    final folderNameController = TextEditingController(); // Use a controller
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // User must tap button
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('创建新文件夹'),
          content: TextField(
            controller: folderNameController, // Bind controller
            autofocus: true, // Focus on the field immediately
            decoration: const InputDecoration(
              hintText: '文件夹名称',
            ),
            onSubmitted: (_) => _submitCreateFolder(folderNameController.text
                .trim()), // Allow submitting with Enter key
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('取消'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('创建'),
              onPressed: () =>
                  _submitCreateFolder(folderNameController.text.trim()),
            ),
          ],
        );
      },
    );
  }

  // Action to submit folder creation
  void _submitCreateFolder(String folderName) {
    Navigator.of(context).pop(); // Close the dialog
    if (folderName.isNotEmpty) {
      _createFolder(folderName); // Call the creation function
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('文件夹名称不能为空')),
      );
    }
  }

  // Call the service to create a folder
  Future<void> _createFolder(String folderName) async {
    // Basic validation: Check for invalid characters like '/'
    if (folderName.contains('/')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('文件夹名称不能包含 "/"')),
      );
      return;
    }

    setState(() => _isLoading = true); // Show loading indicator
    try {
      await FileService.createFolder(
        path: widget
            .path, // The current directory where the new folder should be created
        folderName: folderName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('文件夹 "$folderName" 创建成功')),
      );
      await _fetchFileList(); // Refresh list to show the new folder
    } catch (e) {
      print("Error creating folder: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        // Provide more specific error if FileService returns meaningful messages
        SnackBar(content: Text('创建文件夹失败: ${e.toString()}')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Placeholder/Example handlers for bottom actions
  void _handleDownload() async {
    if (_selectedFiles.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('开始下载 ${_selectedFiles.length} 个文件... (未实现)')));
    // TODO: Implement download logic
    // - Iterate through _selectedFiles
    // - Get file path for each ID
    // - Call FileService.getDownloadUrl or similar
    // - Use url_launcher or flutter_downloader package
    _exitSelectionMode(); // Exit mode after initiating action
  }

  void _handleShare() async {
    if (_selectedFiles.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享 ${_selectedFiles.length} 个文件... (未实现)')));
    // TODO: Implement sharing logic
    // - May involve getting shareable links from backend or using `share_plus` package
    _exitSelectionMode();
  }

  void _handleMove() async {
    if (_selectedFiles.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('移动 ${_selectedFiles.length} 个文件... (未实现)')));
    // TODO: Implement move logic
    // - Show a folder picker dialog
    // - Call FileService.moveFiles(fileIds: _selectedFiles, destinationPath: ...)
    _exitSelectionMode();
  }

  // Handle deleting selected files
  void _handleDelete() async {
    if (_selectedFiles.isEmpty) return;

    // Confirm deletion with the user
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text(
            '确定要将选中的 ${_selectedFiles.length} 个文件移至回收站吗? (7天后自动清除)'), // Updated message
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, false), // Return false on Cancel
            child: const Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor: Colors.red), // Destructive action color
            onPressed: () => Navigator.pop(ctx, true), // Return true on Confirm
            child: const Text('确定删除'),
          ),
        ],
      ),
    );

    // If user didn't confirm, do nothing
    if (confirm != true) return;

    setState(() => _isLoading = true); // Show loading indicator during delete
    int successCount = 0;
    int failCount = 0;

    try {
      // Create a list of delete operations to run concurrently
      final List<Future> deleteTasks = [];
      final List<String> pathsToDelete = [];

      for (final fileId in _selectedFiles) {
        // Find the file details from the full list using the ID
        final file = _allFiles.firstWhere(
          (f) => f['id']?.toString() == fileId,
          orElse: () => <String, dynamic>{}, // Return empty map if not found
        );

        final filePath = file['path'] as String?; // Safely cast path

        if (filePath != null) {
          pathsToDelete
              .add(filePath); // Add path for batch deletion if API supports it
          // Or add individual delete tasks:
          // deleteTasks.add(FileService.deleteFile(filePath: filePath));
        } else {
          print("Warning: Could not find path for file ID $fileId to delete.");
          failCount++; // Count files that couldn't be found
        }
      }

      // --- Choose ONE deletion strategy ---
      // Strategy 1: Batch delete if your API supports it (preferred)
      if (pathsToDelete.isNotEmpty) {
        // Assuming FileService has a batch delete method
        // await FileService.deleteFilesBatch(filePaths: pathsToDelete);
        // For now, we simulate individual calls for the existing FileService.deleteFile
        for (final path in pathsToDelete) {
          try {
            await FileService.deleteFile(filePath: path);
            successCount++;
          } catch (e) {
            print("Failed to delete $path: $e");
            failCount++;
          }
        }
      }

      // Strategy 2: Individual concurrent deletion (if no batch API)
      // await Future.wait(deleteTasks); // This doesn't easily allow counting success/fail
    } catch (e) {
      // Catch potential errors during the process (e.g., network)
      print("Error during delete process: $e");
      failCount = _selectedFiles.length - successCount; // Estimate failures
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除操作时发生错误: ${e.toString()}')),
      );
    } finally {
      if (!mounted) return;
      // Show summary message
      String message = '';
      if (successCount > 0) message += '$successCount 个文件已移至回收站。';
      if (failCount > 0) message += '$failCount 个文件删除失败。';
      if (message.isEmpty)
        message = '未执行删除操作。'; // Should not happen if confirm was true

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );

      _isLoading = false; // Hide loading indicator
      _exitSelectionMode(); // Exit selection mode regardless of outcome
      await _fetchFileList(); // Refresh the file list
    }
  }

  // --- (Optional) Sorting/Filtering Bar ---
  // Consider if this UI is necessary or if sorting/filtering can be done via menus
  /*
  Widget buildFunctionBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          DropdownButton<String>(
            value: _sortBy,
            items: ['打开时间', '修改时间', '文件名', '文件类型', '文件大小'] // Add actual sort keys if needed
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (value) {
               if (value != null) {
                   setState(() => _sortBy = value);
                   _fetchFileList(); // Re-fetch with new sort order
               }
            },
          ),
          IconButton(
            icon: Icon(Icons.filter_list),
            tooltip: "筛选",
            onPressed: () {
              // TODO: Implement filter dialog
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('筛选功能未实现')));
            },
          ),
        ],
      ),
    );
  }
  */
} // End of _FilePageState
