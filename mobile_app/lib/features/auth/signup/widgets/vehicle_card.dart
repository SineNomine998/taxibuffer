import 'package:flutter/material.dart';
import '../../../../core/models/vehicle.dart';

class VehicleCard extends StatelessWidget {
  final Vehicle vehicle;
  final bool isCurrent;

  const VehicleCard({
    required this.vehicle,
    required this.isCurrent,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCurrent ? const Color(0xFFDDBE26) : const Color(0xFFF2F2F2),
        border: isCurrent ? null : Border.all(color: const Color(0xFFC7C9D2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vehicle.nickname,
                  style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isCurrent ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Type: ${_capitalize(vehicle.vehicleType)}',
                  style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 18,
                    color: Color(0xFF4A4A4A),
                  ),
                ),
              ],
            ),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 112),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isCurrent ? Colors.transparent : Colors.white,
              border: Border.all(
                color: isCurrent
                    ? const Color(0xFFF7E79A)
                    : const Color(0xFF6F6F6F),
                width: 2,
              ),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              normalizeLicensePlate(vehicle.licensePlate),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isCurrent ? Colors.white : const Color(0xFF484848),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String normalizeLicensePlate(String value) {
  return value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
}
