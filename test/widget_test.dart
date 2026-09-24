import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ur_terminal/ui/theme.dart';
import 'package:ur_terminal/ui/widgets.dart';

void main() {
  testWidgets('EmptyState renders title and message', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const Scaffold(
        body: EmptyState(
          icon: Icons.dns_outlined,
          title: 'No hosts yet',
          message: 'Add a server',
        ),
      ),
    ));
    expect(find.text('No hosts yet'), findsOneWidget);
    expect(find.text('Add a server'), findsOneWidget);
  });
}
