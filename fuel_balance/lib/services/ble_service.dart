import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/ble_reading.dart';

class BleService {
  BleService._();
  static final instance = BleService._();

  // Nordic UART Service UUIDs
  static const _serviceUuid = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';
  static const _txUuid = '6E400003-B5A3-F393-E0A9-E50E24DCCA9E';
  static const _rxUuid = '6E400002-B5A3-F393-E0A9-E50E24DCCA9E';
  static const _deviceName = 'AvidyneFF';

  final _statusController = StreamController<BleStatus>.broadcast();
  final _readingController = StreamController<BleReading>.broadcast();

  Stream<BleStatus> get statusStream => _statusController.stream;
  Stream<BleReading> get readingStream => _readingController.stream;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _rxChar;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connStateSub;

  bool _running = false;
  bool _intentionalDisconnect = false;
  int _reconnectDelay = 1;

  // JSON line buffer — BLE may split packets mid-line
  final StringBuffer _lineBuffer = StringBuffer();

  void startScan() {
    if (_running) return;
    _running = true;
    _intentionalDisconnect = false;
    _reconnectDelay = 1;
    _doScan();
  }

  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _running = false;
    await _teardown();
    _statusController.add(BleStatus.disconnected);
  }

  Future<void> _doScan() async {
    if (!_running) return;
    _statusController.add(BleStatus.scanning);

    try {
      // Scan for up to 10 seconds
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
        withNames: [_deviceName],
        withServices: [Guid(_serviceUuid)],
      );

      // Wait for scan results, pick best RSSI
      BluetoothDevice? bestDevice;
      int bestRssi = -999;

      await for (final results in FlutterBluePlus.scanResults
          .timeout(const Duration(seconds: 10), onTimeout: (s) => s.close())) {
        for (final r in results) {
          if (r.device.advName == _deviceName || r.device.advName.isEmpty) {
            if (r.rssi > bestRssi) {
              bestRssi = r.rssi;
              bestDevice = r.device;
            }
          }
        }
      }

      await FlutterBluePlus.stopScan();

      if (!_running) return;

      if (bestDevice != null) {
        await _connect(bestDevice);
      } else {
        // No device found — schedule retry
        await _scheduleReconnect();
      }
    } catch (e) {
      await FlutterBluePlus.stopScan();
      await _scheduleReconnect();
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    if (!_running) return;
    _statusController.add(BleStatus.connecting);
    _device = device;

    try {
      await device.connect(timeout: const Duration(seconds: 10));

      // Listen to connection state changes for auto-reconnect
      _connStateSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && !_intentionalDisconnect) {
          _statusController.add(BleStatus.disconnected);
          _teardown(skipDeviceDisconnect: true).then((_) {
            _scheduleReconnect();
          });
        }
      });

      // Discover services
      final services = await device.discoverServices();
      BluetoothCharacteristic? txChar;
      BluetoothCharacteristic? rxChar;

      for (final svc in services) {
        if (svc.serviceUuid.str128.toUpperCase() == _serviceUuid) {
          for (final c in svc.characteristics) {
            final uuid = c.characteristicUuid.str128.toUpperCase();
            if (uuid == _txUuid) txChar = c;
            if (uuid == _rxUuid) rxChar = c;
          }
        }
      }

      if (txChar == null) {
        await device.disconnect();
        await _scheduleReconnect();
        return;
      }

      _rxChar = rxChar;

      // Subscribe to TX notifications
      await txChar.setNotifyValue(true);
      _notifySub = txChar.lastValueStream.listen(_onData);

      _reconnectDelay = 1; // reset backoff on successful connection
      _statusController.add(BleStatus.connected);
    } catch (e) {
      await _teardown();
      await _scheduleReconnect();
    }
  }

  void _onData(List<int> bytes) {
    if (bytes.isEmpty) return;
    final chunk = utf8.decode(bytes, allowMalformed: true);
    _lineBuffer.write(chunk);

    final raw = _lineBuffer.toString();
    final lines = raw.split('\n');

    // All complete lines except the last (which may be incomplete)
    for (int i = 0; i < lines.length - 1; i++) {
      final line = lines[i].trim();
      if (line.isNotEmpty) _parseLine(line);
    }

    // Keep the remainder (possibly incomplete line)
    _lineBuffer.clear();
    _lineBuffer.write(lines.last);
  }

  void _parseLine(String line) {
    try {
      final Map<String, dynamic> json = jsonDecode(line) as Map<String, dynamic>;

      // Heartbeat — no reading
      if (json.containsKey('hb')) return;

      final v = json['v'] as int?;
      if (v != 1) return; // invalid/low-confidence reading

      final espT = json['t'] as int?;
      final ff = (json['ff'] as num?)?.toDouble();
      final conf = (json['c'] as num?)?.toInt() ?? 0;

      if (espT == null || ff == null) return;

      _readingController.add(BleReading(
        espT: espT,
        ffGph: ff,
        confidence: conf,
        wallClock: DateTime.now(),
      ));
    } catch (_) {
      // Malformed JSON — discard line
    }
  }

  Future<void> _teardown({bool skipDeviceDisconnect = false}) async {
    await _notifySub?.cancel();
    _notifySub = null;
    await _connStateSub?.cancel();
    _connStateSub = null;
    _rxChar = null;
    _lineBuffer.clear();

    if (!skipDeviceDisconnect && _device != null) {
      try {
        await _device!.disconnect();
      } catch (_) {}
    }
    _device = null;
  }

  Future<void> _scheduleReconnect() async {
    if (!_running || _intentionalDisconnect) return;
    _statusController.add(BleStatus.disconnected);

    await Future.delayed(Duration(seconds: _reconnectDelay));

    // Exponential backoff: 1, 2, 4, 8, 30 (cap)
    _reconnectDelay = (_reconnectDelay * 2).clamp(1, 30);

    if (_running && !_intentionalDisconnect) {
      await _doScan();
    }
  }

  Future<void> sendResetVote() async {
    if (_rxChar == null) return;
    try {
      final payload = utf8.encode('{"cmd":"reset_vote"}\n');
      await _rxChar!.write(payload, withoutResponse: false);
    } catch (_) {}
  }
}
