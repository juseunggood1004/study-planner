import 'dart:convert';

enum PlanKind { book, goal }

extension PlanKindLabel on PlanKind {
  String get label => this == PlanKind.book ? '책' : '자유 목표';
  String get itemLabel => this == PlanKind.book ? '목차' : '학습 단계';
}

class ContentItem {
  ContentItem({
    required this.id,
    required this.chapter,
    required this.title,
    this.section,
    this.estimatedMinutes,
  });

  String id;
  String chapter;
  String? section;
  String title;
  int? estimatedMinutes;

  factory ContentItem.fromJson(Map<String, dynamic> json) => ContentItem(
        id: json['id'] as String,
        chapter: json['chapter'] as String,
        section: json['section'] as String?,
        title: json['title'] as String,
        estimatedMinutes: json['estimated_minutes'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'chapter': chapter,
        'section': section,
        'title': title,
        'estimated_minutes': estimatedMinutes,
      };
}

class DailyAvailability {
  const DailyAvailability(this.weekday, this.availableMinutes);
  final int weekday;
  final int availableMinutes;

  Map<String, dynamic> toJson() => {
        'weekday': weekday,
        'available_minutes': availableMinutes,
      };
}

class DateStudyOverride {
  const DateStudyOverride({
    required this.date,
    required this.availableMinutes,
    required this.preferredStartTime,
    required this.focusMinutes,
    required this.breakMinutes,
  });

  final DateTime date;
  final int availableMinutes;
  final String preferredStartTime;
  final int focusMinutes;
  final int breakMinutes;

  factory DateStudyOverride.fromJson(Map<String, dynamic> json) => DateStudyOverride(
        date: DateTime.parse(json['date'] as String),
        availableMinutes: json['available_minutes'] as int,
        preferredStartTime: (json['preferred_start_time'] as String).substring(0, 5),
        focusMinutes: json['focus_minutes'] as int,
        breakMinutes: json['break_minutes'] as int,
      );

  Map<String, dynamic> toJson() => {
        'date': _dateOnly(date),
        'available_minutes': availableMinutes,
        'preferred_start_time': '$preferredStartTime:00',
        'focus_minutes': focusMinutes,
        'break_minutes': breakMinutes,
      };
}

class StudyPreferences {
  StudyPreferences({
    required this.deadline,
    required this.dailyAvailability,
    required this.preferredStartTime,
    required this.focusMinutes,
    required this.breakMinutes,
    required this.bufferMinutes,
    Map<String, DateStudyOverride>? dateOverrides,
  }) : dateOverrides = dateOverrides ?? {};

  final DateTime deadline;
  final Map<int, int> dailyAvailability;
  final String preferredStartTime;
  final int focusMinutes;
  final int breakMinutes;
  final int bufferMinutes;
  final Map<String, DateStudyOverride> dateOverrides;

  DateStudyOverride? overrideFor(DateTime date) => dateOverrides[_dateOnly(date)];

  Map<String, dynamic> toJson() => {
        'deadline': _dateOnly(deadline),
        'daily_availability': dailyAvailability.entries
            .map((entry) => DailyAvailability(entry.key, entry.value).toJson())
            .toList(),
        'preferred_start_time': '$preferredStartTime:00',
        'focus_minutes': focusMinutes,
        'break_minutes': breakMinutes,
        'buffer_minutes': bufferMinutes,
        'date_overrides': dateOverrides.values.map((value) => value.toJson()).toList(),
      };

  factory StudyPreferences.fromJson(Map<String, dynamic> json) {
    final availability = <int, int>{
      for (final item in json['daily_availability'] as List)
        (item as Map<String, dynamic>)['weekday'] as int: item['available_minutes'] as int,
    };
    final overrides = (json['date_overrides'] as List? ?? const [])
        .map((item) => DateStudyOverride.fromJson(item as Map<String, dynamic>));
    return StudyPreferences(
      deadline: DateTime.parse(json['deadline'] as String),
      dailyAvailability: availability,
      preferredStartTime: (json['preferred_start_time'] as String).substring(0, 5),
      focusMinutes: json['focus_minutes'] as int,
      breakMinutes: json['break_minutes'] as int,
      bufferMinutes: json['buffer_minutes'] as int,
      dateOverrides: {
        for (final override in overrides) _dateOnly(override.date): override,
      },
    );
  }
}

class StudyBlock {
  StudyBlock({
    required this.contentIds,
    required this.title,
    required this.startTime,
    required this.durationMinutes,
    required this.breakAfterMinutes,
  });

  final List<String> contentIds;
  final String title;
  final String startTime;
  final int durationMinutes;
  final int breakAfterMinutes;

