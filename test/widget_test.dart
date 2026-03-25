import 'package:flutter_test/flutter_test.dart';
import 'package:viking_burger/main.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const VikingBurgerApp());
    await tester.pumpAndSettle();

    expect(find.text('Viking Burger'), findsOneWidget);
  });
}
