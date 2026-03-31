import 'dart:typed_data';
import 'dart:io';
import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../models/order.dart';
import '../utils/formatters.dart';

enum PrinterConnectionType { system, network, bluetooth }

class SavedPrinter {
  final String name;
  final String address; // URL for system, IP:port for network
  final PrinterConnectionType type;

  SavedPrinter({
    required this.name,
    required this.address,
    required this.type,
  });
}

class PrinterService {
  static final PrinterService _instance = PrinterService._internal();
  factory PrinterService() => _instance;
  PrinterService._internal();

  // Keys for SharedPreferences
  static const _customerNameKey = 'customer_printer_name';
  static const _customerAddressKey = 'customer_printer_address';
  static const _customerTypeKey = 'customer_printer_type';
  static const _kitchenNameKey = 'kitchen_printer_name';
  static const _kitchenAddressKey = 'kitchen_printer_address';
  static const _kitchenTypeKey = 'kitchen_printer_type';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _sharedPrefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ===== Save/Load Printer Config =====

  Future<void> saveCustomerPrinter(SavedPrinter printer) async {
    final prefs = await _sharedPrefs;
    await prefs.setString(_customerNameKey, printer.name);
    await prefs.setString(_customerAddressKey, printer.address);
    await prefs.setString(_customerTypeKey, printer.type.name);
  }

  Future<void> saveKitchenPrinter(SavedPrinter printer) async {
    final prefs = await _sharedPrefs;
    await prefs.setString(_kitchenNameKey, printer.name);
    await prefs.setString(_kitchenAddressKey, printer.address);
    await prefs.setString(_kitchenTypeKey, printer.type.name);
  }

  Future<SavedPrinter?> getCustomerPrinter() async {
    try {
      final prefs = await _sharedPrefs;
      final name = prefs.getString(_customerNameKey);
      final address = prefs.getString(_customerAddressKey);
      final type = prefs.getString(_customerTypeKey);
      if (name == null || address == null) return null;
      return SavedPrinter(
        name: name,
        address: address,
        type: _parseConnectionType(type),
      );
    } catch (_) {
      return null;
    }
  }

