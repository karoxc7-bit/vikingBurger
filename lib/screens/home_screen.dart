import 'package:flutter/material.dart';
import '../models/menu_item.dart';
import '../models/order.dart';
import '../database/database_helper.dart';
import '../widgets/menu_item_card.dart';
import 'add_edit_item_screen.dart';
import 'item_detail_screen.dart';
import 'cart_screen.dart';
import 'sales_history_screen.dart';

class HomeScreen extends StatefulWidget {
  final List<OrderItem>? initialCartItems;
  final Order? existingOrder;

  const HomeScreen({super.key, this.initialCartItems, this.existingOrder});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  List<MenuItem> _items = [];
  bool _isLoading = true;
  late AnimationController _fabController;

  // Cart state
  final List<OrderItem> _cartItems = [];
  Order? _existingOrder;

  // Scroll-to-hide header
  final ScrollController _scrollController = ScrollController();
  double _headerOffset = 0.0; // 0 = fully visible, 1 = fully hidden
  double _lastScrollPos = 0.0;
  static const double _headerHeight = 64.0;

  // Add-to-cart animation
  final GlobalKey _cartIconKey = GlobalKey();

  int get _cartItemCount =>
      _cartItems.fold(0, (sum, item) => sum + item.quantity);

  @override
  void initState() {
    super.initState();
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    if (widget.initialCartItems != null) {
      _cartItems.addAll(widget.initialCartItems!);
    }
    _existingOrder = widget.existingOrder;

    _scrollController.addListener(_onScroll);
    _loadItems();
  }

  @override
  void dispose() {
    _fabController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final current = _scrollController.offset;
    final delta = current - _lastScrollPos;
    _lastScrollPos = current;

    setState(() {
      _headerOffset = (_headerOffset + delta / _headerHeight).clamp(0.0, 1.0);
      // Snap fully visible when near top
      if (current <= 10) _headerOffset = 0.0;
    });
  }

