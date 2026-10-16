import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/order_models.dart';
import '../state/orders_providers.dart';

/// D-70 pharmacy Patients tab: every patient (like the admin user list, patients only),
/// each opening the dispensing view.
class PharmacyPatientsPage extends ConsumerStatefulWidget {
  const PharmacyPatientsPage({super.key});

  @override
  ConsumerState<PharmacyPatientsPage> createState() => _PharmacyPatientsPageState();
}

class _PharmacyPatientsPageState extends ConsumerState<PharmacyPatientsPage> {
  String _query = '';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(pharmacyLookupProvider(_query));
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Patients', style: Theme.of(context).textTheme.headlineSmall),
        const Text('Open a patient to see dispensing details or message them.'),
        const SizedBox(height: 12),
        TextField(
          key: const Key('patients-search'),
          controller: _search,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Name, email, IC or patient ID',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => setState(() => _query = v.trim()),
        ),
        const SizedBox(height: 12),
        list.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => TextButton(
            onPressed: () => ref.invalidate(pharmacyLookupProvider(_query)),
            child: const Text('Could not load patients. Retry'),
          ),
          data: (patients) => patients.isEmpty
              ? const Padding(
                  key: Key('patients-empty'),
                  padding: EdgeInsets.all(16),
                  child: Text('No patient matches.'),
                )
              : Card(
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      key: const Key('patients-table'),
                      showCheckboxColumn: false,
                      columns: const [
                        DataColumn(label: Text('Name')),
                        DataColumn(label: Text('Email')),
                        DataColumn(label: Text('Age / gender')),
                        DataColumn(label: Text('Orders'), numeric: true),
                        DataColumn(label: Text('Active orders'), numeric: true),
                        DataColumn(label: Text('Account')),
                      ],
                      rows: [
                        for (final PharmacyPatient p in patients)
                          DataRow(
                            key: ValueKey('patient-${p.id}'),
                            onSelectChanged: (_) => context.go('/pharmacy/patients/${p.id}'),
                            cells: [
                              DataCell(Text(p.name)),
                              DataCell(Text(p.email ?? '—')),
                              DataCell(
                                Text([if (p.age != null) '${p.age}', ?p.gender].join(' · ')),
                              ),
                              DataCell(Text('${p.orderCount}')),
                              DataCell(Text('${p.activeOrders}')),
                              DataCell(Text(p.isActive ? 'Active' : 'Deactivated')),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