  Future<SavedPrinter?> getKitchenPrinter() async {
    try {
      final prefs = await _sharedPrefs;
      final name = prefs.getString(_kitchenNameKey);
      final address = prefs.getString(_kitchenAddressKey);
      final type = prefs.getString(_kitchenTypeKey);
      if (name == null || address == null) return null;
      return SavedPrinter(
        name: name,
        address: address,
        type: _parseConnectionType(type),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clearCustomerPrinter() async {
    final prefs = await _sharedPrefs;
    await prefs.remove(_customerNameKey);
    await prefs.remove(_customerAddressKey);
    await prefs.remove(_customerTypeKey);
  }

  Future<void> clearKitchenPrinter() async {
    final prefs = await _sharedPrefs;
    await prefs.remove(_kitchenNameKey);
    await prefs.remove(_kitchenAddressKey);
    await prefs.remove(_kitchenTypeKey);
  }

  // ===== System Printers (Windows/Desktop) =====

  Future<List<Printer>> getSystemPrinters() async {
    try {
      return await Printing.listPrinters();
    } catch (_) {
      return [];
    }
  }

  static PrinterConnectionType _parseConnectionType(String? type) {
    switch (type) {
      case 'network':
        return PrinterConnectionType.network;
      case 'bluetooth':
        return PrinterConnectionType.bluetooth;
      default:
        return PrinterConnectionType.system;
    }
  }

  // ===== Network Printer Test =====

  Future<bool> testNetworkPrinter(String ip, int port) async {
    try {
      final socket = await Socket.connect(ip, port,
          timeout: const Duration(seconds: 3));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ===== Bluetooth =====

  Future<bool> isBluetoothEnabled() async {
    try {
      return await PrintBluetoothThermal.bluetoothEnabled;
    } catch (_) {
      return false;
    }
  }

  Future<List<BluetoothInfo>> getBluetoothDevices() async {
    try {
      return await PrintBluetoothThermal.pairedBluetooths;
    } catch (_) {
      return [];
    }
  }

  Future<bool> testBluetoothPrinter(String macAddress) async {
    try {
      final connected = await PrintBluetoothThermal.connect(
        macPrinterAddress: macAddress,
      );
      if (connected) {
        await PrintBluetoothThermal.disconnect;
      }
      return connected;
    } catch (_) {
      return false;
    }
  }

  Future<void> _printToBluetooth(String macAddress, List<int> escBytes) async {
    bool isConnected = await PrintBluetoothThermal.connectionStatus;
    if (!isConnected) {
      final connected = await PrintBluetoothThermal.connect(
        macPrinterAddress: macAddress,
      );
      if (!connected) throw Exception('نەتوانرا بەستنەوە بە پرینتەری بلوتوس');
      await Future.delayed(const Duration(milliseconds: 500));
    }
    final result = await PrintBluetoothThermal.writeBytes(Uint8List.fromList(escBytes));
    if (!result) throw Exception('نەتوانرا پرینت بکرێت');
    await PrintBluetoothThermal.disconnect;
  }

  // ===== Print Functions =====

  Future<PrintResult> printBoth(Order order) async {
    final customerPrinter = await getCustomerPrinter();
    final kitchenPrinter = await getKitchenPrinter();

    if (customerPrinter == null && kitchenPrinter == null) {
      return PrintResult(
        success: false,
        message: 'هیچ پرینتەرێک دیاری نەکراوە. تکایە لە ڕێکخستنەکان پرینتەر دیاری بکە.',
      );
    }

    final errors = <String>[];
    int printed = 0;

    // Print customer receipt
    if (customerPrinter != null) {
      try {
        await _printOrder(customerPrinter, order, isKitchen: false);
        printed++;
      } catch (e) {
        errors.add('هەڵەی پرینتی کڕیار: $e');
      }
    }

    // Print kitchen receipt
    if (kitchenPrinter != null) {
      try {
        await _printOrder(kitchenPrinter, order, isKitchen: true);
        printed++;
      } catch (e) {
        errors.add('هەڵەی پرینتی مەتبەخ: $e');
      }
    }

    if (printed > 0 && errors.isEmpty) {
      return PrintResult(
          success: true, message: 'پرینت سەرکەوتوو بوو بۆ هەردوو پرینتەر');
    } else if (printed > 0) {
      return PrintResult(
          success: true,
          message:
              '$printed پرینت سەرکەوتوو. ${errors.join(" | ")}');
    } else {
      return PrintResult(success: false, message: errors.join(' | '));
    }
  }

  Future<void> _printOrder(SavedPrinter saved, Order order, {required bool isKitchen}) async {
    if (saved.type == PrinterConnectionType.bluetooth) {
      final escBytes = isKitchen
          ? _generateKitchenReceiptESC(order)
          : _generateCustomerReceiptESC(order);
      await _printToBluetooth(saved.address, escBytes);
    } else {
      final pdfBytes = isKitchen
          ? await _generateKitchenReceipt(order)
          : await _generateCustomerReceipt(order);
      if (saved.type == PrinterConnectionType.network) {
        await _printToNetwork(saved.address, pdfBytes);
      } else {
        await _printToSystem(saved.address, pdfBytes);
      }
    }
  }

  Future<void> _printToSystem(String printerUrl, Uint8List pdfBytes) async {
    final printers = await Printing.listPrinters();
    final printer = printers.where((p) => p.url == printerUrl).firstOrNull;
    if (printer == null) throw Exception('پرینتەر نەدۆزرایەوە');
    await Printing.directPrintPdf(
      printer: printer,
      onLayout: (_) async => pdfBytes,
    );
  }

  Future<void> _printToNetwork(String address, Uint8List pdfBytes) async {
    // address format: "ip:port"
    final parts = address.split(':');
    final ip = parts[0];
    final port = parts.length > 1 ? int.tryParse(parts[1]) ?? 9100 : 9100;

    final socket = await Socket.connect(ip, port,
        timeout: const Duration(seconds: 5));
    try {
      socket.add(pdfBytes);
      await socket.flush();
    } finally {
      socket.destroy();
    }
  }

  /// Print customer receipt (auto-detects printer type)
  Future<void> printCustomerWithDialog(Order order) async {
    final printer = await getCustomerPrinter();
    if (printer != null && printer.type == PrinterConnectionType.bluetooth) {
      await _printOrder(printer, order, isKitchen: false);
    } else {
      final pdf = await _generateCustomerReceipt(order);
      await Printing.layoutPdf(onLayout: (_) async => pdf);
    }
  }

  /// Print kitchen receipt (auto-detects printer type)
  Future<void> printKitchenWithDialog(Order order) async {
    final printer = await getKitchenPrinter();
    if (printer != null && printer.type == PrinterConnectionType.bluetooth) {
      await _printOrder(printer, order, isKitchen: true);
    } else {
      final pdf = await _generateKitchenReceipt(order);
      await Printing.layoutPdf(onLayout: (_) async => pdf);
    }
  }

  // ===== PDF Generation =====

  String _formatDate(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}  $hour:$minute';
  }

  Future<Uint8List> _generateCustomerReceipt(Order order) async {
    final pdf = pw.Document();
    // 58mm thermal receipt paper width ≈ 164 points (common small thermal)
    // 80mm thermal receipt paper width ≈ 226 points
    const pageWidth = 164.0;
    const pageMargin = 6.0;

    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(pageWidth, double.infinity,
            marginAll: pageMargin),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Header
              pw.Text('Viking Burger',
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 1),
              pw.Text('================',
                  style: const pw.TextStyle(fontSize: 7)),
              pw.SizedBox(height: 4),

              // Date
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Date:', style: const pw.TextStyle(fontSize: 7)),
                  pw.Text(_formatDate(order.createdAt),
                      style: const pw.TextStyle(fontSize: 7)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Items:', style: const pw.TextStyle(fontSize: 7)),
                  pw.Text(
                      '${order.items.fold<int>(0, (s, i) => s + i.quantity)}',
                      style: const pw.TextStyle(fontSize: 7)),
                ],
              ),
              pw.SizedBox(height: 3),
              pw.Text('--------------------------------',
                  style: const pw.TextStyle(fontSize: 6)),
              pw.SizedBox(height: 3),

              // Column headers
              pw.Row(
                children: [
                  pw.Expanded(
                      flex: 5,
                      child: pw.Text('Item',
                          style: pw.TextStyle(
                              fontSize: 7,
                              fontWeight: pw.FontWeight.bold))),
                  pw.SizedBox(
                      width: 20,
                      child: pw.Text('Qty',
                          style: pw.TextStyle(
                              fontSize: 7,
                              fontWeight: pw.FontWeight.bold),
                          textAlign: pw.TextAlign.center)),
                  pw.Expanded(
                      flex: 3,
                      child: pw.Text('Total',
                          style: pw.TextStyle(
                              fontSize: 7,
                              fontWeight: pw.FontWeight.bold),
                          textAlign: pw.TextAlign.right)),
                ],
              ),
              pw.SizedBox(height: 2),

              // Items
              ...order.items.expand((item) => [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 1),
                      child: pw.Row(
                        children: [
                          pw.Expanded(
                              flex: 5,
                              child: pw.Text(item.name,
                                  style: const pw.TextStyle(fontSize: 7))),
                          pw.SizedBox(
                              width: 20,
                              child: pw.Text('${item.quantity}',
                                  style: const pw.TextStyle(fontSize: 7),
                                  textAlign: pw.TextAlign.center)),
                          pw.Expanded(
                              flex: 3,
                              child: pw.Text(
                                  formatPrice(item.totalPrice),
                                  style: const pw.TextStyle(fontSize: 7),
                                  textAlign: pw.TextAlign.right)),
                        ],
                      ),
                    ),
                    if (item.note != null && item.note!.isNotEmpty)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 2, left: 4),
                        child: pw.Text('  > ${item.note}',
                            style: pw.TextStyle(
                                fontSize: 6,
                                fontStyle: pw.FontStyle.italic)),
                      ),
                  ]),

