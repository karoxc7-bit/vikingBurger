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
      Future.delayed(const Duration(milliseconds: 500), _handleAutoPrint);
    }
  }

  /// Auto-print routing:
  /// - If any printer is configured → direct print
  /// - Otherwise (iPrint / thermal app users) → open share sheet
  Future<void> _handleAutoPrint() async {
    if (!mounted) return;
    final customer = await _printerService.getCustomerPrinter();
    final kitchen = await _printerService.getKitchenPrinter();
    if (!mounted) return;
    if (customer != null || kitchen != null) {
      await _printBothReceipts();
    } else {
      _showShareChoiceSheet();
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

  /// Share receipt as a pixel-perfect PNG sized for the thermal printer.
  /// Users then pick iPrint (or any thermal printer app) from the share sheet.
  Future<void> _shareReceiptToPrinterApp({required bool isKitchen}) async {
    setState(() => _isPrinting = true);
    try {
      final box = context.findRenderObject() as RenderBox?;
      await _printerService.shareReceiptAsImage(
        widget.order,
        isKitchen: isKitchen,
        sharePositionOrigin:
            box != null ? box.localToGlobal(Offset.zero) & box.size : null,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'هەڵەیەک ڕوویدا لە هاوبەشکردنی وەسڵ: $e',
              textDirection: TextDirection.rtl,
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
    if (mounted) setState(() => _isPrinting = false);
  }

  void _showShareChoiceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Text(
                  'کام وەسڵ هاوبەش بکرێت؟',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'وەسڵەکە وەک وێنەیەکی شفاف ئامادە دەکرێت و دەتوانیت بینێریت بۆ ئەپی iPrint',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                _buildShareTile(
                  icon: Icons.receipt_long_rounded,
                  title: 'وەصڵی کڕیار',
                  subtitle: 'هەموو کورتەیەکی فرۆشتنەکە',
                  onTap: () {
                    Navigator.pop(ctx);
                    _shareReceiptToPrinterApp(isKitchen: false);
                  },
                ),
                const SizedBox(height: 10),
                _buildShareTile(
                  icon: Icons.restaurant_rounded,
                  title: 'وەصڵی مەتبەخ',
                  subtitle: 'تەنها ئایتمەکان و تێبینییەکان',
                  onTap: () {
                    Navigator.pop(ctx);
                    _shareReceiptToPrinterApp(isKitchen: true);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShareTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFF2A2A2A),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8C00).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    Icon(icon, color: const Color(0xFFFF8C00), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_left_rounded,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
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
                    // Primary action: Share to iPrint (thermal printer app)
                    SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: ElevatedButton.icon(
                        onPressed: _isPrinting ? null : _showShareChoiceSheet,
                        icon: _isPrinting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.ios_share_rounded, size: 22),
                        label: const Text(
                          'هاوبەشکردن بۆ پرینتەر (iPrint)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF8C00),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Secondary: Direct print (for configured printers)
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _isPrinting ? null : _printBothReceipts,
                        icon: const Icon(Icons.print_rounded, size: 20),
                        label: const Text(
                          'پرینتی ڕاستەوخۆ',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2A2A2A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Individual print buttons
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: OutlinedButton.icon(
                              onPressed: _isPrinting ? null : _printCustomerOnly,
                              icon: const Icon(Icons.receipt_long_rounded, size: 16),
                              label: const Text(
                                'کڕیار',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white70,
                                side: const BorderSide(color: Colors.white24, width: 1.2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: OutlinedButton.icon(
                              onPressed: _isPrinting ? null : _printKitchenOnly,
                              icon: const Icon(Icons.restaurant_rounded, size: 16),
                              label: const Text(
                                'مەتبەخ',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white70,
                                side: const BorderSide(color: Colors.white24, width: 1.2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
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
