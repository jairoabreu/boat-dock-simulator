import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../providers/flight_provider.dart';
import '../widgets/tank_gauge.dart';
import '../widgets/switch_log.dart';

class FlightScreen extends StatefulWidget {
  const FlightScreen({super.key});

  @override
  State<FlightScreen> createState() => _FlightScreenState();
}

class _FlightScreenState extends State<FlightScreen> {
  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Future<void> _showSwitchDialog(FlightProvider p) async {
    final totalCtrl = TextEditingController(
      text: p.totalConsumed > 0 ? p.totalConsumed.toStringAsFixed(1) : '',
    );
    DateTime switchTime = DateTime.now();
    bool editTime = false;
    final hourCtrl = TextEditingController(
        text: switchTime.hour.toString().padLeft(2, '0'));
    final minCtrl = TextEditingController(
        text: switchTime.minute.toString().padLeft(2, '0'));

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: const Color(0xFF0A1A2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Registrar Troca de Tanque',
            style: TextStyle(color: Color(0xFFCCE3F5), fontSize: 18),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Combustível total consumido no voo (gal):',
                  style: TextStyle(color: Color(0xFF8BA7C0), fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: totalCtrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  style: const TextStyle(
                    color: Color(0xFFCCE3F5),
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF071220),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF1E3A5F)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF1E3A5F)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Color(0xFF00B0FF), width: 1.5),
                    ),
                    suffixText: 'gal',
                    suffixStyle: const TextStyle(color: Color(0xFF5A7A9A)),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      'Horário da troca:',
                      style: TextStyle(color: Color(0xFF8BA7C0), fontSize: 13),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setDlg(() => editTime = !editTime),
                      child: Text(
                        editTime ? 'Usar atual' : 'Editar',
                        style: const TextStyle(color: Color(0xFF00B0FF)),
                      ),
                    ),
                  ],
                ),
                if (!editTime)
                  Text(
                    DateFormat('HH:mm:ss').format(switchTime),
                    style: const TextStyle(
                      color: Color(0xFFCCE3F5),
                      fontSize: 18,
                      fontFamily: 'monospace',
                    ),
                  )
                else
                  Row(
                    children: [
                      SizedBox(
                        width: 60,
                        child: TextField(
                          controller: hourCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(2),
                          ],
                          style: const TextStyle(color: Color(0xFFCCE3F5)),
                          decoration: _smallDec('HH'),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Text(':',
                            style: TextStyle(
                                color: Color(0xFF8BA7C0), fontSize: 20)),
                      ),
                      SizedBox(
                        width: 60,
                        child: TextField(
                          controller: minCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(2),
                          ],
                          style: const TextStyle(color: Color(0xFFCCE3F5)),
                          decoration: _smallDec('MM'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar',
                  style: TextStyle(color: Color(0xFF5A7A9A))),
            ),
            ElevatedButton(
              onPressed: () {
                final val = double.tryParse(totalCtrl.text);
                if (val == null) return;
                DateTime? override;
                if (editTime) {
                  final h = int.tryParse(hourCtrl.text) ?? switchTime.hour;
                  final m = int.tryParse(minCtrl.text) ?? switchTime.minute;
                  final now = DateTime.now();
                  override = DateTime(now.year, now.month, now.day, h, m);
                }
                Navigator.pop(context);
                p.recordSwitch(
                  totalConsumedInput: val,
                  overrideTime: override,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00B0FF),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Confirmar Troca',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEndDialog(FlightProvider p) async {
    final totalCtrl = TextEditingController(
      text: p.totalConsumed > 0 ? p.totalConsumed.toStringAsFixed(1) : '',
    );

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Encerrar Voo',
          style: TextStyle(color: Color(0xFFCCE3F5)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Combustível total consumido no voo (gal):',
              style: TextStyle(color: Color(0xFF8BA7C0), fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: totalCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              style: const TextStyle(
                color: Color(0xFFCCE3F5),
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF071220),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF1E3A5F)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: Color(0xFF00C853), width: 1.5),
                ),
                suffixText: 'gal',
                suffixStyle: const TextStyle(color: Color(0xFF5A7A9A)),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar',
                style: TextStyle(color: Color(0xFF5A7A9A))),
          ),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(totalCtrl.text) ?? p.totalConsumed;
              Navigator.pop(context);
              p.endFlight(totalConsumedFinal: val).then((_) {
                if (mounted) {
                  Navigator.pushNamedAndRemoveUntil(
                      context, '/', (_) => false);
                }
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD50000),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Encerrar',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF071220),
      appBar: AppBar(
        backgroundColor: const Color(0xFF09131F),
        automaticallyImplyLeading: false,
        title: Consumer<FlightProvider>(
          builder: (context, p, child) => Row(
            children: [
              const Icon(Icons.flight, color: Color(0xFF00C853), size: 20),
              const SizedBox(width: 8),
              Text(
                _formatDuration(p.elapsed),
                style: const TextStyle(
                  color: Color(0xFFCCE3F5),
                  fontFamily: 'monospace',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        actions: [
          Consumer<FlightProvider>(
            builder: (context, p, child) => TextButton.icon(
              onPressed: () => _showEndDialog(p),
              icon: const Icon(Icons.flight_land, color: Color(0xFFFF5252)),
              label: const Text('Encerrar',
                  style: TextStyle(color: Color(0xFFFF5252))),
            ),
          ),
        ],
      ),
      body: Consumer<FlightProvider>(
        builder: (context, p, child) {
          final diff = p.tankDiff;
          final overThreshold = diff >= p.switchThreshold;

          return Column(
            children: [
              // Diff banner
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                color: overThreshold
                    ? const Color(0xFFD50000).withValues(alpha: 0.15)
                    : const Color(0xFF071220),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      overThreshold
                          ? Icons.warning_amber_rounded
                          : Icons.balance,
                      color: overThreshold
                          ? const Color(0xFFFF5252)
                          : const Color(0xFF5A7A9A),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Diferença: ${diff.toStringAsFixed(1)} gal',
                      style: TextStyle(
                        color: overThreshold
                            ? const Color(0xFFFF5252)
                            : const Color(0xFF8BA7C0),
                        fontSize: 15,
                        fontWeight: overThreshold
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    if (overThreshold) ...[
                      const SizedBox(width: 8),
                      const Text('• TROCAR TANQUE',
                          style: TextStyle(
                              color: Color(0xFFFF5252),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5)),
                    ],
                  ],
                ),
              ),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Tank gauges
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TankGauge(
                            tank: p.tanks[0],
                            isActive: p.activeTankIndex == 0,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TankGauge(
                            tank: p.tanks[1],
                            isActive: p.activeTankIndex == 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Stats row
                    Row(
                      children: [
                        _StatBox(
                          label: 'Total consumido',
                          value: '${p.totalConsumed.toStringAsFixed(1)} gal',
                        ),
                        const SizedBox(width: 10),
                        _StatBox(
                          label: 'Tanque ativo',
                          value: p.activeTank.name,
                          highlight: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Fuel flow + estimation
                    _FuelFlowCard(provider: p),
                    const SizedBox(height: 20),

                    // Switch button
                    SizedBox(
                      height: 64,
                      child: ElevatedButton.icon(
                        onPressed: () => _showSwitchDialog(p),
                        icon: const Icon(Icons.swap_horiz, size: 28),
                        label: const Text(
                          'TROCAR TANQUE',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: overThreshold
                              ? const Color(0xFFD50000)
                              : const Color(0xFF00B0FF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Switch log
                    const _SectionLabel('Histórico de Trocas'),
                    const SizedBox(height: 8),
                    SwitchLog(
                        records: p.switchRecords, tanks: p.tanks),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _StatBox({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1A2E),
          border: Border.all(
            color: highlight
                ? const Color(0xFF00B0FF).withValues(alpha: 0.5)
                : const Color(0xFF1E3A5F),
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF5A7A9A), fontSize: 11)),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: highlight
                    ? const Color(0xFF00B0FF)
                    : const Color(0xFFCCE3F5),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FuelFlowCard extends StatefulWidget {
  final FlightProvider provider;
  const _FuelFlowCard({required this.provider});

  @override
  State<_FuelFlowCard> createState() => _FuelFlowCardState();
}

class _FuelFlowCardState extends State<_FuelFlowCard> {
  late TextEditingController _ctrl;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: widget.provider.fuelFlow > 0
            ? widget.provider.fuelFlow.toString()
            : '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _fmtDuration(Duration d) {
    if (d.isNegative || d == Duration.zero) return 'agora';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}min';
    return '${m}min';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.provider;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1A2E),
        border: Border.all(color: const Color(0xFF1E3A5F)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _SectionLabel('Fuel Flow'),
              const Spacer(),
              if (!_editing)
                TextButton(
                  onPressed: () => setState(() => _editing = true),
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Editar',
                      style: TextStyle(
                          color: Color(0xFF00B0FF), fontSize: 13)),
                )
              else
                TextButton(
                  onPressed: () {
                    final v = double.tryParse(_ctrl.text) ?? 0.0;
                    p.updateFuelFlow(v);
                    setState(() => _editing = false);
                  },
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Salvar',
                      style: TextStyle(
                          color: Color(0xFF00C853), fontSize: 13)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_editing)
            TextField(
              controller: _ctrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              style: const TextStyle(color: Color(0xFFCCE3F5), fontSize: 18),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF071220),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF1E3A5F)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: Color(0xFF00B0FF), width: 1.5),
                ),
                suffixText: 'GPH',
                suffixStyle:
                    const TextStyle(color: Color(0xFF5A7A9A)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
              ),
            )
          else if (p.fuelFlow <= 0)
            const Text(
              'Não configurado — estimativas desativadas',
              style: TextStyle(color: Color(0xFF5A7A9A), fontSize: 13),
            )
          else ...[
            Text(
              '${p.fuelFlow.toStringAsFixed(1)} GPH',
              style: const TextStyle(
                color: Color(0xFFCCE3F5),
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            _EstRow(
              icon: Icons.swap_horiz,
              label: 'Próxima troca',
              value: p.estimatedSwitchTime != null
                  ? DateFormat('HH:mm').format(p.estimatedSwitchTime!)
                  : '--',
              sub: p.estimatedTimeToSwitch != null
                  ? '(em ${_fmtDuration(p.estimatedTimeToSwitch!)})'
                  : '',
            ),
            const SizedBox(height: 6),
            _EstRow(
              icon: Icons.hourglass_bottom,
              label: '${p.activeTank.name} esvazia em',
              value: p.estimatedActiveTankEmpty != null
                  ? _fmtDuration(p.estimatedActiveTankEmpty!)
                  : '--',
            ),
          ],
        ],
      ),
    );
  }
}

class _EstRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String sub;

  const _EstRow({
    required this.icon,
    required this.label,
    required this.value,
    this.sub = '',
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF5A7A9A), size: 16),
        const SizedBox(width: 6),
        Text(label,
            style:
                const TextStyle(color: Color(0xFF8BA7C0), fontSize: 13)),
        const SizedBox(width: 8),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFFCCE3F5),
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (sub.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(sub,
              style:
                  const TextStyle(color: Color(0xFF5A7A9A), fontSize: 12)),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFF5A7A9A),
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }
}

InputDecoration _smallDec(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFF2A4A6A)),
    filled: true,
    fillColor: const Color(0xFF071220),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: Color(0xFF1E3A5F)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: Color(0xFF00B0FF), width: 1.5),
    ),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  );
}
