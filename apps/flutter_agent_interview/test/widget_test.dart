import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_agent_interview/main.dart';

void main() {
  testWidgets('renders interview chatbot shell', (WidgetTester tester) async {
    await tester.pumpWidget(const AgentInterviewApp());
    await tester.pumpAndSettle();

    expect(find.text('Agent 面试机器人'), findsOneWidget);
    expect(find.text('本地 Demo · 本机记忆'), findsOneWidget);
  });
}
