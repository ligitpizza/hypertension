import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/health_models.dart';
import '../../dashboard/state/dashboard_providers.dart';
import '../data/trends_repository.dart';
import '../domain/trend_logic.dart';

final trendsRepositoryProvider = Provider<TrendsRepository>(
  (ref) => FirestoreTrendsRepository(FirebaseFirestore.instance),
);

Duration? _noRetry(int _, Object _) => null;

/// Readings for one patient and timeframe (UC4.1 A1: switching re-renders in place).
final readingsInRangeProvider = StreamProvider.family<List<VitalReading>, (String, TrendRange)>((
  ref,
  args,
) {
  final (patientId, range) = args;
  final now = ref.watch(nowProvider)();
  return ref.watch(trendsRepositoryProvider).readingsSince(patientId, range.startFrom(now));
}, retry: _noRetry);

final riskHistoryProvider = StreamProvider.family<List<RiskScore>, String>(
  (ref, patientId) => ref.watch(trendsRepositoryProvider).riskHistory(patientId),
  retry: _noRetry,
);
