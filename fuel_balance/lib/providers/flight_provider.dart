import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/flight.dart';
import '../models/aircraft.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';

enum FlightPhase { idle, active, finished }

class FlightProvider extends ChangeNotifier {
  final StorageService _storage;
  final NotificationService _notif;

  FlightProvider(this._storage, this._notif);

  FlightPhase phase = FlightPhase.idle;

  // Config (pre-flight)
  List<TankConfig> tanks = [
    TankConfig(name: 'Esquerdo', capacity: 50, initialFuel: 50),
    TankConfig(name: 'Direito', capacity: 50, initialFuel: 50),
  ];
  double fuelFlow = 0.0;
  double switchThreshold = 10.0;
  int activeTankIndex = 0;

  // Aircraft
  Aircraft? selectedAircraft;

  // Active flight state
  int? _flightId;
  DateTime? _startTime;
  DateTime? _lastEventTime;
  double _totalConsumedAtLastSwitch = 0.0;
  double _totalConsumedNow = 0.0;
  final List<SwitchRecord> _switchRecords = [];
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  // Derived for display
  Duration get elapsed => _elapsed;
  double get totalConsumed => _totalConsumedNow;
  TankConfig get activeTank => tanks[activeTankIndex];
  TankConfig get inactiveTank => tanks[1 - activeTankIndex];
  double get tankDiff => (tanks[0].remaining - tanks[1].remaining).abs();
  List<SwitchRecord> get switchRecords => List.unmodifiable(_switchRecords);

  // Aircraft-derived limits
  double get fuelFlowMin => selectedAircraft?.fuelFlowMin ?? 5.0;
  double get fuelFlowMax => selectedAircraft?.fuelFlowMax ?? 50.0;

  // Real-time estimation since the last event (start or switch)
  double get estimatedConsumedSinceLastEvent {
    if (fuelFlow <= 0 || _lastEventTime == null) return 0;
    final secs = DateTime.now().difference(_lastEventTime!).inSeconds;
    return (fuelFlow / 3600) * secs;
  }

  double get estimatedActiveTankRemaining =>
      (activeTank.remaining - estimatedConsumedSinceLastEvent)
          .clamp(0.0, double.infinity);

  double get estimatedTankDiff {
    if (fuelFlow <= 0) return tankDiff;
    return (estimatedActiveTankRemaining - inactiveTank.remaining).abs();
  }

  /// Total consumido no voo incluindo o consumo estimado desde a última troca
  double get estimatedTotalConsumed => _totalConsumedNow + estimatedConsumedSinceLastEvent;

  // Estimation (only when fuelFlow > 0)
  Duration? get estimatedTimeToSwitch {
    if (fuelFlow <= 0) return null;
    final diff = estimatedTankDiff;
    final active = estimatedActiveTankRemaining;
    final inactive = inactiveTank.remaining;
    final double minutesToThreshold;
    if (active > inactive) {
      // Active is heavier — consuming it reduces imbalance
      final gapToClose = diff - switchThreshold;
      if (gapToClose <= 0) return Duration.zero;
      minutesToThreshold = gapToClose / (fuelFlow / 60);
    } else {
      // Active is lighter — consuming it increases imbalance
      minutesToThreshold =
          (switchThreshold - diff).clamp(0, double.infinity) / (fuelFlow / 60);
    }
    return Duration(seconds: (minutesToThreshold * 60).round());
  }

  DateTime? get estimatedSwitchTime {
    final dur = estimatedTimeToSwitch;
    if (dur == null) return null;
    return DateTime.now().add(dur);
  }

  Duration? get estimatedActiveTankEmpty {
    if (fuelFlow <= 0) return null;
    final minutes = estimatedActiveTankRemaining / (fuelFlow / 60);
    return Duration(seconds: (minutes * 60).round());
  }

  // --- Aircraft selection ---

  void selectAircraft(Aircraft a) {
    selectedAircraft = a;
    switchThreshold = a.maxTankDiff;
    tanks[0] = tanks[0].copyWith(capacity: a.tankCapacity);
    tanks[1] = tanks[1].copyWith(capacity: a.tankCapacity);
    notifyListeners();
  }

  void clearAircraft() {
    selectedAircraft = null;
    notifyListeners();
  }

  // --- Flight lifecycle ---

  Future<void> startFlight() async {
    _startTime = DateTime.now();
    _lastEventTime = _startTime;
    _elapsed = Duration.zero;
    _totalConsumedAtLastSwitch = 0.0;
    _totalConsumedNow = 0.0;
    _switchRecords.clear();

    for (final t in tanks) {
      t.consumed = 0.0;
    }

    final log = FlightLog(
      startTime: _startTime!,
      tanks: tanks.map((t) => t.copyWith()).toList(),
      fuelFlow: fuelFlow,
      switchThreshold: switchThreshold,
      activeTankIndex: activeTankIndex,
      totalConsumed: 0,
      switchRecords: const [],
    );
    _flightId = await _storage.insertFlight(log);

    _ticker = Timer.periodic(const Duration(seconds: 1), _tick);
    phase = FlightPhase.active;
    notifyListeners();

    await _saveConfig();
  }

  void _tick(Timer _) {
    _elapsed = DateTime.now().difference(_startTime!);
    _checkNotifications();
    notifyListeners();
  }

  bool _thresholdNotified = false;
  bool _warningNotified = false;

