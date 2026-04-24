import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/ble_printer_service.dart';

/// Modal bottom sheet that scans for BLE thermal printers and lets the
/// user tap one to select it. On success the sheet pops with a
/// [BluetoothDevice]; on cancel it pops with null.
///
/// Handles Bluetooth permissions and adapter-off states inline so the
/// caller doesn't need to. All text is RTL Kurdish.
class BleScanSheet extends StatefulWidget {
  const BleScanSheet({super.key});

  static Future<BluetoothDevice?> show(BuildContext context) {
    return showModalBottomSheet<BluetoothDevice>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const BleScanSheet(),
    );
  }

  @override
  State<BleScanSheet> createState() => _BleScanSheetState();
}

class _BleScanSheetState extends State<BleScanSheet>
    with SingleTickerProviderStateMixin {
  final _ble = BlePrinterService();
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  List<ScanResult> _results = [];
  bool _scanning = false;
  bool _adapterOn = true;
  bool _requestingPerms = false;
  String? _errorMessage;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _init();
  }

  Future<void> _init() async {
    // First make sure the native plugin actually loaded. On a hot-restart
    // after adding flutter_blue_plus this can be `false` until the user
    // does a full rebuild — surface a friendly message instead of crashing.
    final available = await _ble.isPluginAvailable();
    if (!available) {
      if (mounted) {
        setState(() {
          _errorMessage =
              'پلەگینی بلوتوس ئامادە نییە. تکایە ئەپلیکەیشنەکە بە تەواوی دامێزرێنە لەبار (Full Rebuild).';
          _requestingPerms = false;
        });
      }
      return;
    }

    _adapterSub = _ble.adapterStateStream.listen(
      (state) {
        if (!mounted) return;
        setState(() => _adapterOn = state == BluetoothAdapterState.on);
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _adapterOn = false);
      },
    );
    await _ensurePermissions();
    _adapterOn = await _ble.isBluetoothOn();
    if (mounted) setState(() {});
    if (_adapterOn) _startScan();
  }

  Future<void> _ensurePermissions() async {
    setState(() => _requestingPerms = true);
    try {
      // Android requires explicit BT scan + connect + location (older SDKs).
      // iOS handles permissions via Info.plist strings, but requesting
      // bluetoothScan here is harmless.
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
      final granted = statuses.values.every(
          (s) => s.isGranted || s.isLimited || s.isRestricted || s.isDenied);
      if (!granted) {
        _errorMessage = 'ڕێگەی بلوتوس پێویستە بۆ دۆزینەوەی پرینتەر.';
      }
    } catch (_) {}
    if (mounted) setState(() => _requestingPerms = false);
  }

  Future<void> _startScan() async {
    await _scanSub?.cancel();
    setState(() {
      _scanning = true;
      _results = [];
      _errorMessage = null;
    });
    try {
      _scanSub = _ble
          .scanForPrinters(timeout: const Duration(seconds: 12))
          .listen((results) {
        if (!mounted) return;
        setState(() => _results = results);
      }, onDone: () {
        if (!mounted) return;
        setState(() => _scanning = false);
      }, onError: (err) {
        if (!mounted) return;
        final msg = err.toString().contains('PLUGIN_UNAVAILABLE')
            ? 'پلەگینی بلوتوس ئامادە نییە. تکایە ئەپلیکەیشنەکە بە تەواوی دامێزرێنە لەبار.'
            : 'کێشەیەک ڕوویدا لە دۆزینەوەی ئامێرەکان.';
        setState(() {
          _scanning = false;
          _errorMessage = msg;
        });
      });

      // Stop scan after the advertised timeout so the spinner settles.
      Future.delayed(const Duration(seconds: 12), () async {
        if (!mounted) return;
        await _scanSub?.cancel();
        setState(() => _scanning = false);
      });
    } on Exception catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('PLUGIN_UNAVAILABLE')
          ? 'پلەگینی بلوتوس ئامادە نییە. تکایە ئەپلیکەیشنەکە بە تەواوی دامێزرێنە لەبار.'
          : 'کێشەیەک ڕوویدا: $e';
      setState(() {
        _scanning = false;
        _errorMessage = msg;
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scanSub?.cancel();
    _adapterSub?.cancel();
    _ble.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        minChildSize: 0.55,
        maxChildSize: 0.95,
        builder: (context, controller) {
          return Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF42A5F5).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.bluetooth_searching_rounded,
                          color: Color(0xFF42A5F5), size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'دۆزینەوەی پرینتەر',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'پرینتەرەکەت بکەرەوە و نزیکی مۆبایلەکە دایبنێ',
                            style: TextStyle(
                                color: Colors.white54, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    if (_scanning)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFFFF8C00)),
                      )
                    else
                      IconButton(
                        onPressed: _startScan,
                        icon: const Icon(Icons.refresh_rounded,
                            color: Color(0xFFFF8C00)),
                        tooltip: 'دۆزینەوە دوبارە',
                      ),
                  ],
                ),
              ),
              // Helpful hint: BLE scan only sees devices that are actively
              // advertising. If the printer is already "connected" in iPrint
              // or iOS Settings, it won't appear here until disconnected.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF8C00).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFFFF8C00).withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          color: Color(0xFFFF8C00), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'ئەگەر پرینتەرەکە پێشتر بە iPrint یان لە ڕێکخستنەکانی iOS پەیوەستە، تکایە سەرەتا پەیوەندییەکەی لێ بڕێنەوە ئینجا گەڕان بکە.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 11,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildBody(controller)),
              Padding(
                padding: EdgeInsets.fromLTRB(
                    20, 10, 20, MediaQuery.of(context).padding.bottom + 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, null),
                    child: const Text(
                      'پاشگەزبوونەوە',
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(ScrollController controller) {
    if (_requestingPerms) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF8C00)),
      );
    }

    if (!_adapterOn) {
      return _infoState(
        icon: Icons.bluetooth_disabled_rounded,
        title: 'بلوتوس کوێرە',
        subtitle:
            'تکایە بلوتوسی مۆبایلەکەت چالاک بکە ئینجا دووبارە هەوڵ بدەرەوە',
        action: TextButton.icon(
          onPressed: () => _ble.requestEnableBluetooth(),
          icon: const Icon(Icons.bluetooth_rounded,
              color: Color(0xFFFF8C00)),
          label: const Text('چالاککردنی بلوتوس',
              style: TextStyle(color: Color(0xFFFF8C00))),
        ),
      );
    }

    if (_errorMessage != null) {
      return _infoState(
        icon: Icons.error_outline_rounded,
        title: 'کێشەیەک ڕوویدا',
        subtitle: _errorMessage!,
        action: TextButton.icon(
          onPressed: _startScan,
          icon: const Icon(Icons.refresh_rounded, color: Color(0xFFFF8C00)),
          label: const Text('دووبارەکردنەوە',
              style: TextStyle(color: Color(0xFFFF8C00))),
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: Tween(begin: 0.85, end: 1.05).animate(_pulseController),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0xFF42A5F5).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.bluetooth_searching_rounded,
                    color: Color(0xFF42A5F5), size: 44),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _scanning ? 'بگەڕێ بۆ ئامێرەکان...' : 'هیچ ئامێرێک نەدۆزرایەوە',
              style: const TextStyle(
                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'دڵنیا بە کە پرینتەرەکە چالاکە و بلوتوسەکەی کراوەتەوە',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    // Sort: likely printers first, then by signal strength.
    final sorted = [..._results]
      ..sort((a, b) {
        final aP = looksLikePrinter(a) ? 1 : 0;
        final bP = looksLikePrinter(b) ? 1 : 0;
        if (aP != bP) return bP - aP;
        return b.rssi.compareTo(a.rssi);
      });

    return ListView.separated(
      controller: controller,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: sorted.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _buildDeviceTile(sorted[i]),
    );
  }

  Widget _buildDeviceTile(ScanResult result) {
    final name = result.advertisementData.advName.isNotEmpty
        ? result.advertisementData.advName
        : (result.device.platformName.isNotEmpty
            ? result.device.platformName
            : 'ئامێری نەناسراو');
    final isPrinter = looksLikePrinter(result);
    final signalStrength = _signalBars(result.rssi);

    return Material(
      color: isPrinter
          ? const Color(0xFF42A5F5).withValues(alpha: 0.10)
          : const Color(0xFF2A2A2A),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => Navigator.pop(context, result.device),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isPrinter
                      ? const Color(0xFF42A5F5).withValues(alpha: 0.2)
                      : const Color(0xFF333333),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isPrinter
                      ? Icons.print_rounded
                      : Icons.bluetooth_rounded,
                  color: isPrinter
                      ? const Color(0xFF42A5F5)
                      : Colors.white70,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isPrinter)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF42A5F5)
                                  .withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'پرینتەر',
                              style: TextStyle(
                                color: Color(0xFF42A5F5),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      result.device.remoteId.str,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(4, (i) {
                  final active = i < signalStrength;
                  return Container(
                    width: 3,
                    height: 6 + i * 3.0,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0xFF4CAF50)
                          : Colors.white12,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _signalBars(int rssi) {
    // RSSI scale: -40 excellent, -90 very weak.
    if (rssi >= -55) return 4;
    if (rssi >= -70) return 3;
    if (rssi >= -80) return 2;
    if (rssi >= -90) return 1;
    return 0;
  }

  Widget _infoState({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white54, size: 44),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            if (action != null) ...[
              const SizedBox(height: 14),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
