import 'package:flutter/material.dart';

import '../../../../core/constants/enums.dart';

/// Role selector from Figs 4.3.1.1 / 4.3.14.8. Must match the account (D-26).
class RoleToggle extends StatelessWidget {
  const RoleToggle({
    super.key,
    required this.roles,
    required this.selected,
    required this.onChanged,
    this.showIcons = true,
  });

  final List<UserRole> roles;
  final UserRole selected;
  final ValueChanged<UserRole> onChanged;

  /// Fig 4.3.1.1 shows icons; the staff portal (Fig 4.3.14.8) does not.
  final bool showIcons;

  static String label(UserRole r) => switch (r) {
    UserRole.patient => 'Patient',
    UserRole.familyMember => 'Family',
    UserRole.doctor => 'Doctor',
    UserRole.pharmacist => 'Pharmacist',
    UserRole.admin => 'Admin',
  };

  static IconData icon(UserRole r) => switch (r) {
    UserRole.patient => Icons.person,
    UserRole.familyMember => Icons.family_restroom,
    UserRole.doctor => Icons.medical_services_outlined,
    UserRole.pharmacist => Icons.local_pharmacy_outlined,
    UserRole.admin => Icons.admin_panel_settings_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Select your role',
      child: SegmentedButton<UserRole>(
        showSelectedIcon: false,
        segments: [
          for (final r in roles)
            ButtonSegment(
              value: r,
              label: Text(label(r), maxLines: 1, softWrap: false),
              icon: showIcons ? Icon(icon(r)) : null,
            ),
        ],
        selected: {selected},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}
