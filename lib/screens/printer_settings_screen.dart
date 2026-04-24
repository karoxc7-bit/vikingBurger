import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../services/printer_service.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen>
    with SingleTickerProviderStateMixin {
  final _printerService = PrinterService();
  SavedPrinter? _customerPrinter;
  SavedPrinter? _kitchenPrinter;
  bool _isLoading = true;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _loadPrinters();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadPrinters() async {
    final customer = await _printerService.getCustomerPrinter();
    final kitchen = await _printerService.getKitchenPrinter();
    setState(() {
      _customerPrinter = customer;
      _kitchenPrinter = kitchen;
      _isLoading = false;
    });
    _animController.forward();
  }

  // Show choice: System printer or Network printer
  Future<void> _selectPrinter(bool isCustomer) async {
    if (!mounted) return;

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            isCustomer ? 'پرینتەری کڕیار زیاد بکە' : 'پرینتەری مەتبەخ زیاد بکە',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'چۆن دەتەوێت پرینتەرەکە زیاد بکەیت؟',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 20),
              _buildChoiceButton(
                icon: Icons.bluetooth_rounded,
                title: 'پرینتەری بلوتوس',
                subtitle: 'پەیوەندی بە بلوتوس',
                color: const Color(0xFF42A5F5),
                onTap: () => Navigator.pop(ctx, 'bluetooth'),
              ),
              const SizedBox(height: 10),
              _buildChoiceButton(
                icon: Icons.wifi_rounded,
                title: 'پرینتەری نێتوەرک (WiFi)',
                subtitle: 'بە IP ناونیشان',
                color: const Color(0xFF2196F3),
                onTap: () => Navigator.pop(ctx, 'network'),
              ),
              const SizedBox(height: 10),
              _buildChoiceButton(
                icon: Icons.print_rounded,
                title: 'پرینتەری سیستەم',
                subtitle: 'USB / پرینتەری داگیرکراو',
                color: const Color(0xFF4CAF50),
                onTap: () => Navigator.pop(ctx, 'system'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('پاشگەزبوونەوە', style: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
      ),
    );

    if (choice == null || !mounted) return;

    if (choice == 'bluetooth') {
      await _addBluetoothPrinter(isCustomer);
    } else if (choice == 'network') {
      await _addNetworkPrinter(isCustomer);
    } else {
      await _addSystemPrinter(isCustomer);
    }
  }

  Widget _buildChoiceButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: Colors.white.withValues(alpha: 0.3), size: 16),
          ],
        ),
      ),
    );
  }

  // ===== Bluetooth printer =====
  Future<void> _addBluetoothPrinter(bool isCustomer) async {
    if (!mounted) return;

    // Show scanning dialog — scan runs while dialog is open
    final selected = await showDialog<BluetoothInfo>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _BluetoothScanDialog(
        title: isCustomer ? 'پرینتەری کڕیار هەڵبژێرە' : 'پرینتەری مەتبەخ هەڵبژێرە',
        printerService: _printerService,
      ),
    );

    if (selected == null || !mounted) return;

    // Test connection
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Row(
            children: [
              const CircularProgressIndicator(color: Color(0xFFFF8C00)),
              const SizedBox(width: 16),
              Text(
                'پەیوەندی دەکرێت...',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
              ),
            ],
          ),
        ),
      ),
    );

    final ok = await _printerService.testBluetoothPrinter(selected.macAdress);
    if (mounted) Navigator.pop(context);

    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('نەتوانرا پەیوەندی بکرێت. دڵنیا بە کە پرینتەرەکە چالاکە و جووتکراوە.', textDirection: TextDirection.rtl),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return;
    }

    final saved = SavedPrinter(
      name: selected.name.isNotEmpty ? selected.name : 'بلوتوس',
      address: selected.macAdress,
      type: PrinterConnectionType.bluetooth,
    );

    if (isCustomer) {
      await _printerService.saveCustomerPrinter(saved);
      setState(() => _customerPrinter = saved);
    } else {
      await _printerService.saveKitchenPrinter(saved);
      setState(() => _kitchenPrinter = saved);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('پرینتەری ${isCustomer ? "کڕیار" : "مەتبەخ"} بە بلوتوس بەسترا', textDirection: TextDirection.rtl),
          backgroundColor: const Color(0xFF2E7D32),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  // ===== Network printer (IP) =====
  Future<void> _addNetworkPrinter(bool isCustomer) async {
    final ipController = TextEditingController();
    final portController = TextEditingController(text: '9100');

    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('پرینتەری نێتوەرک', style: TextStyle(color: Colors.white, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'IP ناونیشانی پرینتەرەکە بنووسە',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ipController,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2),
                decoration: InputDecoration(
                  hintText: '192.168.1.100',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 16),
                  labelText: 'IP',
                  labelStyle: const TextStyle(color: Color(0xFFFF8C00)),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFFF8C00))),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: portController,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  labelText: 'پۆرت (ئاسایی: 9100)',
                  labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFFF8C00))),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('پاشگەزبوونەوە', style: TextStyle(color: Colors.white54)),
            ),
            StatefulBuilder(
              builder: (context, setButtonState) {
                bool isTesting = false;
                return TextButton(
                  // ignore: dead_code
                  onPressed: isTesting ? null : () async {
                    final ip = ipController.text.trim();
                    final port = int.tryParse(portController.text.trim()) ?? 9100;
                    if (ip.isEmpty) return;

                    setButtonState(() => isTesting = true);
                    final ok = await PrinterService().testNetworkPrinter(ip, port);
                    setButtonState(() => isTesting = false);

                    if (ok) {
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } else {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: const Text('نەتوانرا پەیوەندی بکرێت بە پرینتەرەوە. IP و پۆرتەکە بپشکنە.', textDirection: TextDirection.rtl),
                            backgroundColor: Colors.red.shade700,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        );
                      }
                    }
                  },
                  child: isTesting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Color(0xFFFF8C00), strokeWidth: 2))
                      : const Text('تاقیکردنەوە و زیادکردن', style: TextStyle(color: Color(0xFFFF8C00), fontWeight: FontWeight.bold)),
                );
              },
            ),
          ],
        ),
      ),
    );

    if (result != true) return;

    final ip = ipController.text.trim();
    final port = portController.text.trim();
    final address = '$ip:$port';
    final saved = SavedPrinter(name: 'نێتوەرک ($ip)', address: address, type: PrinterConnectionType.network);

    if (isCustomer) {
      await _printerService.saveCustomerPrinter(saved);
      setState(() => _customerPrinter = saved);
    } else {
      await _printerService.saveKitchenPrinter(saved);
      setState(() => _kitchenPrinter = saved);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('پرینتەری ${isCustomer ? "کڕیار" : "مەتبەخ"} دیاریکرا: $ip', textDirection: TextDirection.rtl),
          backgroundColor: const Color(0xFF2E7D32),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }

    ipController.dispose();
    portController.dispose();
  }

  // ===== System printer =====
  Future<void> _addSystemPrinter(bool isCustomer) async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFFFF8C00))),
    );

    final printers = await _printerService.getSystemPrinters();

    if (mounted) Navigator.pop(context);

    if (printers.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'هیچ پرینتەری سیستەمێک نەدۆزرایەوە.\nبۆ موبایل/تابلێت بەشی "پرینتەری نێتوەرک" بەکاربهێنە.',
              textDirection: TextDirection.rtl,
            ),
            backgroundColor: Colors.orange.shade800,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    final selected = await showDialog<Printer>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            isCustomer ? 'پرینتەری کڕیار هەڵبژێرە' : 'پرینتەری مەتبەخ هەڵبژێرە',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: printers.length,
              itemBuilder: (context, index) {
                final printer = printers[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.print_rounded, color: Colors.white54),
                    title: Text(printer.name, style: const TextStyle(color: Colors.white, fontSize: 14)),
                    subtitle: printer.isAvailable
                        ? const Text('ئامادەیە', style: TextStyle(color: Colors.green, fontSize: 11))
                        : const Text('ئامادە نییە', style: TextStyle(color: Colors.red, fontSize: 11)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onTap: () => Navigator.pop(ctx, printer),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('پاشگەزبوونەوە', style: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
      ),
    );

    if (selected == null) return;

    final saved = SavedPrinter(name: selected.name, address: selected.url, type: PrinterConnectionType.system);

    if (isCustomer) {
      await _printerService.saveCustomerPrinter(saved);
      setState(() => _customerPrinter = saved);
    } else {
      await _printerService.saveKitchenPrinter(saved);
      setState(() => _kitchenPrinter = saved);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('پرینتەری ${isCustomer ? "کڕیار" : "مەتبەخ"} دیاریکرا: ${selected.name}', textDirection: TextDirection.rtl),
          backgroundColor: const Color(0xFF2E7D32),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _clearPrinter(bool isCustomer) async {
    if (isCustomer) {
      await _printerService.clearCustomerPrinter();
      setState(() => _customerPrinter = null);
    } else {
      await _printerService.clearKitchenPrinter();
      setState(() => _kitchenPrinter = null);
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
          title: const Text(
            'ڕێکخستنی پرینتەر',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFFF8C00)),
              )
            : FadeTransition(
                opacity: _fadeAnim,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Info card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFFF8C00).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF8C00).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.info_outline_rounded,
                                color: Color(0xFFFF8C00),
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                'دوو پرینتەر دیاری بکە.\n'
                                '• بۆ موبایل/تابلێت: بە IP ناونیشانی پرینتەر لە WiFi\n'
                                '• بۆ کۆمپیوتەر: پرینتەری سیستەم (USB)',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 12,
                                  height: 1.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Customer Printer
                      _buildPrinterCard(
                        title: 'پرینتەری کڕیار',
                        subtitle: 'وەصڵی فرۆشتن بۆ کڕیار پرینت دەکات',
                        icon: Icons.receipt_long_rounded,
                        color: const Color(0xFF4CAF50),
                        printer: _customerPrinter,
                        onSelect: () => _selectPrinter(true),
                        onClear: () => _clearPrinter(true),
                      ),

                      const SizedBox(height: 16),

                      // Kitchen Printer
                      _buildPrinterCard(
                        title: 'پرینتەری مەتبەخ',
                        subtitle: 'لیستی داواکاری بۆ مەتبەخ پرینت دەکات',
                        icon: Icons.restaurant_rounded,
                        color: const Color(0xFFFF5722),
                        printer: _kitchenPrinter,
                        onSelect: () => _selectPrinter(false),
                        onClear: () => _clearPrinter(false),
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildPrinterCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required SavedPrinter? printer,
    required VoidCallback onSelect,
    required VoidCallback onClear,
  }) {
    final isConnected = printer != null;
    IconData connectionIcon;
    switch (printer?.type) {
      case PrinterConnectionType.bluetooth:
        connectionIcon = Icons.bluetooth_rounded;
        break;
      case PrinterConnectionType.network:
        connectionIcon = Icons.wifi_rounded;
        break;
      default:
        connectionIcon = Icons.usb_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isConnected
              ? color.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Status indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isConnected
                      ? color.withValues(alpha: 0.15)
                      : const Color(0xFF333333),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isConnected ? color : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isConnected ? 'دیاریکراو' : 'نەکراو',
                      style: TextStyle(
                        color: isConnected ? color : Colors.grey,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (isConnected) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(connectionIcon,
                      color: Colors.white.withValues(alpha: 0.5), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          printer.name,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          printer.type == PrinterConnectionType.network
                              ? printer.address
                              : printer.type == PrinterConnectionType.bluetooth
                                  ? 'بلوتوس'
                                  : 'سیستەم',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: onClear,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.close_rounded,
                          color: Colors.redAccent, size: 16),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: onSelect,
              icon: Icon(
                  isConnected ? Icons.swap_horiz_rounded : Icons.add_rounded,
                  size: 20),
              label: Text(
                isConnected ? 'گۆڕینی پرینتەر' : 'دیاریکردنی پرینتەر',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: color.withValues(alpha: 0.2),
                foregroundColor: color,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bluetooth Scan Dialog ───────────────────────────────────────────────────

class _BluetoothScanDialog extends StatefulWidget {
  final String title;
  final PrinterService printerService;

  const _BluetoothScanDialog({
    required this.title,
    required this.printerService,
  });

  @override
  State<_BluetoothScanDialog> createState() => _BluetoothScanDialogState();
}

class _BluetoothScanDialogState extends State<_BluetoothScanDialog>
    with SingleTickerProviderStateMixin {
  final List<BluetoothInfo> _found = [];
  bool _scanning = true;
  String _statusMsg = 'بەدوادا دەگەڕێت...';
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scan();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    // Check BT enabled
    final enabled = await widget.printerService.isBluetoothEnabled();
    if (!enabled) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _statusMsg = 'بلوتوسەکەت چالاک نییە. تکایە لە ڕێکخستنەکانی مۆبایل چالاکی بکە.';
        });
      }
      return;
    }

    // First scan pass
    final devices = await widget.printerService.getBluetoothDevices();
    if (mounted) {
      setState(() {
        for (final d in devices) {
          if (!_found.any((f) => f.macAdress == d.macAdress)) {
            _found.add(d);
          }
        }
      });
    }

    // Wait 2 more seconds and scan again (iOS BLE needs time)
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final devices2 = await widget.printerService.getBluetoothDevices();
    if (mounted) {
      setState(() {
        for (final d in devices2) {
          if (!_found.any((f) => f.macAdress == d.macAdress)) {
            _found.add(d);
          }
        }
        _scanning = false;
        _statusMsg = _found.isEmpty
            ? 'هیچ پرینتەرێک نەدۆزرایەوە.\nدڵنیا بە پرینتەرەکەت چالاکە و نزیکە.'
            : '${_found.length} ئامێر دۆزرایەوە';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            if (_scanning)
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) => Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(left: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.lerp(
                        const Color(0xFF42A5F5), Colors.transparent, _pulse.value),
                  ),
                ),
              )
            else
              const Icon(Icons.bluetooth_rounded,
                  color: Color(0xFF42A5F5), size: 18),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                widget.title,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status row
              Row(
                children: [
                  if (_scanning)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          color: Color(0xFFFF8C00), strokeWidth: 2),
                    ),
                  if (_scanning) const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusMsg,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (!_scanning && _found.isEmpty)
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _scanning = true;
                          _statusMsg = 'بەدوادا دەگەڕێت...';
                        });
                        _scan();
                      },
                      icon: const Icon(Icons.refresh_rounded,
                          size: 16, color: Color(0xFFFF8C00)),
                      label: const Text('دووبارە',
                          style: TextStyle(
                              color: Color(0xFFFF8C00), fontSize: 12)),
                    ),
                ],
              ),
              if (_found.isNotEmpty) ...[
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _found.length,
                    itemBuilder: (_, i) {
                      final d = _found[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2A2A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xFF42A5F5).withValues(alpha: 0.2)),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF42A5F5).withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.print_rounded,
                                color: Color(0xFF42A5F5), size: 20),
                          ),
                          title: Text(
                            d.name.isNotEmpty ? d.name : 'پرینتەری نەناسراو',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            d.macAdress,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.35),
                                fontSize: 11),
                          ),
                          trailing: const Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: Color(0xFFFF8C00),
                            size: 14,
                          ),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          onTap: () => Navigator.pop(context, d),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('پاشگەزبوونەوە',
                style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }
}
