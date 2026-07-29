import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_study_scheduler/main.dart';

void main() {
  testWidgets('shows the study planner welcome flow', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const StudySchedulerApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('하루공부'), findsOneWidget);
    expect(find.text('공부할 책을 알려주세요'), findsOneWidget);
  });
}