              pw.SizedBox(height: 3),
              pw.Text('--------------------------------',
                  style: const pw.TextStyle(fontSize: 6)),
              pw.SizedBox(height: 3),

              // Totals
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Subtotal:',
                      style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('${formatPrice(order.totalPrice)} IQD',
                      style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              if (order.discount > 0)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Discount:',
                        style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('- ${formatPrice(order.discount)} IQD',
                        style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
              pw.SizedBox(height: 2),
              pw.Text('================================',
                  style: const pw.TextStyle(fontSize: 6)),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL:',
                      style: pw.TextStyle(
                          fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  pw.Text('${formatPrice(order.finalPrice)} IQD',
                      style: pw.TextStyle(
                          fontSize: 11, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Text('================================',
                  style: const pw.TextStyle(fontSize: 6)),
              pw.SizedBox(height: 4),
              pw.Text('Thank you!',
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Text('We hope to see you again',
                  style: const pw.TextStyle(fontSize: 7)),
              pw.SizedBox(height: 1),
              pw.Text('Erbil - Bahirka - Main St.',
                  style: const pw.TextStyle(fontSize: 6)),
              pw.Text('0750 348 5909',
                  style: const pw.TextStyle(fontSize: 6)),
              pw.SizedBox(height: 8),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  Future<Uint8List> _generateKitchenReceipt(Order order) async {
    final pdf = pw.Document();
    // 58mm thermal receipt paper
    const pageWidth = 164.0;
    const pageMargin = 6.0;

    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(pageWidth, double.infinity,
            marginAll: pageMargin),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Header - Kitchen
              pw.Text('** KITCHEN **',
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              pw.Text(_formatDate(order.createdAt),
                  style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(height: 4),
              pw.Text('================================',
                  style: const pw.TextStyle(fontSize: 6)),
              pw.SizedBox(height: 6),

              // Items - bigger font, just name + quantity, no background fill
              ...order.items.expand((item) => [
                    pw.Container(
                      margin: const pw.EdgeInsets.only(bottom: 1),
                      padding: const pw.EdgeInsets.symmetric(
                          vertical: 3, horizontal: 4),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(width: 0.8),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Expanded(
                                child: pw.Text(item.name,
                                    style: pw.TextStyle(
                                        fontSize: 11,
                                        fontWeight: pw.FontWeight.bold)),
                              ),
                              pw.Text('  x${item.quantity}',
                                  style: pw.TextStyle(
                                    fontSize: 12,
                                    fontWeight: pw.FontWeight.bold,
                                  )),
                            ],
                          ),
                          if (item.note != null && item.note!.isNotEmpty)
                            pw.Padding(
                              padding: const pw.EdgeInsets.only(top: 2),
                              child: pw.Text('> ${item.note}',
                                  style: pw.TextStyle(
                                      fontSize: 8,
                                      fontStyle: pw.FontStyle.italic)),
                            ),
                        ],
                      ),
                    ),
                    pw.SizedBox(height: 3),
                  ]),

              pw.SizedBox(height: 4),
              pw.Text('================================',
                  style: const pw.TextStyle(fontSize: 6)),
              pw.SizedBox(height: 3),
              pw.Text(
                  'Total: ${order.items.fold<int>(0, (s, i) => s + i.quantity)} items',
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  // ===== ESC/POS Thermal Receipt Generation (for Bluetooth) =====

  static const int _lineWidth = 32; // 58mm thermal printer character width

  List<int> _escInit() => [0x1B, 0x40]; // Initialize
  List<int> _escCenter() => [0x1B, 0x61, 0x01];
  List<int> _escLeft() => [0x1B, 0x61, 0x00];
  List<int> _escBoldOn() => [0x1B, 0x45, 0x01];
  List<int> _escBoldOff() => [0x1B, 0x45, 0x00];
  List<int> _escDoubleSize() => [0x1B, 0x21, 0x30]; // double height + width
  List<int> _escNormalSize() => [0x1B, 0x21, 0x00];
  List<int> _escFeed(int lines) => List.generate(lines, (_) => 0x0A);
  List<int> _escCut() => [0x1D, 0x56, 0x01]; // Partial cut
  List<int> _text(String s) => utf8.encode(s);

  String _padRight2(String left, String right) {
    final space = _lineWidth - left.length - right.length;
    return '$left${' ' * (space > 0 ? space : 1)}$right';
  }

  String _padColumns(String name, String qty, String total) {
    // name: 18 chars, qty: 4 chars center, total: 10 chars right
    final n = name.length > 18 ? name.substring(0, 18) : name.padRight(18);
    final q = qty.padLeft(2).padRight(4);
    final t = total.padLeft(10);
    return '$n$q$t';
  }

  List<int> _generateCustomerReceiptESC(Order order) {
    final bytes = <int>[];
    final itemCount = order.items.fold<int>(0, (s, i) => s + i.quantity);

    bytes.addAll(_escInit());

    // Header
    bytes.addAll(_escCenter());
    bytes.addAll(_escDoubleSize());
    bytes.addAll(_escBoldOn());
    bytes.addAll(_text('VIKING BURGER\n'));
    bytes.addAll(_escBoldOff());
    bytes.addAll(_escNormalSize());
    bytes.addAll(_text('Erbil - Bahirka - Main St.\n'));
    bytes.addAll(_text('0750 348 5909\n'));
    bytes.addAll(_text('================================\n'));
    bytes.addAll(_escFeed(1));

    // Date & items
    bytes.addAll(_escLeft());
    bytes.addAll(_text(_padRight2('Date:', _formatDate(order.createdAt))));
    bytes.addAll(_escFeed(1));
    bytes.addAll(_text(_padRight2('Items:', '$itemCount')));
    bytes.addAll(_escFeed(1));
    bytes.addAll(_text('--------------------------------\n'));

    // Column headers
    bytes.addAll(_escBoldOn());
    bytes.addAll(_text(_padColumns('Item', 'Qty', 'Total')));
    bytes.addAll(_escFeed(1));
    bytes.addAll(_escBoldOff());

    // Items
    for (final item in order.items) {
      bytes.addAll(_text(_padColumns(
        item.name,
        '${item.quantity}',
        formatPrice(item.totalPrice),
      )));
      bytes.addAll(_escFeed(1));
      if (item.note != null && item.note!.isNotEmpty) {
        bytes.addAll(_text('  > ${item.note}'));
        bytes.addAll(_escFeed(1));
      }
    }

    bytes.addAll(_text('--------------------------------\n'));

    // Subtotal
    bytes.addAll(_text(_padRight2('Subtotal:', '${formatPrice(order.totalPrice)} IQD')));
    bytes.addAll(_escFeed(1));

    // Discount
    if (order.discount > 0) {
      bytes.addAll(_text(_padRight2('Discount:', '- ${formatPrice(order.discount)} IQD')));
      bytes.addAll(_escFeed(1));
    }

    bytes.addAll(_text('================================\n'));

    // Total - emphasized
    bytes.addAll(_escBoldOn());
    bytes.addAll(_escDoubleSize());
    bytes.addAll(_escCenter());
    bytes.addAll(_text('${formatPrice(order.finalPrice)} IQD\n'));
    bytes.addAll(_escNormalSize());
    bytes.addAll(_escBoldOff());

    bytes.addAll(_text('================================\n'));

    // Footer
    bytes.addAll(_escCenter());
    bytes.addAll(_escFeed(1));
    bytes.addAll(_escBoldOn());
    bytes.addAll(_text('Thank you!\n'));
    bytes.addAll(_escBoldOff());
    bytes.addAll(_text('We hope to see you again\n'));
    bytes.addAll(_text('Erbil - Bahirka\n'));
    bytes.addAll(_text('0750 348 5909\n'));

    bytes.addAll(_escFeed(4));
    bytes.addAll(_escCut());

    return bytes;
  }

  List<int> _generateKitchenReceiptESC(Order order) {
    final bytes = <int>[];
    final itemCount = order.items.fold<int>(0, (s, i) => s + i.quantity);

    bytes.addAll(_escInit());

    // Header
    bytes.addAll(_escCenter());
    bytes.addAll(_escDoubleSize());
    bytes.addAll(_escBoldOn());
    bytes.addAll(_text('** KITCHEN **\n'));
    bytes.addAll(_escBoldOff());
    bytes.addAll(_escNormalSize());
    bytes.addAll(_text(_formatDate(order.createdAt)));
    bytes.addAll(_escFeed(1));
    bytes.addAll(_text('================================\n'));
    bytes.addAll(_escFeed(1));

    // Items - large and bold
    bytes.addAll(_escLeft());
    for (final item in order.items) {
      bytes.addAll(_escBoldOn());
      bytes.addAll(_escDoubleSize());
      bytes.addAll(_text('${item.quantity}x ${item.name}\n'));
      bytes.addAll(_escNormalSize());
      bytes.addAll(_escBoldOff());
      if (item.note != null && item.note!.isNotEmpty) {
        bytes.addAll(_text('   > ${item.note}\n'));
      }
    }

    bytes.addAll(_escFeed(1));
    bytes.addAll(_escCenter());
    bytes.addAll(_text('================================\n'));
    bytes.addAll(_escBoldOn());
    bytes.addAll(_text('Total: $itemCount items\n'));
    bytes.addAll(_escBoldOff());

    bytes.addAll(_escFeed(4));
    bytes.addAll(_escCut());

    return bytes;
  }
}

class PrintResult {
  final bool success;
  final String message;

  PrintResult({required this.success, required this.message});
}
