import 'package:uuid/uuid.dart';

class MenuItem {
  final String id;
  final String name;
  final String description;
  final double price;
  final String? imagePath;
  final DateTime createdAt;

  MenuItem({
    String? id,
    required this.name,
    required this.description,
    required this.price,
    this.imagePath,
    DateTime? createdAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'price': price,
      'imagePath': imagePath,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory MenuItem.fromMap(Map<String, dynamic> map) {
    return MenuItem(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String,
      price: (map['price'] as num).toDouble(),
      imagePath: map['imagePath'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  MenuItem copyWith({
    String? name,
    String? description,
    double? price,
    String? imagePath,
    bool clearImage = false,
  }) {
    return MenuItem(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      imagePath: clearImage ? null : (imagePath ?? this.imagePath),
      createdAt: createdAt,
    );
  }
}
