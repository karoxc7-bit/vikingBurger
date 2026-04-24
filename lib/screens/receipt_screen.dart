import 'package:flutter/material.dart';
import '../models/order.dart';
import '../utils/formatters.dart';
import '../services/printer_service.dart';
import 'printer_settings_screen.dart';

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
  String _printStatus = '';
  late AnimationController _printAnimController;
  late Animation<double> _printBounce;

  // Cache of printer configuration so the UI can adapt (different button
  // label/color when a BLE printer is paired vs not).
  SavedPrinter? _printer;
  bool _printerLoaded = false;

  bool get _hasPrinter => _printer != null;

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
    _loadPrinterConfig();
  }

  Future<void> _loadPrinterConfig() async {
    final printer = await _printerService.getPrinter();
    if (!mounted) return;
    setState(() {
      _printer = printer;
      _printerLoaded = true;
    });

    if (widget.autoPrint) {
      Future.delayed(const Duration(milliseconds: 400), _handleAutoPrint);
    }
  }

  /// Smart auto-print:
  ///   - Printer configured? → print instantly in place with a nice overlay
  ///   - Otherwise → open the save-to-Photos flow (iPrint compatibility)
  Future<void> _handleAutoPrint() async {
    if (!mounted) return;
    if (_hasPrinter) {
      await _printReceipt();
    } else {
      _saveReceiptToPhotos();
    }
  }

  @override
  void dispose() {
    _printAnimController.dispose();
    super.dispose();
  }

  Future<void> _printReceipt() async {
    setState(() {
      _isPrinting = true;
      _printStatus = 'بەستنەوە بە پرینتەر...';
    });
    // Tiny visual tick so the user sees "connecting" state before we move
    // on to the bytes-over-BLE phase, which can sometimes finish very fast.
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) {
      setState(() => _printStatus = 'ناردنی وەسڵ...');
    }

    final result = await _printerService.printReceipt(widget.order);
    if (mounted) {
      setState(() {
        _isPrinting = false;
        _printStatus = '';
      });
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

  Future<void> _openPrinterSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PrinterSettingsScreen()),
    );
    // Reload the printer config after returning so the UI updates.
    await _loadPrinterConfig();
  }

  /// Save the receipt as a PNG into the "Viking Burger" album in Photos.
  /// Cashier then opens iPrint and picks the latest photo from the album.
  Future<void> _saveReceiptToPhotos() async {
    setState(() => _isPrinting = true);
    try {
      final album = await _printerService.saveReceiptToGallery(widget.order);
      if (mounted) {
        _showSavedDialog(album: album);
      }
    } catch (e) {
      if (!mounted) return;
      final s = e.toString();
      String msg;
      if (s.contains('PHOTO_PERMISSION_DENIED')) {
        msg = 'تکایە ڕێگەی گەیشتن بە وێنەکان بدە لە ڕێکخستنەکانی iPhone';
      } else if (s.contains('PLUGIN_UNAVAILABLE')) {
        msg =
            'پلەگینی پاشەکەوتکردن ئامادە نییە. تکایە ئەپلیکەیشنەکە بە تەواوی دامێزرێنە لەبار (Full Rebuild).';
      } else {
        msg = 'نەتوانرا وێنە پاشەکەوت بکرێت: $e';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, textDirection: TextDirection.rtl),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
    if (mounted) setState(() => _isPrinting = false);
  }

  /// Optional fallback: iOS share sheet (for users who prefer other apps).
  Future<void> _shareReceiptViaSystemSheet() async {
    setState(() => _isPrinting = true);
    try {
      final box = context.findRenderObject() as RenderBox?;
      await _printerService.shareReceiptAsImage(
        widget.order,
        sharePositionOrigin:
            box != null ? box.localToGlobal(Offset.zero) & box.size : null,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'هەڵەیەک ڕوویدا: $e',
              textDirection: TextDirection.rtl,
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
    if (mounted) setState(() => _isPrinting = false);
  }

  /// Success dialog with step-by-step iPrint instructions.
  void _showSavedDialog({required String album}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.check_circle_rounded,
                    color: Colors.greenAccent, size: 26),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'وێنەکە پاشەکەوت کرا',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.photo_library_rounded,
                        color: Color(0xFFFF8C00), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'ئەلبۆم: $album',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'بۆ چاپکردن:',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              _buildStep(1, 'ئەپی iPrint بکەرەوە'),
              _buildStep(2, 'کلیک لەسەر وێنە / Photo بکە'),
              _buildStep(3, 'ئەلبۆمی Viking Burger هەڵبژێرە'),
              _buildStep(4, 'دوایین وێنە هەڵبژێرە و Print بکە'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'باشە',
                style: TextStyle(
                  color: Color(0xFFFF8C00),
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _shareReceiptViaSystemSheet();
              },
              icon: const Icon(Icons.ios_share_rounded,
                  color: Colors.white54, size: 16),
              label: const Text(
                'هاوبەشکردن',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(int num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: const Color(0xFFFF8C00).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$num',
                style: const TextStyle(
                  color: Color(0xFFFF8C00),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
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

              // Smart print area — adapts based on printer config
              ScaleTransition(
                scale: _printBounce,
                child: _buildSmartPrintActions(),
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

  /// Adapts the primary action based on whether a printer is configured.
  /// When paired to BLE printer:
  ///   → Big "Print now" button (one tap, auto-prints both copies)
  /// When no printer:
  ///   → Setup wizard suggestion + Photos fallback
  Widget _buildSmartPrintActions() {
    if (!_printerLoaded) {
      return const SizedBox(
        height: 58,
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFFFF8C00)),
        ),
      );
    }

    if (_hasPrinter) {
      return Column(
        children: [
          // Primary: one-tap direct print
          SizedBox(
            width: double.infinity,
            height: 58,
            child: ElevatedButton.icon(
              onPressed: _isPrinting ? null : _printReceipt,
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
                _isPrinting
                    ? (_printStatus.isNotEmpty
                        ? _printStatus
                        : 'پرینت دەکرێت...')
                    : 'چاپکردنی وەسڵ',
                style: const TextStyle(
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
          // Connected printer chip
          _buildConnectedPrinterChip(),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _isPrinting ? null : _saveReceiptToPhotos,
            icon: const Icon(Icons.photo_library_rounded,
                color: Colors.white38, size: 16),
            label: const Text(
              'پاشەکەوت وەک وێنە',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
        ],
      );
    }

    // No printer configured — promote the one-time setup, with Photos fallback.
    return Column(
      children: [
        // Prominent setup card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFFFF8C00).withValues(alpha: 0.15),
                const Color(0xFFFF8C00).withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFFFF8C00).withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color:
                          const Color(0xFFFF8C00).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded,
                        color: Color(0xFFFF8C00), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'چاپکردنی زیرەک',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'پرینتەرەکەت بە بلوتوس جووت بکە بۆ چاپکردنی ڕاستەوخۆ بێ iPrint',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _openPrinterSettings,
                  icon: const Icon(Icons.bluetooth_searching_rounded, size: 20),
                  label: const Text(
                    'یەک-جار ڕێکخستنی پرینتەر',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8C00),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Separator "or"
        Row(
          children: [
            const Expanded(child: Divider(color: Colors.white12)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('یان',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 11)),
            ),
            const Expanded(child: Divider(color: Colors.white12)),
          ],
        ),
        const SizedBox(height: 14),
        // Photos fallback for iPrint users
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: _isPrinting ? null : _saveReceiptToPhotos,
            icon: const Icon(Icons.photo_library_rounded, size: 18),
            label: const Text(
              'پاشەکەوت لە وێنەکان (بۆ iPrint)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white24, width: 1.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConnectedPrinterChip() {
    if (_printer == null) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: _printerChip(
              icon: Icons.bluetooth_rounded,
              label: _printer!.name,
              color: const Color(0xFF42A5F5)),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: _openPrinterSettings,
          icon: const Icon(Icons.settings_rounded,
              color: Colors.white38, size: 16),
          tooltip: 'ڕێکخستنەکان',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ],
    );
  }

  Widget _printerChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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
