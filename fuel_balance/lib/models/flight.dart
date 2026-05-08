class TankConfig {
  String name;
  double capacity;
  double initialFuel;
  double consumed;

  TankConfig({
    required this.name,
    required this.capacity,
    required this.initialFuel,
    this.consumed = 0.0,
  });

  double get remaining => initialFuel - consumed;

  Map<String, dynamic> toMap() => {
        'name': name,
        'capacity': capacity,
        'initialFuel': initialFuel,
        'consumed': consumed,
      };

  factory TankConfig.fromMap(Map<String, dynamic> m) => TankConfig(
        name: m['name'] as String,
        capacity: (m['capacity'] as num).toDouble(),
        initialFuel: (m['initialFuel'] as num).toDouble(),
        consumed: (m['consumed'] as num).toDouble(),
      );

  TankConfig copyWith({
    String? name,
    double? capacity,
    double? initialFuel,
    double? consumed,
  }) =>
      TankConfig(
        name: name ?? this.name,
        capacity: capacity ?? this.capacity,
        initialFuel: initialFuel ?? this.initialFuel,
        consumed: consumed ?? this.consumed,
      );
}

class SwitchRecord {
  final DateTime timestamp;
  final double totalConsumedAtSwitch;
  final int fromTankIndex;
  final int toTankIndex;
  final double consumedFromTank;

  const SwitchRecord({
    required this.timestamp,
    required this.totalConsumedAtSwitch,
    required this.fromTankIndex,
    required this.toTankIndex,
    required this.consumedFromTank,
  });

  Map<String, dynamic> toMap(int flightId) => {
        'flightId': flightId,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'totalConsumedAtSwitch': totalConsumedAtSwitch,
        'fromTankIndex': fromTankIndex,
        'toTankIndex': toTankIndex,
        'consumedFromTank': consumedFromTank,
      };

  factory SwitchRecord.fromMap(Map<String, dynamic> m) => SwitchRecord(
        timestamp: DateTime.fromMillisecondsSinceEpoch(m['timestamp'] as int),
        totalConsumedAtSwitch: (m['totalConsumedAtSwitch'] as num).toDouble(),
        fromTankIndex: m['fromTankIndex'] as int,
        toTankIndex: m['toTankIndex'] as int,
        consumedFromTank: (m['consumedFromTank'] as num).toDouble(),
      );
}

class FlightLog {
  final int? id;
  final DateTime startTime;
  final DateTime? endTime;
  final List<TankConfig> tanks;
  final double fuelFlow;
  final double switchThreshold;
  final int activeTankIndex;
  final double totalConsumed;
  final List<SwitchRecord> switchRecords;

  const FlightLog({
    this.id,
    required this.startTime,
    this.endTime,
    required this.tanks,
    required this.fuelFlow,
    required this.switchThreshold,
    required this.activeTankIndex,
    required this.totalConsumed,
    required this.switchRecords,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'startTime': startTime.millisecondsSinceEpoch,
        'endTime': endTime?.millisecondsSinceEpoch,
        'tank0Name': tanks[0].name,
        'tank0Capacity': tanks[0].capacity,
        'tank0Initial': tanks[0].initialFuel,
        'tank0Consumed': tanks[0].consumed,
        'tank1Name': tanks[1].name,
        'tank1Capacity': tanks[1].capacity,
        'tank1Initial': tanks[1].initialFuel,
        'tank1Consumed': tanks[1].consumed,
        'fuelFlow': fuelFlow,
        'switchThreshold': switchThreshold,
        'activeTankIndex': activeTankIndex,
        'totalConsumed': totalConsumed,
      };

  factory FlightLog.fromMap(Map<String, dynamic> m, List<SwitchRecord> records) =>
      FlightLog(
        id: m['id'] as int?,
        startTime: DateTime.fromMillisecondsSinceEpoch(m['startTime'] as int),
        endTime: m['endTime'] != null
            ? DateTime.fromMillisecondsSinceEpoch(m['endTime'] as int)
            : null,
        tanks: [
          TankConfig(
            name: m['tank0Name'] as String,
            capacity: (m['tank0Capacity'] as num).toDouble(),
            initialFuel: (m['tank0Initial'] as num).toDouble(),
            consumed: (m['tank0Consumed'] as num).toDouble(),
          ),
          TankConfig(
            name: m['tank1Name'] as String,
            capacity: (m['tank1Capacity'] as num).toDouble(),
            initialFuel: (m['tank1Initial'] as num).toDouble(),
            consumed: (m['tank1Consumed'] as num).toDouble(),
          ),
        ],
        fuelFlow: (m['fuelFlow'] as num).toDouble(),
        switchThreshold: (m['switchThreshold'] as num).toDouble(),
        activeTankIndex: m['activeTankIndex'] as int,
        totalConsumed: (m['totalConsumed'] as num).toDouble(),
        switchRecords: records,
      );
}
