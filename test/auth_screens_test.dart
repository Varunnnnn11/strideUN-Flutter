import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aurarun_app/screens/forgot_password_screen.dart';
import 'package:aurarun_app/screens/login_screen.dart';
import 'package:aurarun_app/screens/register_screen.dart';

// flutter test renders text in the blocky "Ahem" font, which is far wider than
// the real fonts, so harmless RenderFlex overflow reports are ignored here.
void _ignoreOverflow() {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  _ignoreOverflow();
  tester.view.physicalSize = const Size(1080, 2400); // phone-sized, tall enough
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('login: renders and rejects empty fields before any network call',
      (tester) async {
    await _pump(tester, const LoginScreen());
    expect(find.text('LOGIN'), findsOneWidget);

    await tester.tap(find.text('LOGIN'));
    await tester.pump();
    expect(find.text('Please enter username and password'), findsOneWidget);
  });

  testWidgets('register: validates username, email and password locally',
      (tester) async {
    await _pump(tester, const RegisterScreen());
    final create = find.text('CREATE ACCOUNT').last;
    final fields = find.byType(TextField);

    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pump();
    expect(find.text('Username must be at least 3 characters'), findsOneWidget);

    await tester.enterText(fields.at(0), 'runner1');
    await tester.tap(create);
    await tester.pump();
    expect(find.text('Email is required'), findsOneWidget);

    await tester.enterText(fields.at(1), 'not-an-email');
    await tester.tap(create);
    await tester.pump();
    expect(find.text('Please enter a valid email'), findsOneWidget);

    await tester.enterText(fields.at(1), 'runner1@example.com');
    await tester.enterText(fields.at(2), '123');
    await tester.tap(create);
    await tester.pump();
    expect(find.text('Password must be at least 6 characters'), findsOneWidget);

    await tester.enterText(fields.at(2), 'secret1');
    await tester.enterText(fields.at(3), 'different');
    await tester.tap(create);
    await tester.pump();
    expect(find.text('Passwords do not match'), findsOneWidget);
  });

  testWidgets('forgot password: renders the email form', (tester) async {
    await _pump(tester, const ForgotPasswordScreen());
    expect(find.text('SEND RESET LINK'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}
