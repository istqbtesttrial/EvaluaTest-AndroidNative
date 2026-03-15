import 'package:evaluatest_androidnative/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders native home shell', (WidgetTester tester) async {
    await tester.pumpWidget(const EvaluaTestApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('EvaluaTest Native'), findsWidgets);
    expect(find.text('Voir la prochaine étape'), findsOneWidget);
  });
}
