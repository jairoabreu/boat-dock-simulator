import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/aircraft.dart';
import '../services/storage_service.dart';

class AircraftScreen extends StatefulWidget {
  const AircraftScreen({super.key});

  @override
  State<AircraftScreen> createState() => _AircraftScreenState();
}

class _AircraftScreenState extends State<AircraftScreen> {
  final _storage = StorageService();
  List<Aircraft> _aircrafts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _storage.getAircrafts();
    if (mounted) setState(() { _aircrafts = list; _loading = false; });
  }

  Future<void> _openForm({Aircraft? aircraft}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AircraftForm(
        storage: _storage,
        aircraft: aircraft,
      ),
    );
    if (result == true) _load();
  }

  Future<void> _confirmDelete(Aircraft aircraft) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Excluir aeronave',
          style: TextStyle(color: Color(0xFFCCE3F5)),
        ),
        content: Text(
          'Deseja excluir "${aircraft.name} (${aircraft.prefix})"?',
          style: const TextStyle(color: Color(0xFF8BA7C0)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar',
                style: TextStyle(color: Color(0xFF5A7A9A))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD50000),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Excluir',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed == true && aircraft.id != null) {
      await _storage.deleteAircraft(aircraft.id!);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF071220),
      appBar: AppBar(
        backgroundColor: const Color(0xFF09131F),
        title: const Text(
          'Aeronaves',
          style: TextStyle(
              color: Color(0xFFCCE3F5), fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF8BA7C0)),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        backgroundColor: const Color(0xFF00B0FF),
        foregroundColor: Colors.black,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00B0FF)))
          : _aircrafts.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.airplanemode_inactive,
                          color: Color(0xFF2A4A6A), size: 64),
                      SizedBox(height: 16),
                      Text(
                        'Nenhuma aeronave cadastrada',
                        style: TextStyle(
                            color: Color(0xFF5A7A9A), fontSize: 15),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Toque em + para adicionar',
                        style: TextStyle(
                            color: Color(0xFF2A4A6A), fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _aircrafts.length,
                  itemBuilder: (context, index) {
                    final a = _aircrafts[index];
                    return _AircraftTile(
                      aircraft: a,
                      onTap: () => _openForm(aircraft: a),
                      onLongPress: () => _confirmDelete(a),
                    );
                  },
                ),
    );
  }
}

class _AircraftTile extends StatelessWidget {
  final Aircraft aircraft;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _AircraftTile({
    required this.aircraft,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1A2E),
          border: Border.all(color: const Color(0xFF1E3A5F)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.flight, color: Color(0xFF00B0FF), size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    aircraft.name,
                    style: const TextStyle(
                      color: Color(0xFFCCE3F5),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    aircraft.prefix,
                    style: const TextStyle(
                        color: Color(0xFF8BA7C0), fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _Chip(
                          label:
                              'Flow: ${aircraft.fuelFlowMin.toStringAsFixed(0)}–${aircraft.fuelFlowMax.toStringAsFixed(0)} GPH'),
                      const SizedBox(width: 8),
                      _Chip(
                          label:
                              'Diff: ${aircraft.maxTankDiff.toStringAsFixed(0)} gal'),
                      const SizedBox(width: 8),
                      _Chip(
                          label:
                              'Cap: ${aircraft.tankCapacity.toStringAsFixed(0)} gal'),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF2A4A6A)),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF071220),
        border: Border.all(color: const Color(0xFF1E3A5F)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Color(0xFF5A7A9A), fontSize: 11),
      ),
    );
  }
}

// ---- Form sheet ----

class _AircraftForm extends StatefulWidget {
  final StorageService storage;
  final Aircraft? aircraft;

  const _AircraftForm({required this.storage, this.aircraft});

  @override
  State<_AircraftForm> createState() => _AircraftFormState();
}

