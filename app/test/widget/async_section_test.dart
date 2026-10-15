import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hypertension/features/provider_portal/presentation/portal_widgets.dart';

// Doctor patient page sections (Fig 4.3.12.4): a stream that errors after delivering data
// (e.g. a listener cut off mid-session) keeps showing the last data.

void main() {
  testWidgets('a later stream error keeps the last data on screen', (t) async {
    final controller = StreamController<String>();
    final provider = StreamProvider.autoDispose<String>(
      (ref) => controller.stream,
      retry: (_, _) => null,
    );
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Consumer(
            builder: (_, ref, _) =>
                AsyncSection<String>(value: ref.watch(provider), builder: Text.new),
          ),
        ),
      ),
    );
    controller.add('120/80');
    await t.pumpAndSettle();
    expect(find.text('120/80'), findsOneWidget);
    controller.addError(Exception('permission-denied'));
    await t.pumpAndSettle();
    expect(find.text('120/80'), findsOneWidget);
    expect(find.textContaining('Could not load'), findsNothing);
    await controller.close();
  });

  testWidgets('an error with no data yet is still reported', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: AsyncSection<String>(
          value: AsyncError<String>(Exception('x'), StackTrace.empty),
          builder: Text.new,
        ),
      ),
    );
    expect(find.textContaining('Could not load this section'), findsOneWidget);
  });
}
