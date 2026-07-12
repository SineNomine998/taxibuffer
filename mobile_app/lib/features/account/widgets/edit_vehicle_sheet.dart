import 'package:flutter/material.dart';

import '../../../core/models/vehicle.dart';
import '../../../widgets/primary_pill_button.dart';
import '../../../widgets/secondary_pill_button.dart';

class EditVehicleSheet extends StatefulWidget {
  final Vehicle vehicle;

  const EditVehicleSheet({super.key, required this.vehicle});

  @override
  State<EditVehicleSheet> createState() => _EditVehicleSheetState();
}

class _EditVehicleSheetState extends State<EditVehicleSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _licensePlateController;
  late final TextEditingController _nicknameController;
  late String _vehicleType;

  @override
  void initState() {
    super.initState();

    _licensePlateController = TextEditingController(
      text: widget.vehicle.licensePlate,
    );

    _nicknameController = TextEditingController(text: widget.vehicle.nickname);

    _vehicleType = widget.vehicle.vehicleType;
  }

  @override
  void dispose() {
    _licensePlateController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final updated = Vehicle(
      id: widget.vehicle.id,
      licensePlate: _licensePlateController.text.trim().toUpperCase(),
      nickname: _nicknameController.text.trim(),
      vehicleType: _vehicleType,
      isCurrent: widget.vehicle.isCurrent,
    );

    Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1D5DB),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                const Text(
                  'Voertuig bewerken',
                  style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Pas de gegevens van uw voertuig aan.',
                  style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 14,
                    color: Color(0xFF4B5563),
                  ),
                ),
                const SizedBox(height: 22),

                TextFormField(
                  controller: _licensePlateController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Kenteken',
                    hintText: 'Bijv. TX-123-B',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Vul een kenteken in.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _nicknameController,
                  decoration: const InputDecoration(
                    labelText: 'Naam voertuig',
                    hintText: 'Bijv. Taxi 1',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Vul een naam in.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                DropdownButtonFormField<String>(
                  initialValue: _vehicleType,
                  decoration: const InputDecoration(labelText: 'Voertuigtype'),
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('Auto')),
                    DropdownMenuItem(value: 'busje', child: Text('Busje')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _vehicleType = value);
                  },
                ),

                const SizedBox(height: 24),

                PrimaryPillButton(label: 'Opslaan', onPressed: _save),
                const SizedBox(height: 10),
                SecondaryPillButton(
                  label: 'Annuleren',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
