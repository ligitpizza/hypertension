import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/api_providers.dart';
import '../../auth/state/auth_providers.dart';
import '../data/agent_repository.dart';

final agentRepositoryProvider = Provider<AgentRepository>(
  (ref) => ApiAgentRepository(FirebaseFirestore.instance, ref.watch(apiClientProvider)),
);

/// The signed-in patient's conversation with the agent (live).
final agentMessagesProvider = StreamProvider<List<AgentMessage>>((ref) {
  final uid = ref.watch(authUidProvider).value;
  if (uid == null) return Stream.value(const []);
  return ref.watch(agentRepositoryProvider).messages(uid);
}, retry: (_, _) => null);
