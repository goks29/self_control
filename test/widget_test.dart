import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:self_control/main.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('SelfControlApp builds and renders root MaterialApp', (WidgetTester tester) async {
    await tester.pumpWidget(const SelfControlApp());
    expect(find.byType(SelfControlApp), findsOneWidget);
  });
}
