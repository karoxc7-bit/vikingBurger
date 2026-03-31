import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/menu_item.dart';
import '../models/order.dart' as models;

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'viking_burger.db');

    return await openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE menu_items (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT NOT NULL,
            price REAL NOT NULL,
            imagePath TEXT,
            createdAt TEXT NOT NULL
          )
        ''');
        await _createOrderTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createOrderTables(db);
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE orders ADD COLUMN discount REAL NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE orders ADD COLUMN finalPrice REAL NOT NULL DEFAULT 0');
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE order_items ADD COLUMN note TEXT');
        }
      },
    );
  }

  Future<void> _createOrderTables(Database db) async {
    await db.execute('''
      CREATE TABLE orders (
        id TEXT PRIMARY KEY,
        totalPrice REAL NOT NULL,
        discount REAL NOT NULL DEFAULT 0,
        finalPrice REAL NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        orderId TEXT NOT NULL,
        menuItemId TEXT NOT NULL,
        name TEXT NOT NULL,
        price REAL NOT NULL,
        quantity INTEGER NOT NULL,
        imagePath TEXT,
        note TEXT,
        FOREIGN KEY (orderId) REFERENCES orders (id) ON DELETE CASCADE
      )
    ''');
  }

  // ========== Menu Items CRUD ==========

  Future<int> insertItem(MenuItem item) async {
    final db = await database;
    return await db.insert(
      'menu_items',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> updateItem(MenuItem item) async {
    final db = await database;
    return await db.update(
      'menu_items',
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<int> deleteItem(String id) async {
    final db = await database;
    return await db.delete('menu_items', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<MenuItem>> getAllItems() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'menu_items',
      orderBy: 'createdAt DESC',
    );
    return maps.map((map) => MenuItem.fromMap(map)).toList();
  }

  Future<MenuItem?> getItem(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'menu_items',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return MenuItem.fromMap(maps.first);
  }

  // ========== Orders CRUD ==========

  Future<void> insertOrder(models.Order order) async {
    final db = await database;
    await db.insert('orders', order.toMap());
    for (final item in order.items) {
      await db.insert('order_items', item.toMap(order.id));
    }
  }

  Future<List<models.Order>> getAllOrders() async {
    final db = await database;
    final List<Map<String, dynamic>> orderMaps = await db.query(
      'orders',
      orderBy: 'createdAt DESC',
    );

    final List<models.Order> orders = [];
    for (final orderMap in orderMaps) {
      final orderId = orderMap['id'] as String;
      final List<Map<String, dynamic>> itemMaps = await db.query(
        'order_items',
        where: 'orderId = ?',
        whereArgs: [orderId],
      );
      final items = itemMaps.map((m) => models.OrderItem.fromMap(m)).toList();
      orders.add(models.Order.fromMap(orderMap, items));
    }
    return orders;
  }

  Future<int> deleteOrder(String id) async {
    final db = await database;
    await db.delete('order_items', where: 'orderId = ?', whereArgs: [id]);
    return await db.delete('orders', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateOrder(models.Order order) async {
    final db = await database;
    await db.delete('order_items', where: 'orderId = ?', whereArgs: [order.id]);
    await db.update('orders', order.toMap(), where: 'id = ?', whereArgs: [order.id]);
    for (final item in order.items) {
      await db.insert('order_items', item.toMap(order.id));
    }
  }
}
