import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/flight.dart';
import '../services/storage_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _storage = StorageService();
  List<FlightLog>? _flights;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final logs = await _storage.getFlightHistory();
    if (mounted) setState(() => _flights = logs);
  }

  String _duration(FlightLog log) {
    if (log.endTime == null) return 'Em andamento';
    final d = log.endTime!.difference(log.startTime);
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}min' : '${m}min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF071220),
      appBar: AppBar(
        backgroundColor: const Color(0xFF09131F),
        title: const Text(
          'Histórico de Voos',
          style: TextStyle(color: Color(0xFFCCE3F5)),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF8BA7C0)),
      ),
      body: _flights == null
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00B0FF)))
          : _flights!.isEmpty
              ? const Center(
                  child: Text(
                    'Nenhum voo registrado',
                    style: TextStyle(color: Color(0xFF5A7A9A), fontSize: 16),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _flights!.length,
                  itemBuilder: (_, i) => _FlightCard(
                    log: _flights![i],
                    duration: _duration(_flights![i]),
                  ),
                ),
    );
  }
}

class _FlightCard extends StatefulWidget {
  final FlightLog log;
  final String duration;

  const _FlightCard({required this.log, required this.duration});

  @override
  State<_FlightCard> createState() => _FlightCardState();
}

class _FlightCardState extends State<_FlightCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1A2E),
        border: Border.all(color: const Color(0xFF1E3A5F)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.flight, color: Color(0xFF5A7A9A), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dateFmt.format(log.startTime),
                          style: const TextStyle(
                            color: Color(0xFFCCE3F5),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Duração: ${widget.duration}  •  ${log.totalConsumed.toStringAsFixed(1)} gal consumidos',
                          style: const TextStyle(
                            color: Color(0xFF8BA7C0),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: const Color(0xFF5A7A9A),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(color: Color(0xFF1E3A5F), height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tank summary
                  Row(
                    children: log.tanks.map((t) {
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF071220),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: const Color(0xFF1E3A5F)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.name,
                                  style: const TextStyle(
                                    color: Color(0xFF8BA7C0),
                                    fontSize: 12,
                                  )),
                              const SizedBox(height: 4),
                              Text(
                                '${t.consumed.toStringAsFixed(1)} gal consumidos',
                                style: const TextStyle(
                                  color: Color(0xFFCCE3F5),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Restante: ${t.remaining.toStringAsFixed(1)} gal',
                                style: const TextStyle(
                                  color: Color(0xFF5A7A9A),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (log.switchRecords.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'TROCAS',
                      style: TextStyle(
                        color: Color(0xFF5A7A9A),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...log.switchRecords.map((r) {
                      final from = log.tanks[r.fromTankIndex].name;
                      final to = log.tanks[r.toTankIndex].name;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Text(
                              DateFormat('HH:mm:ss').format(r.timestamp),
                              style: const TextStyle(
                                color: Color(0xFF5A7A9A),
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$from → $to  •  −${r.consumedFromTank.toStringAsFixed(1)} gal',
                              style: const TextStyle(
                                color: Color(0xFF8BA7C0),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
