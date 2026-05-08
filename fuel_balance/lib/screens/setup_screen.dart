import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/flight_provider.dart';
import '../models/flight.dart';
import '../models/aircraft.dart';
import '../services/storage_service.dart';
import 'flight_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _storage = StorageService();

  late TextEditingController _t0Name;
  late TextEditingController _t0Cap;
  late TextEditingController _t0Init;
  late TextEditingController _t1Name;
  late TextEditingController _t1Cap;
  late TextEditingController _t1Init;
  late TextEditingController _fuelFlow;
  late TextEditingController _threshold;
  late int _activeTank;

  List<Aircraft> _aircrafts = [];
  Aircraft? _selectedAircraft;

  @override
  void initState() {
    super.initState();
    final p = context.read<FlightProvider>();
    _t0Name = TextEditingController(text: p.tanks[0].name);
    _t0Cap = TextEditingController(text: p.tanks[0].capacity.toString());
    _t0Init = TextEditingController(text: p.tanks[0].initialFuel.toString());
    _t1Name = TextEditingController(text: p.tanks[1].name);
    _t1Cap = TextEditingController(text: p.tanks[1].capacity.toString());
    _t1Init = TextEditingController(text: p.tanks[1].initialFuel.toString());
    _fuelFlow = TextEditingController(
        text: p.fuelFlow > 0 ? p.fuelFlow.toString() : '');
    _threshold = TextEditingController(text: p.switchThreshold.toString());
    _activeTank = p.activeTankIndex;
    _selectedAircraft = p.selectedAircraft;
    _loadAircrafts();
  }

  Future<void> _loadAircrafts() async {
    final list = await _storage.getAircrafts();
    if (!mounted) return;
    setState(() => _aircrafts = list);
    // Restore the previously selected aircraft object by id
    if (_selectedAircraft != null) {
      final match = list.where((a) => a.id == _selectedAircraft!.id);
      setState(() => _selectedAircraft = match.isNotEmpty ? match.first : null);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _t0Name, _t0Cap, _t0Init, _t1Name, _t1Cap, _t1Init, _fuelFlow, _threshold
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _applyAircraft(Aircraft? aircraft) {
    final p = context.read<FlightProvider>();
    setState(() => _selectedAircraft = aircraft);
    if (aircraft != null) {
      p.selectAircraft(aircraft);
      _t0Cap.text = aircraft.tankCapacity.toStringAsFixed(1);
      _t1Cap.text = aircraft.tankCapacity.toStringAsFixed(1);
      _threshold.text = aircraft.maxTankDiff.toStringAsFixed(1);
    } else {
      p.clearAircraft();
    }
  }

  void _start() {
    if (!_formKey.currentState!.validate()) return;
    final p = context.read<FlightProvider>();

    p.tanks[0] = TankConfig(
      name: _t0Name.text.trim(),
      capacity: double.parse(_t0Cap.text),
      initialFuel: double.parse(_t0Init.text),
    );
    p.tanks[1] = TankConfig(
      name: _t1Name.text.trim(),
      capacity: double.parse(_t1Cap.text),
      initialFuel: double.parse(_t1Init.text),
    );
    // fuelFlow may have been pre-filled or left blank; if blank it starts as 0
    // and the pilot adjusts with the slider in-flight
    p.fuelFlow = double.tryParse(_fuelFlow.text) ?? 0.0;
    p.switchThreshold = double.parse(_threshold.text);
    p.activeTankIndex = _activeTank;

    p.startFlight().then((_) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const FlightScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF071220),
      appBar: AppBar(
        backgroundColor: const Color(0xFF09131F),
        title: const Text(
          'Fuel Balance',
          style: TextStyle(color: Color(0xFFCCE3F5), fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: Color(0xFF8BA7C0)),
            onPressed: () => Navigator.pushNamed(context, '/history'),
            tooltip: 'Histórico',
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // -- Aircraft picker --
            _SectionHeader('Aeronave'),
            const SizedBox(height: 8),
            _Card(
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<Aircraft?>(
                        value: _selectedAircraft,
                        dropdownColor: const Color(0xFF0A1A2E),
                        isExpanded: true,
                        hint: const Text(
                          'Nenhuma',
                          style: TextStyle(color: Color(0xFF5A7A9A), fontSize: 14),
                        ),
                        style: const TextStyle(
                            color: Color(0xFFCCE3F5), fontSize: 14),
                        items: [
                          const DropdownMenuItem<Aircraft?>(
                            value: null,
                            child: Text(
                              'Nenhuma',
                              style: TextStyle(
                                  color: Color(0xFF5A7A9A), fontSize: 14),
                            ),
                          ),
                          ..._aircrafts.map(
                            (a) => DropdownMenuItem<Aircraft?>(
                              value: a,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(a.name,
                                      style: const TextStyle(
                                          color: Color(0xFFCCE3F5),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600)),
                                  Text(a.prefix,
                                      style: const TextStyle(
                                          color: Color(0xFF8BA7C0),
                                          fontSize: 11)),
                                ],
                              ),
                            ),
                          ),
                        ],
                        onChanged: _applyAircraft,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () async {
                      await Navigator.pushNamed(context, '/aircraft');
                      _loadAircrafts();
                    },
                    icon: const Icon(Icons.edit_note,
                        color: Color(0xFF00B0FF), size: 22),
                    tooltip: 'Gerenciar aeronaves',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // -- Tanks --
            _SectionHeader('Tanques'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _TankCard(
                  nameCtrl: _t0Name,
                  capCtrl: _t0Cap,
                  initCtrl: _t0Init,
                )),
                const SizedBox(width: 12),
                Expanded(child: _TankCard(
                  nameCtrl: _t1Name,
                  capCtrl: _t1Cap,
                  initCtrl: _t1Init,
                )),
              ],
            ),
            const SizedBox(height: 20),

            // -- Active tank picker --
            _SectionHeader('Tanque ativo ao decolar'),
            const SizedBox(height: 8),
            Row(
              children: [0, 1].map((i) {
                final selected = _activeTank == i;
                final name = i == 0 ? _t0Name.text : _t1Name.text;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _activeTank = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: EdgeInsets.only(
                          right: i == 0 ? 6 : 0, left: i == 1 ? 6 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF0D2137)
                            : const Color(0xFF0A1A2E),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF00B0FF)
                              : const Color(0xFF1E3A5F),
                          width: selected ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          name.isEmpty ? 'Tanque ${i + 1}' : name,
                          style: TextStyle(
                            color: selected
                                ? const Color(0xFF00B0FF)
                                : const Color(0xFF8BA7C0),
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // -- Flight params --
            _SectionHeader('Parâmetros do Voo'),
            const SizedBox(height: 8),
            _Card(
              child: Column(
                children: [
                  _NumField(
                    label: 'Fuel Flow inicial (GPH)',
                    hint: 'Opcional — ajustável em voo',
                    ctrl: _fuelFlow,
                    required: false,
                  ),
                  const SizedBox(height: 12),
                  _NumField(
                    label: 'Threshold de diferença (gal)',
                    ctrl: _threshold,
                    required: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.flight_takeoff, size: 24),
                label: const Text(
                  'INICIAR VOO',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C853),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _TankCard extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController capCtrl;
  final TextEditingController initCtrl;

  const _TankCard({
    required this.nameCtrl,
    required this.capCtrl,
    required this.initCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        children: [
          _TextField(label: 'Nome', ctrl: nameCtrl),
          const SizedBox(height: 10),
          _NumField(label: 'Capacidade (gal)', ctrl: capCtrl),
          const SizedBox(height: 10),
          _NumField(label: 'Combustível inicial (gal)', ctrl: initCtrl),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1A2E),
        border: Border.all(color: const Color(0xFF1E3A5F)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFF5A7A9A),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;

  const _TextField({required this.label, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: ctrl,
      style: const TextStyle(color: Color(0xFFCCE3F5), fontSize: 15),
      decoration: _inputDec(label),
      validator: (v) => v == null || v.trim().isEmpty ? 'Obrigatório' : null,
    );
  }
}

class _NumField extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController ctrl;
  final bool required;

  const _NumField({
    required this.label,
    this.hint,
    required this.ctrl,
    this.required = true,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: ctrl,
      style: const TextStyle(color: Color(0xFFCCE3F5), fontSize: 15),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      decoration: _inputDec(label, hint: hint),
      validator: required
          ? (v) {
              if (v == null || v.trim().isEmpty) return 'Obrigatório';
              if (double.tryParse(v) == null) return 'Número inválido';
              return null;
            }
          : (v) {
              if (v != null && v.trim().isNotEmpty && double.tryParse(v) == null) {
                return 'Número inválido';
              }
              return null;
            },
    );
  }
}

InputDecoration _inputDec(String label, {String? hint}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle: const TextStyle(color: Color(0xFF5A7A9A), fontSize: 13),
    hintStyle: const TextStyle(color: Color(0xFF2A4A6A), fontSize: 13),
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
      borderSide: const BorderSide(color: Color(0xFF00B0FF), width: 1.5),
    ),
    errorStyle: const TextStyle(color: Color(0xFFFF5252), fontSize: 11),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  );
}
