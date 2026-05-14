enum BleStatus { disconnected, scanning, connecting, connected }

enum SensorSignal { ok, stale, offline }

class BleReading {
  final int espT;
  final double ffGph;
  final int confidence;
  final DateTime wallClock;

  const BleReading({
    required this.espT,
    required this.ffGph,
    required this.confidence,
    required this.wallClock,
  });
}
