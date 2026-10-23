import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:global_frequency_explorer/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('offline tuner starts with FM band and local-only status', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const OfflineFrequencyApp());
    await tester.pump();
    expect(find.text('OFFLINE FREQUENCY'), findsOneWidget);
    expect(find.text('FM BROADCAST BAND'), findsOneWidget);
    expect(find.text('87.5 — 108.0'), findsOneWidget);
  });
}
