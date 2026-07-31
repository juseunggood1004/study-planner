import 'package:ai_study_scheduler/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy book plans migrate with default kind and no date overrides', () {
    final plan = LocalPlan.fromJson({
      'installation_id': 'install-1',
      'book_title': '기존 책',
      'contents': [
        {
          'id': 'c1',
          'chapter': '1장',
          'section': null,
          'title': '시작',
          'estimated_minutes': 30,
        },
      ],
      'preferences': {
        'deadline': '2030-01-02',
        'daily_availability': [
          {'weekday': 0, 'available_minutes': 60},
        ],
        'preferred_start_time': '19:00:00',
        'focus_minutes': 40,
        'break_minutes': 10,
        'buffer_minutes': 20,
      },
      'schedule': {
        'days': [
          {
            'date': '2030-01-01',
            'blocks': [
              {
                'content_ids': ['c1'],
                'title': '시작',
                'start_time': '19:00',
                'duration_minutes': 30,
                'break_after_minutes': 0,
              },
            ],
            'review_minutes': 0,
            'buffer_minutes': 20,
            'note': '',
          },
        ],
        'summary': '시작합니다.',
        'warnings': [],
      },
      'completed_ids': <String>[],
    });

    expect(plan.title, '기존 책');
    expect(plan.kind, PlanKind.book);
    expect(plan.preferences.dateOverrides, isEmpty);
    expect(plan.learningFeedback, isEmpty);
    expect(plan.preferences.startDate, DateTime(2030, 1, 1));
  });

  test('date-specific rhythm is included in a goal request', () {
    final preferences = StudyPreferences(
      startDate: DateTime(2030, 1, 1),
      deadline: DateTime(2030, 1, 2),
      dailyAvailability: {0: 60},
      preferredStartTime: '19:00',
      focusMinutes: 40,
      breakMinutes: 10,
      bufferMinutes: 20,
      dateOverrides: {
        '2030-01-01': DateStudyOverride(
          date: DateTime(2030, 1, 1),
          availableMinutes: 90,
          preferredStartTime: '08:30',
          focusMinutes: 25,
          breakMinutes: 5,
        ),
      },
      blockedTimes: const [
        BlockedTime(
          label: '수학 학원',
          weekday: 0,
          startTime: '19:00',
          endTime: '21:00',
        ),
      ],
    );
    final request = preferences.toJson();

    expect(request['start_date'], '2030-01-01');
    expect((request['blocked_times'] as List).single['end_time'], '21:00:00');
    expect((request['date_overrides'] as List).single['available_minutes'], 90);
    expect((request['date_overrides'] as List).single['preferred_start_time'],
        '08:30:00');
  });
}
