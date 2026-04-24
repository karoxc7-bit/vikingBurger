import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../models/order.dart';
import '../utils/formatters.dart';
import '../kurdish_reshaper.dart';

enum PrinterConnectionType { system, network, bluetooth }

class SavedPrinter {
  final String name;
  final String address;
  final PrinterConnectionType type;

  SavedPrinter({
    required this.name,
    required this.address,
    required this.type,
  });
}

/// Paper specification used for both PDF page size and raster pixel width.
/// The printable width (mm / points) is what gets drawn, and the target
/// pixel width corresponds to the native thermal printer dot count at 203 DPI.
class _PaperSpec {
  final int paperMm;
  final double pdfWidthPoints;
  final int targetPixelWidth;

  const _PaperSpec({
    required this.paperMm,
    required this.pdfWidthPoints,
    required this.targetPixelWidth,
  });

  double get dpi => targetPixelWidth * 72 / pdfWidthPoints;
}

class PrinterService {
  static final PrinterService _instance = PrinterService._internal();
  factory PrinterService() => _instance;
  PrinterService._internal();

  static const _customerNameKey = 'customer_printer_name';
  static const _customerAddressKey = 'customer_printer_address';
  static const _customerTypeKey = 'customer_printer_type';
  static const _kitchenNameKey = 'kitchen_printer_name';
  static const _kitchenAddressKey = 'kitchen_printer_address';
  static const _kitchenTypeKey = 'kitchen_printer_type';
  static const _paperWidthKey = 'paper_width_mm';

  static const int defaultPaperWidthMm = 80;

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _sharedPrefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ===== Paper width (58mm / 80mm) =====

  Future<int> getPaperWidthMm() async {
    final prefs = await _sharedPrefs;
    return prefs.getInt(_paperWidthKey) ?? defaultPaperWidthMm;
  }

  Future<void> setPaperWidthMm(int widthMm) async {
    final prefs = await _sharedPrefs;
    await prefs.setInt(_paperWidthKey, widthMm);
  }

  /// Returns the paper spec (PDF width + target pixel width at 203 DPI)
  /// matching the thermal printer's native printable area.
  /// - 58mm printer: 384 dots printable (~48mm)
  /// - 80mm printer: 576 dots printable (~72mm)
  _PaperSpec _paperSpec(int widthMm) {
    if (widthMm <= 58) {
      return const _PaperSpec(
        paperMm: 58,
        pdfWidthPoints: 136.0,
        targetPixelWidth: 384,
      );
    }
    return const _PaperSpec(
      paperMm: 80,
      pdfWidthPoints: 204.0,
      targetPixelWidth: 576,
    );
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

  // ===== System Printers =====

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
    final result =
        await PrintBluetoothThermal.writeBytes(Uint8List.fromList(escBytes));
    if (!result) throw Exception('نەتوانرا پرینت بکرێت');
    await PrintBluetoothThermal.disconnect;
  }

  // ===== High-level print =====