  Future<void> _loadItems() async {
    setState(() => _isLoading = true);
    try {
      final items = await DatabaseHelper().getAllItems();
      setState(() {
        _items = items;
        _isLoading = false;
      });
      _fabController.forward();
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _addToCart(MenuItem item, [GlobalKey? cardKey]) {
    setState(() {
      final existing = _cartItems.where((ci) => ci.menuItemId == item.id);
      if (existing.isNotEmpty) {
        existing.first.quantity++;
      } else {
        _cartItems.add(OrderItem(
          menuItemId: item.id,
          name: item.name,
          price: item.price,
          imagePath: item.imagePath,
        ));
      }
    });

    // Fly animation from card to cart icon
    if (cardKey != null) {
      _animateFlyToCart(cardKey);
    }

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '"${item.name}" زیادکرا بۆ سەبەتە',
          style: TextStyle(color: Colors.white),
          textDirection: TextDirection.rtl,
        ),
        backgroundColor: const Color(0xFF2A2A2A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _animateFlyToCart(GlobalKey cardKey) {
    final cardBox = cardKey.currentContext?.findRenderObject() as RenderBox?;
    final cartBox = _cartIconKey.currentContext?.findRenderObject() as RenderBox?;
    if (cardBox == null || cartBox == null) return;

    final overlay = Overlay.of(context);
    final startPos = cardBox.localToGlobal(Offset(cardBox.size.width / 2, 0));
    final endPos = cartBox.localToGlobal(Offset(cartBox.size.width / 2, cartBox.size.height / 2));

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    final curve = CurvedAnimation(parent: controller, curve: Curves.easeInCubic);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => AnimatedBuilder(
        animation: curve,
        builder: (_, _) {
          final t = curve.value;
          final x = startPos.dx + (endPos.dx - startPos.dx) * t;
          final y = startPos.dy + (endPos.dy - startPos.dy) * t - 40 * (1 - t) * t * 4;
          final scale = 1.0 - t * 0.6;
          final opacity = 1.0 - t * 0.5;
          return Positioned(
            left: x - 14,
            top: y - 14,
            child: Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF8C00),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add_rounded, color: Colors.white, size: 16),
                ),
              ),
            ),
          );
        },
      ),
    );

    overlay.insert(entry);
    controller.forward().then((_) {
      entry.remove();
      controller.dispose();
    });
  }

  Future<void> _openCart() async {
    final result = await Navigator.push<bool>(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            CartScreen(cartItems: _cartItems, existingOrder: _existingOrder),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
    // result is null when cart used pushReplacement to receipt (sale completed)
    // result is false when user pressed back from cart
    if (result == null) {
      // Came back from receipt — sale was completed, clear cart
      setState(() {
        _cartItems.clear();
        _existingOrder = null;
      });
      // If this was an edit session opened from sales history, go back
      if (widget.existingOrder != null && mounted) {
        Navigator.pop(context);
      }
    } else {
      // Cart modified (items removed etc.), refresh UI
      setState(() {});
    }
  }

  void _openSalesHistory() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const SalesHistoryScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  Future<void> _addItem() async {
    final result = await Navigator.push<bool>(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const AddEditItemScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
    if (result == true) _loadItems();
  }

  Future<void> _viewItem(MenuItem item) async {
    final result = await Navigator.push<bool>(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            ItemDetailScreen(item: item),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
    if (result == true) _loadItems();
  }

  void _deleteItem(MenuItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'ڕەشکردنەوە',
          style: TextStyle(color: Colors.white),
          textDirection: TextDirection.rtl,
        ),
        content: Text(
          'دڵنیایت لە ڕەشکردنەوەی "${item.name}"؟',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('نەخێر', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              await DatabaseHelper().deleteItem(item.id);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              _loadItems();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '"${item.name}" ڕەشکرایەوە',
                      textDirection: TextDirection.rtl,
                    ),
                    backgroundColor: const Color(0xFF2A2A2A),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              }
            },
            child: const Text(
              'بەڵێ، بیسڕەوە',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerIconButton({
    required IconData icon,
    required VoidCallback onTap,
    bool isAccent = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: isAccent ? null : const Color(0xFF1E1E1E),
          gradient: isAccent
              ? const LinearGradient(colors: [Color(0xFFFF8C00), Color(0xFFFF5722)])
              : null,
          borderRadius: BorderRadius.circular(11),
          border: isAccent
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Icon(icon, color: isAccent ? Colors.white : Colors.white70, size: 19),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            // Header - animated hide on scroll
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              height: _headerHeight * (1 - _headerOffset),
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Row(
                    children: [
                      // Branding (LTR so Viking Burger reads correctly)
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'V',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: const Color.fromARGB(255, 255, 140, 0),
                                shadows: [
                                  Shadow(
                                    color: const Color(0xFFFF8C00).withValues(alpha: 0.5),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                            ),
                            const Text(
                              'iking',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              'Burger',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w400,
                                color: Color(0xFFFF8C00),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Add item
                      _headerIconButton(
                        icon: Icons.add_rounded,
                        onTap: _addItem,
                        isAccent: true,
                      ),
                      const SizedBox(width: 6),
                      // Sales history
                      _headerIconButton(
                        icon: Icons.receipt_long_rounded,
                        onTap: _openSalesHistory,
                      ),
                      const SizedBox(width: 6),
                      // Cart with badge
                      GestureDetector(
                        key: _cartIconKey,
                        onTap: _openCart,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1E1E),
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                              child: const Icon(
                                Icons.shopping_cart_rounded,
                                color: Colors.white70,
                                size: 19,
                              ),
                            ),
                            if (_cartItemCount > 0)
                              Positioned(
                                top: -5,
                                left: -5,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  constraints: const BoxConstraints(minWidth: 17),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFFF5722),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '$_cartItemCount',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Content
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFFF8C00),
                      ),
                    )
                  : _items.isEmpty
                  ? _buildEmptyState()
                  : _buildGrid(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 30 * (1 - value)),
              child: child,
            ),
          );
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Icon(
                Icons.fastfood_rounded,
                size: 64,
                color: Colors.orange.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'هیچ ئایتمێک نییە',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'ئایتمی نوێ زیاد بکە بۆ لیستی خواردنەکانت',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = 2;
        if (constraints.maxWidth > 900) {
          crossAxisCount = 4;
        } else if (constraints.maxWidth > 600) {
          crossAxisCount = 3;
        }

        return GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          physics: const BouncingScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.75,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
          ),
          itemCount: _items.length,
          itemBuilder: (context, index) {
            final item = _items[index];
            final cardKey = GlobalKey();
            return TweenAnimationBuilder<double>(
              key: ValueKey(item.id),
              tween: Tween(begin: 0.0, end: 1.0),
              duration: Duration(milliseconds: 400 + (index * 80)),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 30 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: MenuItemCard(
                key: cardKey,
                item: item,
                index: index,
                onTap: () => _viewItem(item),
                onDelete: () => _deleteItem(item),
                onAddToCart: () => _addToCart(item, cardKey),
              ),
            );
          },
        );
      },
    );
  }
}
