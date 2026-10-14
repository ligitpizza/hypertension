import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/prescription_style.dart';
import '../../auth/state/auth_providers.dart';
import '../domain/portal_models.dart';
import '../state/portal_providers.dart';
import 'portal_widgets.dart';

/// A prescription in the doctor's views: blue when doctor-issued, green when reported by
/// the patient (D-50). The issuing doctor can delete their own (development use).
class PortalPrescriptionTile extends ConsumerWidget {
  const PortalPrescriptionTile({super.key, required this.prescription, required this.patientId});

  final Prescription prescription;
  final String patientId;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete prescription?'),
        content: Text(prescription.medicationDetails),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('rx-delete-confirm'),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(portalRepositoryProvider).deletePrescription(patientId, prescription.id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not delete the prescription.')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = prescription;
    final mine =
        !p.byPatient && p.doctorId != null && p.doctorId == ref.watch(authUidProvider).value;
    final color = prescriptionColor(p);
    return ListTile(
      key: Key('portal-rx-${p.id}'),
      dense: true,
      leading: Container(width: 4, height: 36, color: color),
      title: Text(p.medicationDetails),
      subtitle: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${p.byPatient ? 'Recorded' : 'Issued'} ${formatDate(p.issuedAt)}'
            '${p.isRecurring ? ' · recurring' : ''}',
          ),
          PrescriptionSourceChip(prescription: p, forDoctor: true),
        ],
      ),
      trailing: mine
          ? IconButton(
              key: Key('rx-delete-${p.id}'),
              tooltip: 'Delete prescription',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context, ref),
            )
          : null,
    );
  }
}
