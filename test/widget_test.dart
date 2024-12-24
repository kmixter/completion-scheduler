// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:completion_scheduler/main.dart';

void main() {
  testWidgets('Add new item and save', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that the initial list is empty.
    expect(find.byType(ListTile), findsNothing);

    // Tap the '+' icon to add a new item.
    final addButton = find.byIcon(Icons.add);
    await tester.tap(addButton);
    await tester.pump();

    // Verify that a new item is added.
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('<Empty line>'), findsOneWidget);

    // Enter text into the new item.
    await tester.enterText(find.byType(TextField), 'New Task');
    await tester.pump();

    // Verify that the text is updated.
    expect(find.text('New Task'), findsOneWidget);

    // Tap the 'save' icon to save the changes.
    final saveButton = find.byIcon(Icons.save);
    await tester.tap(saveButton);
    await tester.pump();
  });
}
