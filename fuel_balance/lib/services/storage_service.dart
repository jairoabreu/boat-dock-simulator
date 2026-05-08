import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/flight.dart';

class StorageService {
  static Database? _db;

  Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'fuel_balance.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE flights (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            startTime INTEGER NOT NULL,
            endTime INTEGER,
            tank0Name TEXT NOT NULL,
            tank0Capacity REAL NOT NULL,
            tank0Initial REAL NOT NULL,
            tank0Consumed REAL NOT NULL DEFAULT 0,
            tank1Name TEXT NOT NULL,
            tank1Capacity REAL NOT NULL,
            tank1Initial REAL NOT NULL,
            tank1Consumed REAL NOT NULL DEFAULT 0,
            fuelFlow REAL NOT NULL DEFAULT 0,
            switchThreshold REAL NOT NULL DEFAULT 10,
            activeTankIndex INTEGER NOT NULL DEFAULT 0,
            totalConsumed REAL NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE switch_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            flightId INTEGER NOT NULL,
            timestamp INTEGER NOT NULL,
            totalConsumedAtSwitch REAL NOT NULL,
            fromTankIndex INTEGER NOT NULL,
            toTankIndex INTEGER NOT NULL,
            consumedFromTank REAL NOT NULL,
            FOREIGN KEY (flightId) REFERENCES flights(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE prefs (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Future<int> insertFlight(FlightLog flight) async {
    final database = await db;
    return database.insert('flights', flight.toMap());
  }

  Future<void> updateFlight(FlightLog flight) async {
    final database = await db;
    await database.update(
      'flights',
      flight.toMap(),
      where: 'id = ?',
      whereArgs: [flight.id],
    );
  }

  Future<void> insertSwitchRecord(SwitchRecord record, int flightId) async {
    final database = await db;
    await database.insert('switch_records', record.toMap(flightId));
  }

  Future<List<FlightLog>> getFlightHistory() async {
    final database = await db;
    final rows = await database.query(
      'flights',
      orderBy: 'startTime DESC',
    );
    final List<FlightLog> result = [];
    for (final row in rows) {
      final id = row['id'] as int;
      final switchRows = await database.query(
        'switch_records',
        where: 'flightId = ?',
        whereArgs: [id],
        orderBy: 'timestamp ASC',
      );
      final records = switchRows.map(SwitchRecord.fromMap).toList();
      result.add(FlightLog.fromMap(row, records));
    }
    return result;
  }

  Future<void> savePref(String key, String value) async {
    final database = await db;
    await database.insert(
      'prefs',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getPref(String key) async {
    final database = await db;
    final rows = await database.query(
      'prefs',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }
}
