import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wetruck_core/wetruck_core.dart';

void main() {
  testWidgets('Wetruck theme builds without errors', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WetruckTheme.light(),
        home: const Scaffold(body: Center(child: Text('Smoke'))),
      ),
    );
    expect(find.text('Smoke'), findsOneWidget);
  });

  // Real end-to-end behavior (auth controller bootstrap, easy_localization
  // asset load, secure storage, router redirect) is verified on a real
  // device. Adding a meaningful in-process widget test would require
  // stubbing every platform plugin — high cost, low return.
}
