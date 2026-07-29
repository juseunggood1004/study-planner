import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_study_scheduler/main.dart';
import 'package:ai_study_scheduler/models.dart';

void main() {
  testWidgets('shows a plan-first home instead of forcing a book',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const StudySchedulerApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('하루공부'), findsOneWidget);
    expect(find.text('오늘도 내 속도로.'), findsOneWidget);
    expect(find.text('새 계획 추가'), findsOneWidget);
    expect(find.text('공부할 책을 알려주세요'), findsNothing);
  });

  testWidgets(
      'groups detailed contents in a toggle without overlapping actions',
      (WidgetTester tester) async {
    final items = [
      ContentItem(id: 'header', chapter: 'I', title: '지수함수와 로그함수'),
      ContentItem(id: 's1', chapter: 'I', section: '01', title: '지수'),
      ContentItem(id: 's2', chapter: 'I', section: '02', title: '로그'),
    ];
    await tester.pumpWidget(MaterialApp(
      home: ContentsScreen(
        title: '고등쎈수학',
        kind: PlanKind.book,
        items: items,
        onBack: () {},
        onContinue: (_) {},
      ),
    ));

    expect(find.text('I · 지수함수와 로그함수'), findsOneWidget);
    expect(find.text('2개 세부 항목'), findsOneWidget);
    expect(find.text('지수'), findsNothing);

    final toggle = tester.getRect(find.byIcon(Icons.expand_more));
    final title = tester.getRect(find.text('I · 지수함수와 로그함수'));
    expect(toggle.center.dx, lessThan(title.left));

    await tester.tap(find.text('I · 지수함수와 로그함수'));
    await tester.pumpAndSettle();
    expect(find.text('지수'), findsOneWidget);
    expect(find.text('로그'), findsOneWidget);

    final addButton =
        tester.getRect(find.byKey(const ValueKey('contents-add-button')));
    final nextButton =
        tester.getRect(find.widgetWithText(FilledButton, '기본 학습 리듬 정하기'));
    expect(addButton.overlaps(nextButton), isFalse);
  });
}
