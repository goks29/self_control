import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/main.dart';

void main() {
  testWidgets('unsupported platform does not initialize database or channel', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      AppBootstrap(
        isSupported: false,
        initialize: () async {
          calls++;
          return null;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Platform belum didukung'), findsOneWidget);
    expect(find.byType(SelfControlApp), findsNothing);
  });

  testWidgets('startup error is visible and retry reruns initialization', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      AppBootstrap(
        isSupported: true,
        initialize: () async {
          calls++;
          throw StateError('migration failed');
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Gagal menyiapkan aplikasi'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('Coba Lagi'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });
}