  Future<PrintResult> printBoth(Order order) async {
    final customerPrinter = await getCustomerPrinter();
    final kitchenPrinter = await getKitchenPrinter();

    if (customerPrinter == null && kitchenPrinter == null) {
      return PrintResult(
        success: false,
        message:
            'هیچ پرینتەرێک دیاری نەکراوە. تکایە لە ڕێکخستنەکان پرینتەر دیاری بکە.',
      );
    }

    final errors = <String>[];
    int printed = 0;

    if (customerPrinter != null) {
      try {
        await _printOrder(customerPrinter, order, isKitchen: false);
        printed++;
      } catch (e) {
        errors.add('هەڵەی پرینتی کڕیار: $e');
      }
    }

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
          message: '$printed پرینت سەرکەوتوو. ${errors.join(" | ")}');
    } else {
      return PrintResult(success: false, message: errors.join(' | '));
    }
  }

  Future<void> _printOrder(SavedPrinter saved, Order order,
      {required bool isKitchen}) async {
    final widthMm = await getPaperWidthMm();
    final spec = _paperSpec(widthMm);

    if (saved.type == PrinterConnectionType.bluetooth) {
      final escBytes = isKitchen
          ? _generateKitchenReceiptESC(order)
          : _generateCustomerReceiptESC(order);
      await _printToBluetooth(saved.address, escBytes);
    } else {
      final pdfBytes = isKitchen
          ? await _generateKitchenReceipt(order, spec: spec)
          : await _generateCustomerReceipt(order, spec: spec);
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

  Future<void> printCustomerWithDialog(Order order) async {
    final widthMm = await getPaperWidthMm();
    final spec = _paperSpec(widthMm);
    final printer = await getCustomerPrinter();
    if (printer != null && printer.type == PrinterConnectionType.bluetooth) {
      await _printOrder(printer, order, isKitchen: false);
    } else {
      final pdf = await _generateCustomerReceipt(order, spec: spec);
      await Printing.layoutPdf(
        onLayout: (_) async => pdf,
        format: PdfPageFormat(spec.pdfWidthPoints, double.infinity,
            marginAll: 0),
      );
    }
  }

  Future<void> printKitchenWithDialog(Order order) async {
    final widthMm = await getPaperWidthMm();
    final spec = _paperSpec(widthMm);
    final printer = await getKitchenPrinter();
    if (printer != null && printer.type == PrinterConnectionType.bluetooth) {
      await _printOrder(printer, order, isKitchen: true);
    } else {
      final pdf = await _generateKitchenReceipt(order, spec: spec);
      await Printing.layoutPdf(
        onLayout: (_) async => pdf,
        format: PdfPageFormat(spec.pdfWidthPoints, double.infinity,
            marginAll: 0),
      );
    }
  }

  // ===== Share receipt as image (for iPrint / thermal printer apps) =====

  /// Generates the receipt as a PNG image sized exactly to the thermal
  /// printer's native dot width (384px for 58mm, 576px for 80mm).
  /// This guarantees 1:1 printing with no scaling inside iPrint.
  Future<Uint8List> generateReceiptImage(Order order,
      {bool isKitchen = false}) async {
    final widthMm = await getPaperWidthMm();
    final spec = _paperSpec(widthMm);

    final pdfBytes = isKitchen
        ? await _generateKitchenReceipt(order, spec: spec)
        : await _generateCustomerReceipt(order, spec: spec);

    final pages = await Printing.raster(pdfBytes, dpi: spec.dpi).toList();
    if (pages.isEmpty) {
      throw Exception('نەتوانرا وێنەی وەسڵ دروست بکرێت');
    }

    if (pages.length == 1) {
      return await pages.first.toPng();
    }

    return await _stitchPagesVertically(pages, spec.targetPixelWidth);
  }

  /// Stitch multiple raster pages vertically into one tall PNG.
  /// Each page has the same width (the printer's dot count).
  Future<Uint8List> _stitchPagesVertically(
      List<PdfRaster> pages, int width) async {
    int totalHeight = 0;
    for (final p in pages) {
      totalHeight += p.height;
    }

    final combined = Uint8List(width * totalHeight * 4);
    int offset = 0;
    for (final p in pages) {
      final raw = p.pixels;
      combined.setRange(offset, offset + raw.length, raw);
      offset += raw.length;
    }
    final stitchedRaster = PdfRasterBase(width, totalHeight, false, combined);
    return await stitchedRaster.toPng();
  }

  /// Generates a receipt image and opens the native share sheet so the user
  /// can send it to iPrint / any thermal-printer app. Result is a PNG sized
  /// exactly to the printer's dot count for crisp 1:1 printing.
  Future<void> shareReceiptAsImage(Order order,
      {bool isKitchen = false, Rect? sharePositionOrigin}) async {
    final pngBytes = await generateReceiptImage(order, isKitchen: isKitchen);

    final tempDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final name =
        isKitchen ? 'kitchen_receipt_$ts.png' : 'customer_receipt_$ts.png';
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes(pngBytes);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'image/png', name: name)],
      subject: 'Viking Burger - Receipt',
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  // ===== PDF Generation =====

  pw.Widget _pwText(String text,
      {pw.TextStyle? style,
      pw.TextAlign? textAlign,
      pw.TextDirection? textDirection}) {
    return pw.Text(KurdishReshaper.convert(text),
        style: style, textAlign: textAlign, textDirection: textDirection);
  }

  String _formatDate(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}  $hour:$minute';
  }

  /// Generates a crisp, centered, professionally-spaced customer receipt
  /// scaled proportionally to the paper size.
  Future<Uint8List> _generateCustomerReceipt(Order order,
      {required _PaperSpec spec}) async {
    final fontData = await rootBundle.load('assets/fonts/NotoKufiArabic.ttf');
    final font = pw.Font.ttf(fontData);
    final fontBoldData =
        await rootBundle.load('assets/fonts/NotoKufiArabic-Bold.ttf');
    final fontBold = pw.Font.ttf(fontBoldData);

    // Scale factor: design baseline is 58mm (136pt). Fonts grow proportionally.
    final scale = spec.pdfWidthPoints / 136.0;
    double fs(double base) => base * scale;

    final pdf = pw.Document();
    final itemCount = order.items.fold<int>(0, (s, i) => s + i.quantity);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          spec.pdfWidthPoints,
          double.infinity,
          marginAll: 0,
        ),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context context) {
          final contentPadding = spec.pdfWidthPoints * 0.04;
          return pw.Padding(
            padding: pw.EdgeInsets.symmetric(
              horizontal: contentPadding,
              vertical: contentPadding * 1.5,
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // ===== Header =====
                pw.Center(
                  child: _pwText(
                    'Viking Burger',
                    style: pw.TextStyle(
                      fontSize: fs(16),
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                pw.SizedBox(height: fs(2)),
                pw.Center(
                  child: _pwText(
                    'ئەربیل - بەحرکە - شەقامی گشتی',
                    style: pw.TextStyle(fontSize: fs(7.5)),
                  ),
                ),
                pw.SizedBox(height: fs(1.5)),
                pw.Center(
                  child: _pwText(
                    '0750 348 5909',
                    style: pw.TextStyle(
                      fontSize: fs(8.5),
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 1,
                    ),
                    textDirection: pw.TextDirection.ltr,
                  ),
                ),
                pw.SizedBox(height: fs(6)),
                _dashedDivider(spec),
                pw.SizedBox(height: fs(5)),

                if (order.isDelivery) ...[
                  pw.Container(
                    width: double.infinity,
                    padding: pw.EdgeInsets.symmetric(vertical: fs(3)),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.black, width: 1),
                    ),
                    child: pw.Center(
                      child: _pwText(
                        '*** دلیڤەری ***',
                        style: pw.TextStyle(
                          fontSize: fs(10),
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  pw.SizedBox(height: fs(6)),
                ],

                // ===== Date / Items count =====
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _pwText('بەروار',
                            style: pw.TextStyle(
                                color: PdfColors.grey700, fontSize: fs(7))),
                        pw.SizedBox(height: fs(1)),
                        _pwText(_formatDate(order.createdAt),
                            style: pw.TextStyle(
                                fontSize: fs(8),
                                fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        _pwText('ژمارەی ئایتم',
                            style: pw.TextStyle(
                                color: PdfColors.grey700, fontSize: fs(7))),
                        pw.SizedBox(height: fs(1)),
                        _pwText('$itemCount',
                            style: pw.TextStyle(
                                fontSize: fs(9),
                                fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ],
                ),

                pw.SizedBox(height: fs(5)),
                _dashedDivider(spec),
                pw.SizedBox(height: fs(4)),

                // ===== Column headers =====
                pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 5,
                      child: _pwText('ئایتم',
                          style: pw.TextStyle(
                              fontSize: fs(8),
                              fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.SizedBox(
                      width: fs(20),
                      child: _pwText('دانە',
                          style: pw.TextStyle(
                              fontSize: fs(8),
                              fontWeight: pw.FontWeight.bold),
                          textAlign: pw.TextAlign.center),
                    ),
                    pw.Expanded(
                      flex: 4,
                      child: _pwText('کۆی گشتی',
                          style: pw.TextStyle(
                              fontSize: fs(8),
                              fontWeight: pw.FontWeight.bold),
                          textAlign: pw.TextAlign.left),
                    ),
                  ],
                ),
                pw.SizedBox(height: fs(2)),
                _dashedDivider(spec),
                pw.SizedBox(height: fs(3)),

                // ===== Items =====
                ...order.items.expand((item) => [
                      pw.Padding(
                        padding: pw.EdgeInsets.symmetric(vertical: fs(1.5)),
                        child: pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Expanded(
                              flex: 5,
                              child: _pwText(item.name,
                                  style: pw.TextStyle(fontSize: fs(9))),
                            ),
                            pw.SizedBox(
                              width: fs(20),
                              child: _pwText('${item.quantity}',
                                  style: pw.TextStyle(
                                      fontSize: fs(9),
                                      fontWeight: pw.FontWeight.bold),
                                  textAlign: pw.TextAlign.center),
                            ),
                            pw.Expanded(
                              flex: 4,
                              child: _pwText(
                                  formatPrice(item.totalPrice),
                                  style: pw.TextStyle(
                                      fontSize: fs(9),
                                      fontWeight: pw.FontWeight.bold),
                                  textAlign: pw.TextAlign.left),
                            ),
                          ],
                        ),
                      ),
                      if (item.note != null && item.note!.isNotEmpty)
                        pw.Padding(
                          padding: pw.EdgeInsets.only(
                              bottom: fs(2), right: fs(4), left: fs(4)),
                          child: _pwText(
                            '› ${item.note}',
                            style: pw.TextStyle(
                              color: PdfColors.grey700,
                              fontSize: fs(7.5),
                              fontStyle: pw.FontStyle.italic,
                            ),
                          ),
                        ),
                    ]),

                pw.SizedBox(height: fs(3)),
                _dashedDivider(spec),
                pw.SizedBox(height: fs(4)),

                // ===== Totals =====
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _pwText('کۆی نرخەکان',
                        style: pw.TextStyle(fontSize: fs(9))),
                    _pwText('IQD ${formatPrice(order.totalPrice)}',
                        style: pw.TextStyle(fontSize: fs(9))),
                  ],
                ),
                if (order.discount > 0) ...[
                  pw.SizedBox(height: fs(2)),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      _pwText('داشکاندن',
                          style: pw.TextStyle(fontSize: fs(9))),
                      _pwText('IQD -${formatPrice(order.discount)}',
                          style: pw.TextStyle(fontSize: fs(9))),
                    ],
                  ),
                ],

                pw.SizedBox(height: fs(4)),
                pw.Container(height: 1.2, color: PdfColors.black),
                pw.SizedBox(height: fs(5)),

                // ===== Final =====
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    _pwText('نرخی کۆتایی',
                        style: pw.TextStyle(
                            fontSize: fs(12), fontWeight: pw.FontWeight.bold)),
                    _pwText('IQD ${formatPrice(order.finalPrice)}',
                        style: pw.TextStyle(
                            fontSize: fs(13),
                            fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.SizedBox(height: fs(6)),
                _dashedDivider(spec),
                pw.SizedBox(height: fs(8)),

                // ===== Footer =====
                pw.Center(
                  child: _pwText(
                    'سوپاس بۆ هەڵبژاردنی ئێمە',
                    style: pw.TextStyle(
                        fontSize: fs(10), fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.SizedBox(height: fs(2)),
                pw.Center(
                  child: _pwText(
                    'چاوەڕێی گەڕانەوەت دەکەین بۆ تامێکی تایبەت تر',
                    style: pw.TextStyle(
                        color: PdfColors.grey700, fontSize: fs(7)),
                  ),
                ),
                pw.SizedBox(height: fs(4)),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  Future<Uint8List> _generateKitchenReceipt(Order order,
      {required _PaperSpec spec}) async {
    final fontData = await rootBundle.load('assets/fonts/NotoKufiArabic.ttf');
    final font = pw.Font.ttf(fontData);
    final fontBoldData =
        await rootBundle.load('assets/fonts/NotoKufiArabic-Bold.ttf');
    final fontBold = pw.Font.ttf(fontBoldData);

    final scale = spec.pdfWidthPoints / 136.0;
    double fs(double base) => base * scale;

    final itemCount = order.items.fold<int>(0, (s, i) => s + i.quantity);

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          spec.pdfWidthPoints,
          double.infinity,
          marginAll: 0,
        ),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context context) {
          final contentPadding = spec.pdfWidthPoints * 0.04;
          return pw.Padding(
            padding: pw.EdgeInsets.symmetric(
              horizontal: contentPadding,
              vertical: contentPadding * 1.5,
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Center(
                  child: _pwText('** مەتبەخ **',
                      style: pw.TextStyle(
                          fontSize: fs(14), fontWeight: pw.FontWeight.bold)),
                ),
                pw.SizedBox(height: fs(3)),
                pw.Center(
                  child: _pwText(_formatDate(order.createdAt),
                      style: pw.TextStyle(fontSize: fs(8))),
                ),
                pw.SizedBox(height: fs(5)),
                _dashedDivider(spec),
                pw.SizedBox(height: fs(5)),

                if (order.isDelivery) ...[
                  pw.Container(
                    width: double.infinity,
                    padding: pw.EdgeInsets.symmetric(vertical: fs(4)),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.black, width: 1.2),
                    ),
                    child: pw.Center(
                      child: _pwText('*** دلیڤەری ***',
                          style: pw.TextStyle(
                              fontSize: fs(12),
                              fontWeight: pw.FontWeight.bold)),
                    ),
                  ),
                  pw.SizedBox(height: fs(6)),
                ],

                ...order.items.expand((item) => [
                      pw.Container(
                        margin: pw.EdgeInsets.only(bottom: fs(3)),
                        padding: pw.EdgeInsets.symmetric(
                            vertical: fs(3), horizontal: fs(3)),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(width: 0.8),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                          children: [
                            pw.Row(
                              mainAxisAlignment:
                                  pw.MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Expanded(
                                  child: _pwText(
                                    item.name,
                                    style: pw.TextStyle(
                                        fontSize: fs(11),
                                        fontWeight: pw.FontWeight.bold),
                                  ),
                                ),
                                pw.SizedBox(width: fs(4)),
                                _pwText('${item.quantity}x',
                                    style: pw.TextStyle(
                                        fontSize: fs(13),
                                        fontWeight: pw.FontWeight.bold)),
                              ],
                            ),
                            if (item.note != null && item.note!.isNotEmpty)
                              pw.Padding(
                                padding: pw.EdgeInsets.only(top: fs(2)),
                                child: _pwText(
                                  '› ${item.note}',
                                  style: pw.TextStyle(fontSize: fs(9)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ]),

                pw.SizedBox(height: fs(4)),
                _dashedDivider(spec),
                pw.SizedBox(height: fs(4)),
                pw.Center(
                  child: _pwText('کۆی ئایتم: $itemCount',
                      style: pw.TextStyle(
                          fontSize: fs(11), fontWeight: pw.FontWeight.bold)),
                ),
                pw.SizedBox(height: fs(6)),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  pw.Widget _dashedDivider(_PaperSpec spec) {
    final segments = (spec.pdfWidthPoints / 4).floor();
    return pw.Row(
      children: List.generate(
        segments,
        (i) => pw.Expanded(
          child: pw.Container(
            height: 0.6,
            margin: const pw.EdgeInsets.symmetric(horizontal: 0.6),
            color: i.isEven ? PdfColors.grey600 : PdfColors.white,
          ),
        ),
      ),
    );
  }

  // ===== ESC/POS Thermal Receipt Generation (for Bluetooth) =====

  int get _lineWidth => 32; // 58mm default, 80mm uses 48

  List<int> _escInit() => [0x1B, 0x40];
  List<int> _escCenter() => [0x1B, 0x61, 0x01];
  List<int> _escLeft() => [0x1B, 0x61, 0x00];
  List<int> _escBoldOn() => [0x1B, 0x45, 0x01];
  List<int> _escBoldOff() => [0x1B, 0x45, 0x00];
  List<int> _escDoubleSize() => [0x1B, 0x21, 0x30];
  List<int> _escNormalSize() => [0x1B, 0x21, 0x00];
  List<int> _escFeed(int lines) => List.generate(lines, (_) => 0x0A);
  List<int> _escCut() => [0x1D, 0x56, 0x01];
  List<int> _text(String s) => utf8.encode(KurdishReshaper.convert(s));

  String _padRight2(String left, String right) {
    final space = _lineWidth - left.length - right.length;
    return '$left${' ' * (space > 0 ? space : 1)}$right';
  }

  String _padColumns(String name, String qty, String total) {
    final n = name.length > 18 ? name.substring(0, 18) : name.padRight(18);
    final q = qty.padLeft(2).padRight(4);
    final t = total.padLeft(10);
    return '$n$q$t';
  }

  List<int> _generateCustomerReceiptESC(Order order) {
    final bytes = <int>[];
    final itemCount = order.items.fold<int>(0, (s, i) => s + i.quantity);

    bytes.addAll(_escInit());

    bytes.addAll(_escCenter());
    bytes.addAll(_escDoubleSize());
    bytes.addAll(_escBoldOn());
    bytes.addAll(_text('VIKING BURGER\n'));
    bytes.addAll(_escBoldOff());
    bytes.addAll(_escNormalSize());
    bytes.addAll(_text('ئەربیل - بەحرکە - شەقامی گشتی\n'));
    bytes.addAll(_text('0750 348 5909\n'));
    bytes.addAll(_text('--------------------------------\n'));
    bytes.addAll(_escFeed(1));

    if (order.isDelivery) {
      bytes.addAll(_escCenter());
      bytes.addAll(_escDoubleSize());
      bytes.addAll(_escBoldOn());
      bytes.addAll(_text('*** دلیڤەری ***\n'));
      bytes.addAll(_escBoldOff());
      bytes.addAll(_escNormalSize());
      bytes.addAll(_escFeed(1));
      bytes.addAll(_text('--------------------------------\n'));
      bytes.addAll(_escFeed(1));
    }

    bytes.addAll(_escLeft());
    bytes.addAll(_text(_padRight2('بەروار', 'ژمارەی ئایتم')));
    bytes.addAll(_escFeed(1));
    bytes.addAll(_escBoldOn());
    bytes.addAll(_text(_padRight2(_formatDate(order.createdAt), '$itemCount')));
    bytes.addAll(_escBoldOff());
    bytes.addAll(_escFeed(1));
    bytes.addAll(_text('--------------------------------\n'));

    bytes.addAll(_escBoldOn());
    bytes.addAll(_text(_padColumns('ئایتم', 'دانە', 'کۆی گشتی')));
    bytes.addAll(_escFeed(1));
    bytes.addAll(_escBoldOff());

    for (final item in order.items) {
      bytes.addAll(_text(_padColumns(
        item.name,
        '${item.quantity}',
        'IQD ${formatPrice(item.totalPrice)}',
      )));
      bytes.addAll(_escFeed(1));
      if (item.note != null && item.note!.isNotEmpty) {
        bytes.addAll(_text('  > ${item.note}'));
        bytes.addAll(_escFeed(1));
      }
    }

    bytes.addAll(_text('--------------------------------\n'));

    bytes.addAll(
        _text(_padRight2('کۆی نرخەکان', 'IQD ${formatPrice(order.totalPrice)}')));
    bytes.addAll(_escFeed(1));

    if (order.discount > 0) {
      bytes.addAll(_text(
          _padRight2('داشکاندن', 'IQD -${formatPrice(order.discount)}')));
      bytes.addAll(_escFeed(1));
    }

    bytes.addAll(_text('--------------------------------\n'));

    bytes.addAll(_escBoldOn());
    bytes.addAll(_text(
        _padRight2('نرخی کۆتایی', 'IQD ${formatPrice(order.finalPrice)}')));
    bytes.addAll(_escBoldOff());
    bytes.addAll(_escFeed(1));

    bytes.addAll(_text('--------------------------------\n'));

    bytes.addAll(_escCenter());
    bytes.addAll(_escFeed(1));
    bytes.addAll(_escBoldOn());
    bytes.addAll(_text('سوپاس بۆ هەڵبژاردنی ئێمە!\n'));
    bytes.addAll(_escBoldOff());
    bytes.addAll(_text('چاوەڕێی گەڕانەوەت دەکەین بۆ تامێکی تایبەت تر\n'));

    bytes.addAll(_escFeed(4));
    bytes.addAll(_escCut());

    return bytes;
  }

  List<int> _generateKitchenReceiptESC(Order order) {
    final bytes = <int>[];
    final itemCount = order.items.fold<int>(0, (s, i) => s + i.quantity);

    bytes.addAll(_escInit());

    bytes.addAll(_escCenter());
    bytes.addAll(_escDoubleSize());
    bytes.addAll(_escBoldOn());
    bytes.addAll(_text('** مەتبەخ **\n'));
    bytes.addAll(_escBoldOff());
    bytes.addAll(_escNormalSize());
    bytes.addAll(_text(_formatDate(order.createdAt)));
    bytes.addAll(_escFeed(1));
    bytes.addAll(_text('================================\n'));
    bytes.addAll(_escFeed(1));

    if (order.isDelivery) {
      bytes.addAll(_escCenter());
      bytes.addAll(_escDoubleSize());
      bytes.addAll(_escBoldOn());
      bytes.addAll(_text('*** دلیڤەری ***\n'));
      bytes.addAll(_escBoldOff());
      bytes.addAll(_escNormalSize());
      bytes.addAll(_escFeed(1));
      bytes.addAll(_text('================================\n'));
      bytes.addAll(_escFeed(1));
    }

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
    bytes.addAll(_text('کۆی ئایتم: $itemCount\n'));
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
