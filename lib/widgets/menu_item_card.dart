import 'dart:io';
import 'package:flutter/material.dart';
import '../models/menu_item.dart';
import '../utils/formatters.dart';

class MenuItemCard extends StatefulWidget {
  final MenuItem item;
  final VoidCallback onAddToCart;
  final VoidCallback onLongPress;
  final int index;

  const MenuItemCard({
    super.key,
    required this.item,
    required this.onAddToCart,
    required this.onLongPress,
    required this.index,
  });

  @override
  State<MenuItemCard> createState() => _MenuItemCardState();
}

class _MenuItemCardState extends State<MenuItemCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(scale: _scaleAnimation.value, child: child);
      },
      child: GestureDetector(
        onTapDown: (_) {
          setState(() => _isPressed = true);
          _controller.forward();
        },
        onTapUp: (_) {
          setState(() => _isPressed = false);
          _controller.reverse();
          widget.onAddToCart();
        },
        onTapCancel: () {
          setState(() => _isPressed = false);
          _controller.reverse();
        },
        onLongPress: () {
          setState(() => _isPressed = false);
          _controller.reverse();
          widget.onLongPress();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: _isPressed
                    ? Colors.orange.withValues(alpha: 0.3)
                    : Colors.black.withValues(alpha: 0.15),
                blurRadius: _isPressed ? 20 : 12,
                offset: const Offset(0, 6),
                spreadRadius: _isPressed ? 2 : 0,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Image area (Top 65%)
                    Expanded(
                      flex: 65,
                      child: Hero(
                        tag: 'item-image-${widget.item.id}',
                        child: _buildImage(),
                      ),
                    ),
                    // Content area (Bottom 35%)
                    Expanded(
                      flex: 45,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        color: const Color(0xFF1E1E1E),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.item.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (widget.item.description.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.item.description,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.6,
                                      ),
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                            // Price
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFFFF8C00,
                                    ).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(
                                        0xFFFF8C00,
                                      ).withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    '${formatPrice(widget.item.price)} IQD',
                                    style: const TextStyle(
                                      color: Color(0xFFFF8C00),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                // Add to cart button
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: const Color(0xFFFF8C00),
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: widget.onAddToCart,
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(
                          Icons.add_shopping_cart_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (widget.item.imagePath != null &&
        File(widget.item.imagePath!).existsSync()) {
      return Container(
        color: const Color(0xFF252525), // Slight background for the image frame
        padding: const EdgeInsets.all(
          12,
        ), // Padding makes the image appear smaller
        child: Image.file(
          File(widget.item.imagePath!),
          fit: BoxFit
              .contain, // Changed from cover to contain to ensure the whole image is visible and scaled down
          errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
        ),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2C2C2C), Color(0xFF1A1A1A)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.fastfood_rounded,
          size: 48,
          color: Colors.orange.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}
