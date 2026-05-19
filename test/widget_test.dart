import 'package:flutter_test/flutter_test.dart';

import 'package:dbv/main.dart';

void main() {
  testWidgets('app boots to the welcome panel', (tester) async {
    await tester.pumpWidget(const DbvApp());
    await tester.pump();

    expect(find.text('New Connection'), findsWidgets);
  });
}
