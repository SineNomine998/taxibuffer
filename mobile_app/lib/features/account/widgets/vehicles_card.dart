import 'package:flutter/material.dart';
import '../../../core/models/vehicle.dart';
import '../../auth/signup/widgets/vehicle_card.dart'; // reuse VehicleCard from signup

class VehiclesCard extends StatelessWidget {
  final List<Vehicle> vehicles;
  final void Function(Vehicle) onSetCurrent;
  final void Function(Vehicle) onRemove;

  const VehiclesCard({
    required this.vehicles,
    required this.onSetCurrent,
    required this.onRemove,
    super.key,
  });

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mijn voertuigen',
            style: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 18,
              color: Color(0xFF222222),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          if (vehicles.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Nog geen voertuigen toegevoegd.',
                style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: Color(0xFF5D1B1B),
                ),
              ),
            )
          else
            for (final v in vehicles)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  children: [
                    VehicleCard(vehicle: v, isCurrent: v.isCurrent),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (!v.isCurrent)
                            _ActionChip(
                              label: 'Maak huidig',
                              onTap: () => onSetCurrent(v),
                            ),
                          if (!v.isCurrent) const SizedBox(width: 8),
                          _ActionChip(
                            label: 'Verwijder',
                            onTap: () => onRemove(v),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ActionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFECECEC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'DM Sans',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF222222),
          ),
        ),
      ),
    );
  }
}
