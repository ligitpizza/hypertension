import 'package:flutter/material.dart';

import '../../features/provider_portal/domain/portal_models.dart';

/// D-50: doctor-issued prescriptions are blue, patient-reported ones green, everywhere.
Color prescriptionColor(Prescription p) =>
    p.byPatient ? Colors.green.shade600 : Colors.blue.shade600;

/// The small coloured label under a prescription; wording depends on who is looking.
class PrescriptionSourceChip extends StatelessWidget {
  const PrescriptionSourceChip({super.key, required this.prescription, required this.forDoctor});

  final Prescription prescription;
  final bool forDoctor;

  @override
  Widget build(BuildContext context) {
    final color = prescriptionColor(prescription);
    final text = prescription.byPatient
        ? (forDoctor ? 'Reported by patient' : 'Added by you')
        : (forDoctor ? 'Doctor-issued' : 'From your doctor');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}
