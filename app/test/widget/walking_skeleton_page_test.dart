import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hypertension/shared/providers/api_providers.dart';
import 'package:hypertension/shared/services/api/api_client.dart';
import 'package:hypertension/shared/widgets/walking_skeleton_page.dart';

Widget _wrap(Future<Map<String, dynamic>> Function() health) => ProviderScope(
      overrides: [apiHealthProvider.overrideWith((ref) => health())],
      child: const MaterialApp(home: WalkingSkeletonPage(title: 'CareFlow')),
    );

void main() {
  testWidgets('Inc0 walking skeleton shows loading while health check runs', (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(_wrap(() => pending.future));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete({'status': 'ok'});
    await tester.pumpAndSettle();
  });

  testWidgets('Inc0 walking skeleton shows API status on success', (tester) async {
    await tester.pumpWidget(_wrap(() async => {'status': 'ok', 'version': '0.1.0'}));
    await tester.pumpAndSettle();
    expect(find.text('API status: ok'), findsOneWidget);
    expect(find.text('Version: 0.1.0'), findsOneWidget);
  });

  testWidgets('Inc0 walking skeleton shows error and retry when unreachable', (tester) async {
    await tester.pumpWidget(
      _wrap(() async => throw ApiException('NETWORK_ERROR', 'Connection refused')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('health-error')), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
