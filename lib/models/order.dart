import 'package:uuid/uuid.dart';

class OrderItem {
  final String menuItemId;
  final String name;
  final double price;
  final String? imagePath;
  int quantity;
  String? note;

  OrderItem({
    required this.menuItemId,
    required this.name,
    required this.price,
    this.imagePath,
    this.quantity = 1,
    this.note,
  });

  double get totalPrice => price * quantity;

  Map<String, dynamic> toMap(String orderId) {
    return {
      'orderId': orderId,
      'menuItemId': menuItemId,
      'name': name,
      'price': price,
      'quantity': quantity,
      'imagePath': imagePath,
      'note': note,
    };
  }

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      menuItemId: map['menuItemId'] as String,
      name: map['name'] as String,
      price: (map['price'] as num).toDouble(),
      quantity: (map['quantity'] as num).toInt(),
      imagePath: map['imagePath'] as String?,
      note: map['note'] as String?,
    );
  }
}

class Order {
  final String id;
  final List<OrderItem> items;
  final double totalPrice;
  final double discount;
  final double finalPrice;
  final DateTime createdAt;

  Order({
    String? id,
    required this.items,
    required this.totalPrice,
    this.discount = 0,
    double? finalPrice,
    DateTime? createdAt,
  }) : id = id ?? const Uuid().v4(),
       finalPrice = finalPrice ?? (totalPrice - discount),
       createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'totalPrice': totalPrice,
      'discount': discount,
      'finalPrice': finalPrice,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Order.fromMap(Map<String, dynamic> map, List<OrderItem> items) {
    return Order(
      id: map['id'] as String,
      items: items,
      totalPrice: (map['totalPrice'] as num).toDouble(),
      discount: (map['discount'] as num?)?.toDouble() ?? 0,
      finalPrice: (map['finalPrice'] as num?)?.toDouble(),
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}
