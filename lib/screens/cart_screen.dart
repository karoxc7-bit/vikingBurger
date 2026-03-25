import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/order.dart';
import '../database/database_helper.dart';
import '../utils/formatters.dart';
import 'receipt_screen.dart';

class CartScreen extends StatefulWidget {
  final List<OrderItem> cartItems;
  final Order? existingOrder; // If editing an existing order

  const CartScreen({super.key, required this.cartItems, this.existingOrder});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool _isProcessing = false;
  final _discountController = TextEditingController();
  double _discount = 0;
  bool _autoPrint = true;

  bool get _isEditing => widget.existingOrder != null;

  double get _totalPrice =>
      widget.cartItems.fold(0, (sum, item) => sum + item.totalPrice);

  int get _totalItems =>
      widget.cartItems.fold(0, (sum, item) => sum + item.quantity);

  double get _finalPrice {
    final result = _totalPrice - _discount;
    return result > 0 ? result : 0;
  }

  @override
  void initState() {
    super.initState();
    if (widget.existingOrder != null) {
      _discount = widget.existingOrder!.discount;
      if (_discount > 0) {
        _discountController.text = formatPrice(_discount);
      }
    }
  }

  @override
  void dispose() {
    _discountController.dispose();
    super.dispose();
  }

  void _incrementItem(OrderItem item) {
    setState(() => item.quantity++);
  }

  void _decrementItem(OrderItem item) {
    setState(() {
      if (item.quantity > 1) {
        item.quantity--;
      } else {
        widget.cartItems.remove(item);
      }
    });
  }

  void _updateDiscount(String value) {
    final plain = value.replaceAll(',', '');
    setState(() {
      _discount = double.tryParse(plain) ?? 0;
    });
  }

  Future<void> _completeSale() async {
    if (widget.cartItems.isEmpty) return;

    setState(() => _isProcessing = true);

    try {
      final order = Order(
        id: widget.existingOrder?.id,
        items: List.from(widget.cartItems),
        totalPrice: _totalPrice,
        discount: _discount,
        finalPrice: _finalPrice,
        createdAt: widget.existingOrder?.createdAt,
      );

      if (_isEditing) {
        await DatabaseHelper().updateOrder(order);
      } else {
        await DatabaseHelper().insertOrder(order);
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ReceiptScreen(order: order, autoPrint: _autoPrint),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('هەڵەیەک ڕوویدا: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(
            _isEditing ? 'دەستکاریکردنی داواکاری' : 'سەبەتەی فرۆشتن',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            if (_isEditing)
              TextButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.add_rounded, size: 20, color: Color(0xFFFF8C00)),
                label: const Text('ئایتم زیادبکە', style: TextStyle(color: Color(0xFFFF8C00), fontSize: 13)),
              ),
            if (widget.cartItems.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF1E1E1E),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      title: const Text(
                        'بەتاڵکردنەوەی سەبەتە',
                        style: TextStyle(color: Colors.white),
                      ),
                      content: Text(
                        'دڵنیایت لە بەتاڵکردنەوەی سەبەتەکە؟',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text(
                            'نەخێر',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() => widget.cartItems.clear());
                            Navigator.pop(ctx);
                          },
                          child: const Text(
                            'بەڵێ',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
        body: widget.cartItems.isEmpty
            ? _buildEmptyCart()
            : Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      physics: const BouncingScrollPhysics(),
                      itemCount: widget.cartItems.length,
                      itemBuilder: (context, index) {
                        return _buildCartItem(widget.cartItems[index], index);
                      },
                    ),
                  ),
                  _buildCheckoutBar(),
                ],
              ),
      ),
    );
  }

  Widget _buildEmptyCart() {
    return Center(
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
              Icons.shopping_cart_outlined,
              size: 64,
              color: Colors.orange.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'سەبەتەکە بەتاڵە',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ئایتمێک زیاد بکە بۆ سەبەتەی فرۆشتن',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItem(OrderItem item, int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 60)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(30 * (1 - value), 0),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: Row(
          children: [
            // Image
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 60,
                height: 60,
                child: item.imagePath != null &&
                        File(item.imagePath!).existsSync()
                    ? Image.file(
                        File(item.imagePath!),
                        fit: BoxFit.cover,
                      )
                    : Container(
                        color: const Color(0xFF2A2A2A),
                        child: Icon(
                          Icons.fastfood_rounded,
                          color: Colors.orange.withValues(alpha: 0.4),
                          size: 28,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // Name & Price
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${formatPrice(item.price)} IQD',
                    style: TextStyle(
                      color: const Color(0xFFFF8C00).withValues(alpha: 0.8),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            // Quantity controls
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildQtyButton(
                    icon: item.quantity > 1
                        ? Icons.remove_rounded
                        : Icons.delete_outline_rounded,
                    color: item.quantity > 1
                        ? Colors.white
                        : Colors.redAccent,
                    onTap: () => _decrementItem(item),
                  ),
                  Container(
                    constraints: const BoxConstraints(minWidth: 36),
                    alignment: Alignment.center,
                    child: Text(
                      '${item.quantity}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _buildQtyButton(
                    icon: Icons.add_rounded,
                    color: const Color(0xFFFF8C00),
                    onTap: () => _incrementItem(item),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQtyButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }

  Widget _buildCheckoutBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Subtotal
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'کۆی نرخەکان ($_totalItems ئایتم)',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
              ),
              Text(
                '${formatPrice(_totalPrice)} IQD',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Discount input
          Row(
            children: [
              const Icon(Icons.discount_rounded, color: Colors.greenAccent, size: 18),
              const SizedBox(width: 8),
              const Text(
                'داشکاندن',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _discountController,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                    onChanged: _updateDiscount,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      PriceInputFormatter(),
                    ],
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: '0',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF2A2A2A),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      suffixText: 'IQD',
                      suffixStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Show discount amount
          if (_discount > 0) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'داشکاندن',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '- ${formatPrice(_discount)} IQD',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          // Final total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'نرخی کۆتایی',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${formatPrice(_finalPrice)} IQD',
                style: const TextStyle(
                  color: Color(0xFFFF8C00),
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Print toggle
          GestureDetector(
            onTap: () => setState(() => _autoPrint = !_autoPrint),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _autoPrint
                    ? const Color(0xFFFF8C00).withValues(alpha: 0.12)
                    : const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _autoPrint
                      ? const Color(0xFFFF8C00).withValues(alpha: 0.4)
                      : Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _autoPrint ? Icons.print_rounded : Icons.print_disabled_rounded,
                    color: _autoPrint ? const Color(0xFFFF8C00) : Colors.white38,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'پرێنت لەگەڵ فرۆشتنەکە',
                      style: TextStyle(
                        color: _autoPrint ? Colors.white : Colors.white54,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 24,
                    width: 42,
                    child: Switch(
                      value: _autoPrint,
                      onChanged: (v) => setState(() => _autoPrint = v),
                      activeThumbColor: const Color(0xFFFF8C00),
                      activeTrackColor: const Color(0xFFFF8C00).withValues(alpha: 0.35),
                      inactiveThumbColor: Colors.white38,
                      inactiveTrackColor: Colors.white12,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Checkout button
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _completeSale,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF8C00),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: _isProcessing
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'تەواوکردنی فرۆشتن',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