  void _checkNotifications() {
    final diff = estimatedTankDiff;
    if (diff >= switchThreshold && !_thresholdNotified) {
      _thresholdNotified = true;
      _notif.showCritical(
        id: kNotifThreshold,
        title: 'Desequilíbrio de combustível',
        body:
            'Diferença de ${diff.toStringAsFixed(1)} gal. Considere trocar o tanque.',
      );
    } else if (diff < switchThreshold * 0.8) {
      _thresholdNotified = false;
    }

    final est = estimatedTimeToSwitch;
    if (est != null &&
        est.inMinutes <= 5 &&
        est.inMinutes >= 0 &&
        !_warningNotified) {
      _warningNotified = true;
      _notif.showImmediate(
        id: kNotifSwitchWarning,
        title: 'Troca de tanque em breve',
        body:
            'Troque para o tanque ${inactiveTank.name} em aprox. ${est.inMinutes} min.',
      );
    } else if (est == null || est.inMinutes > 6) {
      _warningNotified = false;
    }
  }

  Future<void> recordSwitch({
    required double totalConsumedInput,
    DateTime? overrideTime,
  }) async {
    final switchTime = overrideTime ?? DateTime.now();
    final consumedSinceLast = totalConsumedInput - _totalConsumedAtLastSwitch;

    tanks[activeTankIndex].consumed += consumedSinceLast;
    _totalConsumedNow = totalConsumedInput;
    _totalConsumedAtLastSwitch = totalConsumedInput;

    // Reset real-time estimation baseline from this confirmed switch point
    _lastEventTime = switchTime;

    final record = SwitchRecord(
      timestamp: switchTime,
      totalConsumedAtSwitch: totalConsumedInput,
      fromTankIndex: activeTankIndex,
      toTankIndex: 1 - activeTankIndex,
      consumedFromTank: consumedSinceLast,
    );
    _switchRecords.add(record);

    activeTankIndex = 1 - activeTankIndex;
    _thresholdNotified = false;
    _warningNotified = false;

    if (_flightId != null) {
      await _storage.insertSwitchRecord(record, _flightId!);
      await _persistFlight();
    }
    notifyListeners();
  }

  Future<void> endFlight({required double totalConsumedFinal}) async {
    final consumedSinceLast = totalConsumedFinal - _totalConsumedAtLastSwitch;
    tanks[activeTankIndex].consumed += consumedSinceLast;
    _totalConsumedNow = totalConsumedFinal;

    _ticker?.cancel();
    _ticker = null;
    phase = FlightPhase.finished;

    await _notif.cancelAll();
    await _persistFlight(endTime: DateTime.now());
    notifyListeners();
  }

  Future<void> _persistFlight({DateTime? endTime}) async {
    if (_flightId == null) return;
    final log = FlightLog(
      id: _flightId,
      startTime: _startTime!,
      endTime: endTime,
      tanks: tanks.map((t) => t.copyWith()).toList(),
      fuelFlow: fuelFlow,
      switchThreshold: switchThreshold,
      activeTankIndex: activeTankIndex,
      totalConsumed: _totalConsumedNow,
      switchRecords: _switchRecords,
    );
    await _storage.updateFlight(log);
  }

  void updateFuelFlow(double value) {
    fuelFlow = value;
    _warningNotified = false;
    notifyListeners();
  }

  Future<void> _saveConfig() async {
    await _storage.savePref('tank0Name', tanks[0].name);
    await _storage.savePref('tank0Capacity', tanks[0].capacity.toString());
    await _storage.savePref('tank0Initial', tanks[0].initialFuel.toString());
    await _storage.savePref('tank1Name', tanks[1].name);
    await _storage.savePref('tank1Capacity', tanks[1].capacity.toString());
    await _storage.savePref('tank1Initial', tanks[1].initialFuel.toString());
    await _storage.savePref('fuelFlow', fuelFlow.toString());
    await _storage.savePref('switchThreshold', switchThreshold.toString());
    await _storage.savePref('activeTankIndex', activeTankIndex.toString());
  }

  Future<void> loadLastConfig() async {
    final t0Name = await _storage.getPref('tank0Name');
    if (t0Name == null) return;
    tanks[0] = TankConfig(
      name: t0Name,
      capacity: double.tryParse(await _storage.getPref('tank0Capacity') ?? '') ?? 50,
      initialFuel:
          double.tryParse(await _storage.getPref('tank0Initial') ?? '') ?? 50,
    );
    tanks[1] = TankConfig(
      name: await _storage.getPref('tank1Name') ?? 'Direito',
      capacity: double.tryParse(await _storage.getPref('tank1Capacity') ?? '') ?? 50,
      initialFuel:
          double.tryParse(await _storage.getPref('tank1Initial') ?? '') ?? 50,
    );
    fuelFlow = double.tryParse(await _storage.getPref('fuelFlow') ?? '') ?? 0;
    switchThreshold =
        double.tryParse(await _storage.getPref('switchThreshold') ?? '') ?? 10;
    activeTankIndex =
        int.tryParse(await _storage.getPref('activeTankIndex') ?? '') ?? 0;
    notifyListeners();
  }

  void resetToIdle() {
    _ticker?.cancel();
    _ticker = null;
    phase = FlightPhase.idle;
    _flightId = null;
    _startTime = null;
    _lastEventTime = null;
    _elapsed = Duration.zero;
    _totalConsumedNow = 0;
    _totalConsumedAtLastSwitch = 0;
    _switchRecords.clear();
    _thresholdNotified = false;
    _warningNotified = false;
    for (final t in tanks) {
      t.consumed = 0;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
