import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/presentation/widgets/app_button.dart';
import 'package:self_control/presentation/widgets/app_card.dart';
import 'package:self_control/presentation/widgets/app_text_field.dart';
import '../test_helpers.dart';

void main() {
  setUpAll(() {
    setupTestFonts();
  });

  group('AppButton Widget Tests', () {
    testWidgets('renders primary button text and handles tap', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppButton(
              text: 'Simpan',
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Simpan'), findsOneWidget);
      await tester.tap(find.text('Simpan'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('displays CircularProgressIndicator when isLoading is true', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppButton(
              text: 'Simpan',
              isLoading: true,
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Simpan'), findsNothing);

      await tester.tap(find.byType(AppButton));
      await tester.pump();
      expect(tapped, isFalse);
    });

    testWidgets('renders secondary and outlineBrown button variants', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: const [
                AppButton(
                  text: 'Secondary',
                  variant: AppButtonVariant.secondary,
                ),
                AppButton(
                  text: 'OutlineBrown',
                  variant: AppButtonVariant.outlineBrown,
                ),
                AppButton(
                  text: 'TextOnly',
                  variant: AppButtonVariant.text,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Secondary'), findsOneWidget);
      expect(find.text('OutlineBrown'), findsOneWidget);
      expect(find.text('TextOnly'), findsOneWidget);
    });
  });

  group('AppCard Widget Tests', () {
    testWidgets('renders content with Peach background and handles tap', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppCard(
              onTap: () => tapped = true,
              child: const Text('Card Content'),
            ),
          ),
        ),
      );

      expect(find.text('Card Content'), findsOneWidget);
      await tester.tap(find.text('Card Content'));
      await tester.pump();
      expect(tapped, isTrue);
    });
  });

  group('AppTextField Widget Tests', () {
    testWidgets('renders label and receives text input', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppTextField(
              label: 'Label Field',
              hint: 'Hint Text',
              controller: controller,
            ),
          ),
        ),
      );

      expect(find.text('Label Field'), findsOneWidget);
      expect(find.text('Hint Text'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'Test Value');
      expect(controller.text, 'Test Value');
    });

    testWidgets('renders error message when errorText is provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppTextField(
              errorText: 'Input tidak valid',
            ),
          ),
        ),
      );

      expect(find.text('Input tidak valid'), findsOneWidget);
    });
  });
}
