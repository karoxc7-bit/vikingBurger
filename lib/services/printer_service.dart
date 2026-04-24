import 'dart:io';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/order.dart';
import '../utils/formatters.dart';
import '../kurdish_reshaper.dart';
import 'ble_printer_service.dart';

/// A single Bluetooth thermal printer saved by the user.
class SavedPrinter {
  final String name;
  final String address;

  SavedPrinter({
    required this.name,
    required this.address,
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

  // Single-printer storage keys (old "customer_*" keys are read below as a
  // migration path so users who paired before the simplification aren't
  // forced to pair again).
  static const _printerNameKey = 'printer_name';
  static const _printerAddressKey = 'printer_address';
  static const _paperWidthKey = 'paper_width_mm';

  // Legacy keys — kept for one-time auto-migration.
  static const _legacyCustomerNameKey = 'customer_printer_name';
  static const _legacyCustomerAddressKey = 'customer_printer_address';

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

  Future<void> savePrinter(SavedPrinter printer) async {
    final prefs = await _sharedPrefs;
    await prefs.setString(_printerNameKey, printer.name);
    await prefs.setString(_printerAddressKey, printer.address);
  }

  Future<SavedPrinter?> getPrinter() async {
    try {
      final prefs = await _sharedPrefs;
      var name = prefs.getString(_printerNameKey);
      var address = prefs.getString(_printerAddressKey);

      // Migration: if the user paired on the old schema (customer_*),
      // promote that pairing to the new single-printer slot transparently.
      if (name == null || address == null) {
        final legacyName = prefs.getString(_legacyCustomerNameKey);
        final legacyAddress = prefs.getString(_legacyCustomerAddressKey);
        if (legacyName != null && legacyAddress != null) {
          await prefs.setString(_printerNameKey, legacyName);
          await prefs.setString(_printerAddressKey, legacyAddress);
          name = legacyName;
          address = legacyAddress;
        }
      }

      if (name == null || address == null) return null;
      return SavedPrinter(name: name, address: address);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearPrinter() async {
    final prefs = await _sharedPrefs;
    await prefs.remove(_printerNameKey);
    await prefs.remove(_printerAddressKey);
    // Also clear any legacy entries so the migration doesn't re-populate.
    await prefs.remove(_legacyCustomerNameKey);
    await prefs.remove(_legacyCustomerAddressKey);
    await prefs.remove('customer_printer_type');
    await prefs.remove('kitchen_printer_name');
    await prefs.remove('kitchen_printer_address');
    await prefs.remove('kitchen_printer_type');
  }

  // ===== Bluetooth (BLE) =====

  final BlePrinterService _ble = BlePrinterService();

  Future<bool> isBluetoothEnabled() => _ble.isBluetoothOn();

  Future<bool> testBluetoothPrinter(String remoteId) async {
    try {
      await _ble.connectById(remoteId);
      // Send just the init command to confirm the characteristic works.
      await _ble.writeBytes(const [0x1B, 0x40]);
      await _ble.disconnect();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Prints an image (pixel-perfect receipt) via BLE ESC/POS raster.
  Future<void> _printImageToBluetooth(
      String remoteId, Uint8List pngBytes, int widthPixels) async {
    final data = pngToEscPosRaster(pngBytes, widthPixels);
    try {
      await _ble.connectById(remoteId);
      await _ble.writeBytes(data);
      // Small linger so the printer flushes its buffer before we disconnect.
      await Future.delayed(const Duration(milliseconds: 300));
    } finally {
      await _ble.disconnect();
    }
  }

  // ===== High-level print =====

  /// Prints the receipt to the configured Bluetooth printer.
  /// Returns a [PrintResult] describing success/failure for UI feedback.
  Future<PrintResult> printReceipt(Order order) async {
    final printer = await getPrinter();
    if (printer == null) {
      return PrintResult(
        success: false,
        message:
            'هیچ پرینتەرێک دیاری نەکراوە. تکایە لە ڕێکخستنەکان پرینتەر دیاری بکە.',
      );
    }

    try {
      final widthMm = await getPaperWidthMm();
      final spec = _paperSpec(widthMm);
      final pngBytes = await generateReceiptImage(order);
      await _printImageToBluetooth(
          printer.address, pngBytes, spec.targetPixelWidth);
      return PrintResult(success: true, message: 'پرینت سەرکەوتوو بوو');
    } catch (e) {
      return PrintResult(
          success: false, message: 'هەڵەی پرینت: $e');
    }
  }

  // ===== Share receipt as image (for iPrint / thermal printer apps) =====

  /// Generates the receipt as a PNG image sized exactly to the thermal
  /// printer's native dot width (384px for 58mm, 576px for 80mm).
  Future<Uint8List> generateReceiptImage(Order order) async {
    final widthMm = await getPaperWidthMm();
    final spec = _paperSpec(widthMm);

    final pdfBytes = await _generateReceiptPdf(order, spec: spec);

    final pages = await Printing.raster(pdfBytes, dpi: spec.dpi).toList();
    if (pages.isEmpty) {
      throw Exception('نەتوانرا وێنەی وەسڵ دروست بکرێت');
    }

    if (pages.length == 1) {
      return await pages.first.toPng();
    }

    return await _stitchPagesVertically(pages, spec.targetPixelWidth);
  }

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

  /// iOS share sheet fallback — when direct BLE printing isn't available,
  /// the cashier can share the image to iPrint or similar apps.
  Future<void> shareReceiptAsImage(Order order,
      {Rect? sharePositionOrigin}) async {
    final pngBytes = await generateReceiptImage(order);

    final tempDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final name = 'receipt_$ts.png';
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes(pngBytes);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'image/png', name: name)],
      subject: 'Viking Burger - Receipt',
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  /// Opens the iOS share sheet with a **PDF** receipt. This is the
  /// recommended path for iPrint-style thermal printer apps because they
  /// register themselves as PDF handlers — the user just taps iPrint in
  /// the share sheet and the PDF opens pre-loaded and ready to print.
  ///
  /// The PDF is sized to the configured paper width and renders Kurdish
  /// text via embedded fonts (no rasterization needed on the receiving end).
  Future<void> shareReceiptAsPdf(Order order,
      {Rect? sharePositionOrigin}) async {
    final widthMm = await getPaperWidthMm();
    final spec = _paperSpec(widthMm);
    final pdfBytes = await _generateReceiptPdf(order, spec: spec);

    final tempDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final name = 'Viking_Burger_Receipt_$ts.pdf';
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes(pdfBytes);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: name)],
      subject: 'Viking Burger - Receipt',
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  /// Saves the receipt PNG into the "Viking Burger" album in Photos so
  /// the cashier can pick it from iPrint's "Document Print" flow.
  Future<String> saveReceiptToGallery(Order order) async {
    // Permission check — wrap in try because Gal throws
    // MissingPluginException when the native side isn't built yet.
    try {
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          throw Exception('PHOTO_PERMISSION_DENIED');
        }
      }
    } on MissingPluginException {
      throw Exception('PLUGIN_UNAVAILABLE');
    }

    final pngBytes = await generateReceiptImage(order);
    final tempDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'Receipt_$ts.png';
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(pngBytes);

    const albumName = 'Viking Burger';
    try {
      await Gal.putImage(file.path, album: albumName);
    } on MissingPluginException {
      throw Exception('PLUGIN_UNAVAILABLE');
    } finally {
      try {
        await file.delete();
      } catch (_) {}
    }

    return albumName;
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

  /// Single receipt template (customer-style). Scales fonts proportionally
  /// to the paper width so 58mm and 80mm look equally clean.
  Future<Uint8List> _generateReceiptPdf(Order order,
      {required _PaperSpec spec}) async {
    final fontData = await rootBundle.load('assets/fonts/NotoKufiArabic.ttf');
    final font = pw.Font.ttf(fontData);
    final fontBoldData =
        await rootBundle.load('assets/fonts/NotoKufiArabic-Bold.ttf');
    final fontBold = pw.Font.ttf(fontBoldData);

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
                              child: _pwText(formatPrice(item.totalPrice),
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
}

class PrintResult {
  final bool success;
  final String message;

  PrintResult({required this.success, required this.message});
}
