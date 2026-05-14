import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/ble_reading.dart';
import '../services/ble_service.dart';

class BleProvider extends ChangeNotifier {
  final BleService _service = BleService.instance;

  StreamSubscription<BleStatus>? _statusSub;
  StreamSubscription<BleReading>? _readingSub;
  Timer? _signalTimer;

  BleStatus status = BleStatus.disconnected;
  SensorSignal signal = SensorSignal.offline;
  double? lastFf;
  int? lastConfidence;
  DateTime? lastReadingAt;

  bool get isConnected => status == BleStatus.connected;
  bool get isReceivingValidData =>
      signal == SensorSignal.ok && lastFf != null;

  Stream<BleReading> get readingStream => _service.readingStream;

  BleProvider() {
    _statusSub = _service.statusStream.listen((s) {
      status = s;
      if (s == BleStatus.disconnected) {
        signal = SensorSignal.offline;
      }
      notifyListeners();
    });

    _readingSub = _service.readingStream.listen((reading) {
      lastFf = reading.ffGph;
      lastConfidence = reading.confidence;
      lastReadingAt = reading.wallClock;
      _updateSignal();
      notifyListeners();
    });

    // Every 5 seconds, update signal staleness
    _signalTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _updateSignal();
      notifyListeners();
    });
  }

  void _updateSignal() {
    if (lastReadingAt == null) {
      signal = SensorSignal.offline;
      return;
    }
    final age = DateTime.now().difference(lastReadingAt!).inSeconds;
    if (age < 5) {
      signal = SensorSignal.ok;
    } else if (age <= 60) {
      signal = SensorSignal.stale;
    } else {
      signal = SensorSignal.offline;
    }
  }

  void startScan() {
    _service.startScan();
    status = BleStatus.scanning;
    notifyListeners();
  }

  Future<void> disconnect() async {
    await _service.disconnect();
    lastFf = null;
    lastConfidence = null;
    lastReadingAt = null;
    signal = SensorSignal.offline;
    notifyListeners();
  }

  Future<void> sendResetVote() async {
    await _service.sendResetVote();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _readingSub?.cancel();
    _signalTimer?.cancel();
    super.dispose();
  }
}
