import 'package:flutter/material.dart';
import '../../../core/models/vehicle.dart';
import '../../../widgets/shell_text_field.dart';
import '../../../widgets/primary_pill_button.dart';

class AddVehicleCard extends StatefulWidget {
  final Future<void> Function(Vehicle) onAdd;
  const AddVehicleCard({required this.onAdd, super.key});

  @override
  State<AddVehicleCard> createState() => _AddVehicleCardState();
}

class _AddVehicleCardState extends State<AddVehicleCard> {
  GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final _nicknameController = TextEditingController();
  final _plateController = TextEditingController();
  String _vehicleType = 'auto';
  bool _setAsCurrent = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _nicknameController.dispose();
    _plateController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSaving) return;

    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() => _isSaving = true);
    
    try {
      await widget.onAdd(
        Vehicle(
          nickname: _nicknameController.text.trim(),
          licensePlate: _plateController.text.trim(),
          vehicleType: _vehicleType,
          isCurrent: _setAsCurrent,
        ),
      );

      if (!mounted) return;

      FocusScope.of(context).unfocus();

      _nicknameController.clear();
      _plateController.clear();

      setState(() {
        _vehicleType = 'auto';
        _setAsCurrent = false;
        _formKey = GlobalKey<FormState>();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6F8),
        border: Border.all(color: const Color(0xFFC9CCD5)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Voertuig toevoegen',
              style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 18,
                color: Color(0xFF222222),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            ShellTextField(
              label: 'Geef een naam voor dit voertuig*',
              hint: 'Taxi 1',
              controller: _nicknameController,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Verplicht veld' : null,
            ),
            const SizedBox(height: 14),
            ShellTextField(
              label: 'Kenteken*',
              hint: '38HTTS',
              controller: _plateController,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Verplicht veld' : null,
            ),
            const SizedBox(height: 14),
            const Text(
              'Voertuigtype*',
              style: TextStyle(
                fontFamily: 'DM Sans',
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Color(0xFF222222),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF1F1F1),
                border: Border.all(color: const Color(0xFFA9ACB9)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _vehicleType,
                  isExpanded: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  items: const [
                    DropdownMenuItem(
                      value: 'auto',
                      child: Text(
                        'Auto',
                        style: TextStyle(fontFamily: 'DM Sans', fontSize: 15),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'busje',
                      child: Text(
                        'Busje',
                        style: TextStyle(fontFamily: 'DM Sans', fontSize: 15),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _vehicleType = v ?? 'auto'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Checkbox(
                  value: _setAsCurrent,
                  onChanged: (v) => setState(() => _setAsCurrent = v ?? false),
                  activeColor: const Color(0xFFE0BD22),
                ),
                const Expanded(
                  child: Text(
                    'Maak dit mijn huidige voertuig',
                    style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF222222),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            PrimaryPillButton(
              label: _isSaving ? 'Bezig...' : 'Opslaan',
              onPressed: _isSaving ? () {} : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