  factory StudyBlock.fromJson(Map<String, dynamic> json) => StudyBlock(
        contentIds: List<String>.from(json['content_ids'] as List),
        title: json['title'] as String,
        startTime: json['start_time'] as String,
        durationMinutes: json['duration_minutes'] as int,
        breakAfterMinutes: json['break_after_minutes'] as int,
      );

  Map<String, dynamic> toJson() => {
        'content_ids': contentIds,
        'title': title,
        'start_time': startTime,
        'duration_minutes': durationMinutes,
        'break_after_minutes': breakAfterMinutes,
      };
}

class ScheduleDay {
  ScheduleDay({
    required this.date,
    required this.blocks,
    required this.reviewMinutes,
    required this.bufferMinutes,
    required this.note,
  });

  final DateTime date;
  final List<StudyBlock> blocks;
  final int reviewMinutes;
  final int bufferMinutes;
  final String note;

  factory ScheduleDay.fromJson(Map<String, dynamic> json) => ScheduleDay(
        date: DateTime.parse(json['date'] as String),
        blocks: (json['blocks'] as List)
            .map((value) => StudyBlock.fromJson(value as Map<String, dynamic>))
            .toList(),
        reviewMinutes: json['review_minutes'] as int,
        bufferMinutes: json['buffer_minutes'] as int,
        note: json['note'] as String,
      );

  Map<String, dynamic> toJson() => {
        'date': _dateOnly(date),
        'blocks': blocks.map((block) => block.toJson()).toList(),
        'review_minutes': reviewMinutes,
        'buffer_minutes': bufferMinutes,
        'note': note,
      };
}

class Schedule {
  Schedule({required this.days, required this.summary, required this.warnings});
  final List<ScheduleDay> days;
  final String summary;
  final List<String> warnings;

  factory Schedule.fromJson(Map<String, dynamic> json) => Schedule(
        days: (json['days'] as List)
            .map((value) => ScheduleDay.fromJson(value as Map<String, dynamic>))
            .toList(),
        summary: json['summary'] as String,
        warnings: List<String>.from(json['warnings'] as List),
      );

  Map<String, dynamic> toJson() => {
        'days': days.map((day) => day.toJson()).toList(),
        'summary': summary,
        'warnings': warnings,
      };
}

class LocalPlan {
  LocalPlan({
    required this.planId,
    required this.installationId,
    required this.title,
    required this.kind,
    required this.contents,
    required this.preferences,
    required this.schedule,
    required this.completedIds,
  });

  final String planId;
  final String installationId;
  final String title;
  final PlanKind kind;
  final List<ContentItem> contents;
  final StudyPreferences preferences;
  Schedule schedule;
  final Set<String> completedIds;

  Map<String, dynamic> toRequestJson() => {
        // book_title is kept as a wire-compatible field while the product supports
        // both books and arbitrary goals.
        'book_title': title,
        'goal_type': kind.name,
        'contents': contents.map((item) => item.toJson()).toList(),
        'preferences': preferences.toJson(),
      };

  Map<String, dynamic> toJson() => {
        ...toRequestJson(),
        'plan_id': planId,
        'title': title,
        'installation_id': installationId,
        'schedule': schedule.toJson(),
        'completed_ids': completedIds.toList(),
      };

  factory LocalPlan.fromJson(Map<String, dynamic> json) => LocalPlan(
        planId: json['plan_id'] as String? ?? 'legacy-plan',
        installationId: json['installation_id'] as String,
        title: json['title'] as String? ?? json['book_title'] as String,
        kind: PlanKind.values.firstWhere(
          (value) => value.name == (json['goal_type'] as String? ?? 'book'),
          orElse: () => PlanKind.book,
        ),
        contents: (json['contents'] as List)
            .map((item) => ContentItem.fromJson(item as Map<String, dynamic>))
            .toList(),
        preferences: StudyPreferences.fromJson(json['preferences'] as Map<String, dynamic>),
        schedule: Schedule.fromJson(json['schedule'] as Map<String, dynamic>),
        completedIds: Set<String>.from(json['completed_ids'] as List),
      );
}

String _dateOnly(DateTime value) => value.toIso8601String().substring(0, 10);

String encodePlan(LocalPlan plan) => jsonEncode(plan.toJson());
LocalPlan decodePlan(String source) =>
    LocalPlan.fromJson(jsonDecode(source) as Map<String, dynamic>);

String encodePlans(List<LocalPlan> plans) =>
    jsonEncode(plans.map((plan) => plan.toJson()).toList());
List<LocalPlan> decodePlans(String source) => (jsonDecode(source) as List)
    .map((item) => LocalPlan.fromJson(item as Map<String, dynamic>))
    .toList();
