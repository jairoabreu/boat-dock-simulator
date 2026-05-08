import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/flight.dart';

class SwitchLog extends StatelessWidget {
  final List<SwitchRecord> records;
  final List<TankConfig> tanks;

  const SwitchLog({super.key, required this.records, required this.tanks});

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Nenhuma troca registrada',
          style: TextStyle(color: Color(0xFF5A7A9A), fontSize: 13),
        ),
      );
    }

    final fmt = DateFormat('HH:mm:ss');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: records.reversed.map((r) {
        final from = tanks[r.fromTankIndex].name;
        final to = tanks[r.toTankIndex].name;
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1A2E),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF1E3A5F)),
          ),
          child: Row(
            children: [
              Text(
                fmt.format(r.timestamp),
                style: const TextStyle(
                  color: Color(0xFF8BA7C0),
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$from → $to  •  −${r.consumedFromTank.toStringAsFixed(1)} gal',
                  style: const TextStyle(
                    color: Color(0xFFCCE3F5),
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                '${r.totalConsumedAtSwitch.toStringAsFixed(1)} gal total',
                style: const TextStyle(
                  color: Color(0xFF5A7A9A),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
