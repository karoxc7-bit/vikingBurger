import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:image/image.dart' as img;

/// Well-known BLE service / characteristic UUIDs for cheap thermal printers.
/// We use these as hints when auto-selecting the write characteristic;
/// if none match, we fall back to the first writable characteristic we find.
const _knownWriteServiceUuids = <String>[
  '000018f0-0000-1000-8000-00805f9b34fb',
  '0000ff00-0000-1000-8000-00805f9b34fb',
  '0000ae30-0000-1000-8000-00805f9b34fb',
  'e7810a71-73ae-499d-8c15-faa9aef0c3f2',
];

const _knownWriteCharacteristicUuids = <String>[
  '00002af1-0000-1000-8000-00805f9b34fb',
  '0000ff02-0000-1000-8000-00805f9b34fb',
  '0000ae01-0000-1000-8000-00805f9b34fb',
  'bef8d6c9-9c21-4c9e-b632-bd58c1009f9f',
];

class BlePrinterService {
  static final BlePrinterService _instance = BlePrinterService._internal();
  factory BlePrinterService() => _instance;
  BlePrinterService._internal();

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeChar;

  // ===== Adapter state =====

  /// Surface-level check that the native BLE plugin has been properly
  /// registered. If it throws [MissingPluginException] we return false so
  /// the UI can show a clear "rebuild required" message instead of crashing.
  Future<bool> isPluginAvailable() async {
    try {
      await FlutterBluePlus.isSupported;
      return true;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isBluetoothOn() async {
    try {
      if (!await FlutterBluePlus.isSupported) return false;
      final state = await FlutterBluePlus.adapterState.first;
      return state == BluetoothAdapterState.on;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Safe wrapper around the adapter state stream. If the plugin is
  /// unavailable we emit [BluetoothAdapterState.unknown] once so the UI
  /// can react without crashing.
  Stream<BluetoothAdapterState> get adapterStateStream {
    try {
      return FlutterBluePlus.adapterState.handleError((_) {});
    } on MissingPluginException {
      return Stream.value(BluetoothAdapterState.unknown);
    } catch (_) {
      return Stream.value(BluetoothAdapterState.unknown);
    }
  }

  Future<void> requestEnableBluetooth() async {
    try {
      if (await FlutterBluePlus.isSupported) {
        await FlutterBluePlus.turnOn();
      }
    } catch (_) {}
  }

  // ===== Scanning =====

  /// Starts a BLE scan and streams discovered results.
  ///
  /// By default we show **every** BLE device discovered — even ones with
  /// no advertised name — because some thermal printers stop advertising
  /// their name once they enter connectable mode. The UI sorts/filters
  /// further (known-printer hints + RSSI) so the user still sees the
  /// most likely candidate at the top.
  ///
  /// Throws a plain [Exception] with the key `PLUGIN_UNAVAILABLE` if the
  /// native BLE plugin isn't registered yet (usually means the user did a
  /// hot restart after adding the plugin and needs a full rebuild).
  Stream<List<ScanResult>> scanForPrinters({
    Duration timeout = const Duration(seconds: 20),
  }) async* {
    final seen = <String, ScanResult>{};

    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    // Seed the list with any BLE devices the OS already considers
    // "connected" to some other app. Some iOS BLE printers appear here
    // once they've been connected once; without this, the scan might
    // never show them again because the printer stops advertising.
    try {
      for (final d in FlutterBluePlus.connectedDevices) {
        seen['sys_${d.remoteId.str}'] = ScanResult(
          device: d,
          advertisementData: AdvertisementData(
            advName: d.platformName,
            txPowerLevel: null,
            appearance: null,
            connectable: true,
            manufacturerData: const {},
            serviceData: const {},
            serviceUuids: const [],
          ),
          rssi: -40,
          timeStamp: DateTime.now(),
        );
      }
    } catch (_) {}

    try {
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidScanMode: AndroidScanMode.lowLatency,
      );
    } on MissingPluginException {
      throw Exception('PLUGIN_UNAVAILABLE');
    }

    try {
      await for (final results in FlutterBluePlus.scanResults) {
        for (final r in results) {
          final id = r.device.remoteId.str;
          seen[id] = r;
        }
        final sorted = seen.values.toList()
          ..sort((a, b) => b.rssi.compareTo(a.rssi));
        yield sorted;
      }
    } on MissingPluginException {
      throw Exception('PLUGIN_UNAVAILABLE');
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  // ===== Connection =====

  bool get isConnected => _connectedDevice != null && _writeChar != null;

  String? get connectedDeviceId => _connectedDevice?.remoteId.str;

  /// Connects to a BLE printer, discovers services, and picks the best write
  /// characteristic. Returns the characteristic on success.
  ///
  /// Tries, in order:
  ///   1. Matching well-known service+characteristic UUIDs (most reliable).
  ///   2. Any WriteWithoutResponse characteristic (most thermal printers).
  ///   3. Any Write characteristic.
  Future<BluetoothCharacteristic> connect(BluetoothDevice device) async {
    if (_connectedDevice?.remoteId == device.remoteId && _writeChar != null) {
      return _writeChar!;
    }

    await disconnect();

    await device.connect(
      timeout: const Duration(seconds: 12),
      autoConnect: false,
    );

    // Try to negotiate a larger MTU so we can push bigger chunks of data.
    try {
      await device.requestMtu(512);
    } catch (_) {}

    final services = await device.discoverServices();
    BluetoothCharacteristic? chosen;

    // Pass 1: known UUIDs
    for (final service in services) {
      final sUuid = service.uuid.str128.toLowerCase();
      if (!_knownWriteServiceUuids.contains(sUuid)) continue;
      for (final c in service.characteristics) {
        final cUuid = c.uuid.str128.toLowerCase();
        if (_knownWriteCharacteristicUuids.contains(cUuid) &&
            (c.properties.write || c.properties.writeWithoutResponse)) {
          chosen = c;
          break;
        }
      }
      if (chosen != null) break;
    }

    // Pass 2: any WriteWithoutResponse
    if (chosen == null) {
      for (final service in services) {
        for (final c in service.characteristics) {
          if (c.properties.writeWithoutResponse) {
            chosen = c;
            break;
          }
        }
        if (chosen != null) break;
      }
    }

    // Pass 3: any Write
    if (chosen == null) {
      for (final service in services) {
        for (final c in service.characteristics) {
          if (c.properties.write) {
            chosen = c;
            break;
          }
        }
        if (chosen != null) break;
      }
    }

    if (chosen == null) {
      await device.disconnect();
      throw Exception(
          'هیچ کەناڵێکی نووسینی گونجاو نەدۆزرایەوە. پرینتەرەکە پاڵپشتی ناکرێت.');
    }

    _connectedDevice = device;
    _writeChar = chosen;
    return chosen;
  }

  /// Reconnect using just the saved remote ID (used when auto-printing
  /// after a saved pairing). We don't need the ScanResult object again —
  /// we build a BluetoothDevice from the ID directly.
  Future<BluetoothCharacteristic> connectById(String remoteId) async {
    final device = BluetoothDevice.fromId(remoteId);
    return connect(device);
  }

  Future<void> disconnect() async {
    try {
      await _connectedDevice?.disconnect();
    } catch (_) {}
    _connectedDevice = null;
    _writeChar = null;
  }

  // ===== Writing (chunked) =====

  /// Writes raw ESC/POS bytes to the printer in chunks that fit the
  /// negotiated MTU. Uses WriteWithoutResponse when available for speed;
  /// otherwise falls back to Write (acknowledged).
  Future<void> writeBytes(List<int> data) async {
    final c = _writeChar;
    if (c == null || _connectedDevice == null) {
      throw Exception('پەیوەندی لەگەڵ پرینتەر نییە');
    }

    // Defensive chunk size: MTU - 3 (ATT header). Use conservative value.
    int mtu;
    try {
      mtu = await _connectedDevice!.mtu.first;
    } catch (_) {
      mtu = 23;
    }
    final chunkSize = (mtu - 3).clamp(20, 500);

    final useFast = c.properties.writeWithoutResponse;
    for (int i = 0; i < data.length; i += chunkSize) {
      final end =
          (i + chunkSize > data.length) ? data.length : i + chunkSize;
      final chunk = data.sublist(i, end);
      await c.write(chunk, withoutResponse: useFast);
      // A tiny delay prevents the printer's buffer from overflowing,
      // especially for large raster prints.
      if (useFast) {
        await Future.delayed(const Duration(milliseconds: 8));
      }
    }
  }
}

// ===== ESC/POS Raster Encoding =====

/// Converts a PNG byte stream into an ESC/POS GS v 0 raster payload that
/// most 58mm / 80mm thermal printers understand natively. Output includes:
///   - Printer init (ESC @)
///   - Centered align (ESC a 1)
///   - Raster image (GS v 0 m xL xH yL yH ...bitmap)
///   - Line feeds + paper cut (GS V 1)
///
/// [targetWidthPixels] must match the printer's native dot count
/// (384 for 58mm, 576 for 80mm). The image is resized preserving aspect.
Uint8List pngToEscPosRaster(Uint8List pngBytes, int targetWidthPixels) {
  final decoded = img.decodeImage(pngBytes);
  if (decoded == null) {
    throw Exception('نەتوانرا وێنە بخوێنرێتەوە');
  }

  // Resize to exact printer dot width, preserving aspect ratio.
  final resized = decoded.width == targetWidthPixels
      ? decoded
      : img.copyResize(
          decoded,
          width: targetWidthPixels,
          interpolation: img.Interpolation.average,
        );

  // Convert to grayscale then threshold to 1-bit.
  // Using Floyd-Steinberg style error diffusion gives nicer photographs,
  // but for text-heavy receipts a plain threshold is sharper and smaller.
  final gray = img.grayscale(resized);

  final width = gray.width;
  final height = gray.height;
  final bytesPerRow = (width + 7) ~/ 8;

  final raster = Uint8List(bytesPerRow * height);
  int p = 0;
  for (int y = 0; y < height; y++) {
    for (int byteIdx = 0; byteIdx < bytesPerRow; byteIdx++) {
      int byte = 0;
      for (int bit = 0; bit < 8; bit++) {
        final x = byteIdx * 8 + bit;
        if (x < width) {
          final px = gray.getPixel(x, y);
          // In grayscale, all channels carry the same value.
          final lum = px.r.toInt();
          if (lum < 128) {
            byte |= (1 << (7 - bit));
          }
        }
      }
      raster[p++] = byte;
    }
  }

  final out = BytesBuilder();

  // Init printer.
  out.add([0x1B, 0x40]);
  // Left align (most printers center/fill based on paper width anyway).
  out.add([0x1B, 0x61, 0x00]);

  // GS v 0: Print raster bit image.
  // Command: 1D 76 30 m xL xH yL yH  <data>
  //   m = 0  -> Normal mode
  //   xL/xH = bytes-per-row (little-endian)
  //   yL/yH = height in dots (little-endian)
  out.add([
    0x1D,
    0x76,
    0x30,
    0x00,
    bytesPerRow & 0xFF,
    (bytesPerRow >> 8) & 0xFF,
    height & 0xFF,
    (height >> 8) & 0xFF,
  ]);
  out.add(raster);

  // Feed a few lines so the tear bar clears the printed area.
  out.add([0x1B, 0x64, 0x04]);

  // Partial cut (ignored by printers without cutter, harmless).
  out.add([0x1D, 0x56, 0x01]);

  return out.toBytes();
}

/// Attempt to guess whether a scanned device looks like a thermal printer
/// so the UI can highlight it and avoid listing e.g. AirPods.
bool looksLikePrinter(ScanResult r) {
  final name = (r.advertisementData.advName.isNotEmpty
          ? r.advertisementData.advName
          : r.device.platformName)
      .toLowerCase();
  if (name.isEmpty) return false;

  const hints = [
    'print',
    'pos',
    'pt-',
    'mtp',
    'rpp',
    'bt-',
    'hs-',
    'mini',
    'thermal',
    'cashier',
    'x7',
    'd746',
    '58mm',
    '80mm',
    'sprt',
    'zj',
    'gprinter',
  ];
  for (final h in hints) {
    if (name.contains(h)) return true;
  }
  return false;
}

/// Helper to debug-log the services + characteristics of a device after
/// discovery. Useful during printer compatibility testing.
void debugDumpServices(
    String tag, List<BluetoothService> services) {
  if (!kDebugMode) return;
  for (final s in services) {
    debugPrint('$tag service ${s.uuid.str128}');
    for (final c in s.characteristics) {
      final props = <String>[];
      if (c.properties.read) props.add('R');
      if (c.properties.write) props.add('W');
      if (c.properties.writeWithoutResponse) props.add('Wn');
      if (c.properties.notify) props.add('N');
      if (c.properties.indicate) props.add('I');
      debugPrint('  char ${c.uuid.str128} [${props.join(',')}]');
    }
  }
}
