import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:whateat/main.dart';

void main() {
  testWidgets('shows login screen when no token', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const WhatEatApp());
    await tester.pumpAndSettle();

    expect(find.text('登录'), findsOneWidget);
  });
}
