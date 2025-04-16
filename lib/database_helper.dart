import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'transfer_provider.dart'; // 导入 TransferTask

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('transfers.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getApplicationDocumentsDirectory();
    final path = join(dbPath.path, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    const idType = 'TEXT PRIMARY KEY'; // 使用任务 ID 作为主键
    const textType = 'TEXT NOT NULL';
    const intType = 'INTEGER NOT NULL';
    const realType = 'REAL NOT NULL';
    const boolType = 'INTEGER NOT NULL'; // SQLite 没有布尔类型，用 0/1
    const nullableTextType = 'TEXT';

    await db.execute('''
CREATE TABLE transfer_tasks (
  id $idType,
  filePath $textType,
  remotePath $textType,
  fileName $textType,
  totalSize $intType,
  isUpload $boolType,
  progress $realType,
  status $intType,
  errorMessage $nullableTextType
)
''');
    print("Transfer tasks table created.");
  }

  // 插入或更新任务
  Future<int> upsertTask(TransferTask task) async {
    final db = await instance.database;
    // toMap 中 isUpload 已经是 bool，但存储时需要转为 int
    final map = task.toMap();
    map['isUpload'] = task.isUpload ? 1 : 0; // 转换 bool 为 int

    return await db.insert(
      'transfer_tasks',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace, // 如果 ID 已存在则替换
    );
  }

  // 获取所有任务
  Future<List<TransferTask>> getAllTasks() async {
    final db = await instance.database;
    final maps = await db.query('transfer_tasks');

    if (maps.isEmpty) {
      return [];
    }

    return List.generate(maps.length, (i) {
      // 从数据库读取时，需要将 isUpload (int) 转换回 bool
      final map = Map<String, dynamic>.from(maps[i]); // 创建可修改的 Map
      map['isUpload'] = map['isUpload'] == 1; // int 转回 bool
      return TransferTask.fromMap(map);
    });
  }

  // 更新任务进度和状态
  Future<int> updateTaskProgressStatus(
      String id, double progress, TransferStatus status) async {
    final db = await instance.database;
    return await db.update(
      'transfer_tasks',
      {'progress': progress, 'status': status.index},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 更新任务状态和错误信息
  Future<int> updateTaskStatusError(
      String id, TransferStatus status, String? errorMessage) async {
    final db = await instance.database;
    final Map<String, Object?> values = {
      'status': status.index,
      'errorMessage': errorMessage,
    };
    // 如果完成，强制进度为 1.0
    if (status == TransferStatus.completed) {
      values['progress'] = 1.0;
    }
    return await db.update(
      'transfer_tasks',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 删除任务
  Future<int> deleteTask(String id) async {
    final db = await instance.database;
    return await db.delete(
      'transfer_tasks',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 删除所有已完成的任务
  Future<int> deleteCompletedTasks() async {
    final db = await instance.database;
    return await db.delete(
      'transfer_tasks',
      where: 'status = ?',
      whereArgs: [TransferStatus.completed.index],
    );
  }

  // 关闭数据库
  Future close() async {
    final db = await instance.database;
    db.close();
    _database = null; // 重置实例变量
  }
}
