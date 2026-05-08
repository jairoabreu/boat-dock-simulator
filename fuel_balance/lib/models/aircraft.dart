class Aircraft {
  final int? id;
  final String name;
  final String prefix;
  final double fuelFlowMin;
  final double fuelFlowMax;
  final double maxTankDiff;
  final double tankCapacity;

  const Aircraft({
    this.id,
    required this.name,
    required this.prefix,
    required this.fuelFlowMin,
    required this.fuelFlowMax,
    required this.maxTankDiff,
    required this.tankCapacity,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'prefix': prefix,
        'fuelFlowMin': fuelFlowMin,
        'fuelFlowMax': fuelFlowMax,
        'maxTankDiff': maxTankDiff,
        'tankCapacity': tankCapacity,
      };

  factory Aircraft.fromMap(Map<String, dynamic> m) => Aircraft(
        id: m['id'] as int?,
        name: m['name'] as String,
        prefix: m['prefix'] as String,
        fuelFlowMin: (m['fuelFlowMin'] as num).toDouble(),
        fuelFlowMax: (m['fuelFlowMax'] as num).toDouble(),
        maxTankDiff: (m['maxTankDiff'] as num).toDouble(),
        tankCapacity: (m['tankCapacity'] as num).toDouble(),
      );

  Aircraft copyWith({
    int? id,
    String? name,
    String? prefix,
    double? fuelFlowMin,
    double? fuelFlowMax,
    double? maxTankDiff,
    double? tankCapacity,
  }) =>
      Aircraft(
        id: id ?? this.id,
        name: name ?? this.name,
        prefix: prefix ?? this.prefix,
        fuelFlowMin: fuelFlowMin ?? this.fuelFlowMin,
        fuelFlowMax: fuelFlowMax ?? this.fuelFlowMax,
        maxTankDiff: maxTankDiff ?? this.maxTankDiff,
        tankCapacity: tankCapacity ?? this.tankCapacity,
      );

  @override
  String toString() => '$name ($prefix)';
}