class _AircraftFormState extends State<_AircraftForm> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _name;
  late TextEditingController _prefix;
  late TextEditingController _flowMin;
  late TextEditingController _flowMax;
  late TextEditingController _maxDiff;
  late TextEditingController _capacity;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final a = widget.aircraft;
    _name = TextEditingController(text: a?.name ?? '');
    _prefix = TextEditingController(text: a?.prefix ?? '');
    _flowMin = TextEditingController(
        text: a != null ? a.fuelFlowMin.toStringAsFixed(1) : '');
    _flowMax = TextEditingController(
        text: a != null ? a.fuelFlowMax.toStringAsFixed(1) : '');
    _maxDiff = TextEditingController(
        text: a != null ? a.maxTankDiff.toStringAsFixed(1) : '');
    _capacity = TextEditingController(
        text: a != null ? a.tankCapacity.toStringAsFixed(1) : '');
  }

  @override
  void dispose() {
    for (final c in [_name, _prefix, _flowMin, _flowMax, _maxDiff, _capacity]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final aircraft = Aircraft(
      id: widget.aircraft?.id,
      name: _name.text.trim(),
      prefix: _prefix.text.trim().toUpperCase(),
      fuelFlowMin: double.parse(_flowMin.text),
      fuelFlowMax: double.parse(_flowMax.text),
      maxTankDiff: double.parse(_maxDiff.text),
      tankCapacity: double.parse(_capacity.text),
    );

    if (widget.aircraft == null) {
      await widget.storage.insertAircraft(aircraft);
    } else {
      await widget.storage.updateAircraft(aircraft);
    }

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.aircraft != null;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  isEdit ? 'Editar aeronave' : 'Nova aeronave',
                  style: const TextStyle(
                    color: Color(0xFFCCE3F5),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Color(0xFF5A7A9A)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _FormField(label: 'Nome', ctrl: _name, hint: 'ex: Cessna 172'),
            const SizedBox(height: 12),
            _FormField(
              label: 'Prefixo',
              ctrl: _prefix,
              hint: 'ex: PP-AAA',
              uppercase: true,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _NumFormField(
                    label: 'Flow mín. (GPH)',
                    ctrl: _flowMin,
                    hint: 'ex: 6',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _NumFormField(
                    label: 'Flow máx. (GPH)',
                    ctrl: _flowMax,
                    hint: 'ex: 14',
                    extraValidator: (v) {
                      final min = double.tryParse(_flowMin.text);
                      final max = double.tryParse(v ?? '');
                      if (min != null && max != null && max <= min) {
                        return 'Máx > mín';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _NumFormField(
                    label: 'Diff. máx. (gal)',
                    ctrl: _maxDiff,
                    hint: 'ex: 10',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _NumFormField(
                    label: 'Cap. tanque (gal)',
                    ctrl: _capacity,
                    hint: 'ex: 28',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00B0FF),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.black, strokeWidth: 2),
                      )
                    : Text(
                        isEdit ? 'SALVAR' : 'CADASTRAR',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final String? hint;
  final bool uppercase;

  const _FormField({
    required this.label,
    required this.ctrl,
    this.hint,
    this.uppercase = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: ctrl,
      textCapitalization:
          uppercase ? TextCapitalization.characters : TextCapitalization.words,
      style: const TextStyle(color: Color(0xFFCCE3F5), fontSize: 15),
      decoration: _dec(label, hint: hint),
      validator: (v) =>
          v == null || v.trim().isEmpty ? 'Obrigatório' : null,
    );
  }
}

class _NumFormField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final String? hint;
  final String? Function(String?)? extraValidator;

  const _NumFormField({
    required this.label,
    required this.ctrl,
    this.hint,
    this.extraValidator,
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
      decoration: _dec(label, hint: hint),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Obrigatório';
        if (double.tryParse(v) == null) return 'Inválido';
        if (extraValidator != null) return extraValidator!(v);
        return null;
      },
    );
  }
}

InputDecoration _dec(String label, {String? hint}) {
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
