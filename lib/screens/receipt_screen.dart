import 'package:flutter/material.dart';
import '../models/order.dart';
import '../utils/formatters.dart';
import '../services/printer_service.dart';

class ReceiptScreen extends StatefulWidget {
  final Order order;
  final bool autoPrint;

  const ReceiptScreen({super.key, required this.order, this.autoPrint = false});

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen>
    with SingleTickerProviderStateMixin {
  final _printerService = PrinterService();
  bool _isPrinting = false;
  late AnimationController _printAnimController;
  late Animation<double> _printBounce;

  @override
  void initState() {
    super.initState();
    _printAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _printBounce = CurvedAnimation(
      parent: _printAnimController,
      curve: Curves.elasticOut,
    );
    _printAnimController.forward();

    if (widget.autoPrint) {
      // Auto-print after a short delay for the UI to settle
      Future.delayed(const Duration(milliseconds: 500), _printBothReceipts);
    }
  }

  @override
  void dispose() {
    _printAnimController.dispose();
    super.dispose();
  }

  Future<void> _printBothReceipts() async {
    setState(() => _isPrinting = true);
    final result = await _printerService.printBoth(widget.order);
    if (mounted) {
      setState(() => _isPrinting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.message,
            textDirection: TextDirection.rtl,
          ),
          backgroundColor:
              result.success ? const Color(0xFF2E7D32) : Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _printCustomerOnly() async {
    setState(() => _isPrinting = true);
    try {
      await _printerService.printCustomerWithDialog(widget.order);
    } catch (_) {}
    if (mounted) setState(() => _isPrinting = false);
  }

  Future<void> _printKitchenOnly() async {
    setState(() => _isPrinting = true);
    try {
      await _printerService.printKitchenWithDialog(widget.order);
    } catch (_) {}
    if (mounted) setState(() => _isPrinting = false);
  }

  String _formatDate(DateTime date) {
    final months = [
      'کانوونی دووەم', 'شوبات', 'ئازار', 'نیسان',
      'ئایار', 'حوزەیران', 'تەمووز', 'ئاب',
      'ئەیلوول', 'تشرینی یەکەم', 'تشرینی دووەم', 'کانوونی یەکەم',
    ];
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${date.day} ${months[date.month - 1]} ${date.year}\n$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final itemCount = order.items.fold<int>(0, (sum, i) => sum + i.quantity);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text(
            'وەصڵی فرۆشتن',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
              // Receipt card - Black & White design for thermal printer preview
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Header - Black & White
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: const BoxDecoration(
                        color: Color(0xFF3A3A3A),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                      child: const Column(
                        children: [
                          Text(
                            'Viking Burger',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'ئەربیل - بەحرکە - شەقامی گشتی',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                          SizedBox(height: 2),
                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: Text(
                              '0750 348 5909',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (order.isDelivery)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 14, left: 20, right: 20),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFF666666), width: 1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Center(
                          child: Text(
                            '*** دلیڤەری ***',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                    // Date & order info
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'بەروار',
                                style: TextStyle(
                                  color: Color(0xFF666666),
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatDate(order.createdAt),
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'ژمارەی ئایتم',
                                style: TextStyle(
                                  color: Color(0xFF666666),
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$itemCount',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Dashed line
                    _buildDashedLine(),

                    // Items header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                      child: Row(
                        children: const [
                          Expanded(
                            flex: 4,
                            child: Text(
                              'ئایتم',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 40,
                            child: Text(
                              'دانە',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              'کۆی گشتی',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Items with notes
                    ...order.items.map((item) => Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    flex: 4,
                                    child: Text(
                                      item.name,
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 40,
                                    child: Text(
                                      '${item.quantity}',
                                      style: const TextStyle(
                                        color: Color(0xFF333333),
                                        fontSize: 13,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      '${formatPrice(item.totalPrice)} IQD',
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      textAlign: TextAlign.end,
                                    ),
                                  ),
                                ],
                              ),
                              // Show note if exists
                              if (item.note != null && item.note!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2, right: 8),
                                  child: Row(
                                    children: [
                                      const Text(
                                        '↳ ',
                                        style: TextStyle(
                                          color: Color(0xFF666666),
                                          fontSize: 11,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          item.note!,
                                          style: const TextStyle(
                                            color: Color(0xFF444444),
                                            fontSize: 11,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        )),

                    const SizedBox(height: 6),
                    _buildDashedLine(),

                    // Totals
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'کۆی نرخەکان',
                            style: TextStyle(
                              color: Color(0xFF333333),
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '${formatPrice(order.totalPrice)} IQD',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Discount (if any)
                    if (order.discount > 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'داشکاندن',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              '- ${formatPrice(order.discount)} IQD',
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 4),
                    _buildDashedLine(),

                    // Final price
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'نرخی کۆتایی',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${formatPrice(order.finalPrice)} IQD',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Bottom decoration
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF0F0F0),
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(4),
                        ),
                      ),
                      child: const Column(
                        children: [
                          Text(
                            'سوپاس بۆ هەڵبژاردنی ئێمە',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'چاوەڕێی گەڕانەوەت دەکەین بۆ تامێکی تایبەت تر',
                            style: TextStyle(
                              color: Color(0xFF555555),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Print buttons
              ScaleTransition(
                scale: _printBounce,
                child: Column(
                  children: [
                    // Print both button
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: _isPrinting ? null : _printBothReceipts,
                        icon: _isPrinting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.print_rounded, size: 22),
                        label: Text(
                          _isPrinting ? 'پرینت دەکرێت...' : 'پرینت بۆ هەردوو پرینتەر',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF333333),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Individual print buttons
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 46,
                            child: OutlinedButton.icon(
                              onPressed: _isPrinting ? null : _printCustomerOnly,
                              icon: const Icon(Icons.receipt_long_rounded, size: 18),
                              label: const Text(
                                'وەصڵی کڕیار',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white70,
                                side: const BorderSide(color: Colors.white30, width: 1.5),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 46,
                            child: OutlinedButton.icon(
                              onPressed: _isPrinting ? null : _printKitchenOnly,
                              icon: const Icon(Icons.restaurant_rounded, size: 18),
                              label: const Text(
                                'وەصڵی مەتبەخ',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white70,
                                side: const BorderSide(color: Colors.white30, width: 1.5),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashedLine() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: List.generate(
          40,
          (index) => Expanded(
            child: Container(
              height: 1,
              color: index.isEven
                  ? const Color(0xFF999999)
                  : Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }
}
