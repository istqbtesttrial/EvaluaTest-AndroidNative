import 'package:evaluatest_androidnative/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders login screen widget', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          usernameController: TextEditingController(),
          passwordController: TextEditingController(),
          rememberMe: true,
          loginError: null,
          onRememberChanged: (_) {},
          onLogin: () {},
        ),
      ),
    );

    expect(find.text('Connexion'), findsOneWidget);
    expect(find.text('Entrer dans l’espace élève'), findsOneWidget);
  });
}
