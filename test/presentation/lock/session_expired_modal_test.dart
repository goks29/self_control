import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/presentation/lock/widgets/session_expired_modal.dart';
import '../test_helpers.dart';

void main() {
  setUpAll(() {
    setupTestFonts();
  });

  group('SessionExpiredModal Tests', () {
    testWidgets('renders verbatim copy and Kembali button dismisses dialog', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SessionExpiredModal.show(context),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Akses Berakhir'), findsOneWidget);
      expect(
        find.text('Waktu akses sementara telah berakhir. Aplikasi kembali dibatasi.'),
        findsOneWidget,
      );
      expect(find.text('Kembali'), findsOneWidget);

      await tester.tap(find.text('Kembali'));
      await tester.pumpAndSettle();

      expect(find.byType(SessionExpiredModal), findsNothing);
    });
  });
}
