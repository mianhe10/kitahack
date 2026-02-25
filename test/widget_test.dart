// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:kitahack/main.dart';

void main() {
  testWidgets('Home Screen UI smoke test', (WidgetTester tester) async {
    // 1. Build our app and trigger a frame.
    await tester.pumpWidget(const KitaHackApp());

    // 2. Verify that our specific UI elements are present.
    // Check for the App Bar title
    expect(find.text('Pricing Intel'), findsOneWidget);

    // Check for the AI Recommendation header
    expect(find.text('AI RECOMMENDATION'), findsOneWidget);

    // 3. Test interaction: Tap the "View Analysis" button
    // This replaces the "Icons.add" tap that was causing the error
    await tester.tap(find.text('View Analysis →'));
    await tester.pump(); // Rebuild the widget after the tap
  });
}
