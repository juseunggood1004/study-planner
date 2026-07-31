import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'api_client.dart';
import 'local_store.dart';
import 'models.dart';

const _ink = Color(0xff18211d);
const _green = Color(0xff28634f);
const _greenDark = Color(0xff1f493c);
const _sage = Color(0xffdfe9df);
const _peach = Color(0xffffe2c6);
const _paper = Color(0xfff5f3ed);
const _muted = Color(0xff68746e);
const _line = Color(0xffe5e5df);
const _imageFileChannel =
    MethodChannel('com.example.ai_study_scheduler/image_file');

void main() => runApp(const StudySchedulerApp());

class StudySchedulerApp extends StatelessWidget {
  const StudySchedulerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '하루공부',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: _paper,
          colorScheme: ColorScheme.fromSeed(
            seedColor: _green,
            brightness: Brightness.light,
            surface: Colors.white,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: _paper,
            foregroundColor: _ink,
            elevation: 0,
            centerTitle: false,
            surfaceTintColor: Colors.transparent,
          ),
          textTheme: ThemeData.light().textTheme.apply(
                bodyColor: _ink,
                displayColor: _ink,
              ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              minimumSize: const Size(44, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _green, width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
        home: const StudyShell(),
      );
}

enum _Stage { home, setup, contents, preferences, plan }

class StudyShell extends StatefulWidget {
  const StudyShell({super.key});

  @override
  State<StudyShell> createState() => _StudyShellState();
}

class _StudyShellState extends State<StudyShell> {
  final _store = LocalStore();
  final _api = ApiClient();
  _Stage _stage = _Stage.home;
  bool _loading = true;
  bool _extracting = false;
  List<LocalPlan> _plans = [];
  LocalPlan? _selectedPlan;
  PlanKind _draftKind = PlanKind.book;
  String _draftTitle = '';
  List<ContentItem> _draftContents = [];

  @override
  void initState() {
    super.initState();
    _restorePlans();
  }

  Future<void> _restorePlans() async {
    final saved = await _store.loadPlans();
    if (!mounted) return;
    setState(() {
      _plans = saved;
      _loading = false;
    });
  }

  void _startAdding() {
    setState(() {
      _draftKind = PlanKind.book;
      _draftTitle = '';
      _draftContents = [];
      _stage = _Stage.setup;
    });
  }

  void _openPlan(LocalPlan plan) {
    setState(() {
      _selectedPlan = plan;
      _stage = _Stage.plan;
    });
  }

  Future<void> _extract(
    PlanKind kind,
    String title,
    ImageSource source,
  ) async {
    if (!_validTitle(title)) return;
    final image = await ImagePicker().pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 2400,
    );
    if (image == null) return;
    await _extractFromFiles(kind, title, [File(image.path)]);
  }

  Future<void> _extractMultiple(PlanKind kind, String title) async {
    if (!_validTitle(title)) return;
    final selected = await ImagePicker().pickMultiImage(
      imageQuality: 88,
      maxWidth: 2400,
    );
    if (selected.isEmpty) return;
    if (selected.length > 8) {
      _message('이미지는 한 번에 최대 8장까지 선택할 수 있어요.');
      return;
    }
    await _extractFromFiles(
      kind,
      title,
      selected.map((image) => File(image.path)).toList(),
    );
  }

  Future<void> _pickFromFiles(PlanKind kind, String title) async {
    if (!_validTitle(title)) return;
    try {
      final paths =
          await _imageFileChannel.invokeListMethod<String>('pickImages');
      if (paths == null || paths.isEmpty) return;
      await _extractFromFiles(
        kind,
        title,
        paths.map(File.new).toList(),
      );
    } on PlatformException catch (error) {
      _message(error.message ?? '파일을 열지 못했어요. 다시 시도해 주세요.');
    }
  }

  Future<void> _extractFromFiles(
    PlanKind kind,
    String title,
    List<File> images,
  ) async {
    setState(() => _extracting = true);
    try {
      final extracted = await _api.extractContents(images);
      if (!mounted) return;
      setState(() {
        _draftKind = kind;
        _draftTitle = title.trim();
        _draftContents = extracted;
        _stage = _Stage.contents;
      });
    } catch (error) {
      _message(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  void _startManual(PlanKind kind, String title) {
    final planTitle = title.trim().isEmpty && kind == PlanKind.goal
        ? '나의 과목 계획'
        : title.trim();
    if (!_validTitle(planTitle)) return;
    setState(() {
      _draftKind = kind;
      _draftTitle = planTitle;
      _draftContents = [];
      _stage = _Stage.contents;
    });
  }

  bool _validTitle(String title) {
    if (title.trim().isNotEmpty) return true;
    _message('계획 이름을 먼저 입력해 주세요.');
    return false;
  }

  Future<void> _createPlan(StudyPreferences preferences) async {
    if (_draftContents.isEmpty) {
      _message('${_draftKind.itemLabel}를 하나 이상 추가해 주세요.');
      return;
    }
    try {
      final draft = LocalPlanDraft(
        title: _draftTitle,
        kind: _draftKind,
        contents: _draftContents,
        preferences: preferences,
      );
      final schedule = await _api.generate(draft);
      final plan = LocalPlan(
        planId: 'plan-${DateTime.now().microsecondsSinceEpoch}',
        installationId: await _store.installationId(),
        title: _draftTitle,
        kind: _draftKind,
        contents: [..._draftContents],
        preferences: preferences,
        schedule: schedule,
        completedIds: {},
      );
      _plans = [..._plans, plan];
      await _store.savePlans(_plans);
      if (!mounted) return;
      setState(() {
        _selectedPlan = plan;
        _stage = _Stage.plan;
      });
    } catch (error) {
      _message(_friendlyError(error));
      rethrow;
    }
  }

  Future<void> _toggleCompleted(String id, bool selected) async {
    final plan = _selectedPlan;
    if (plan == null) return;
    setState(() {
      if (selected) {
        plan.completedIds.add(id);
      } else {
        plan.completedIds.remove(id);
      }
    });
    await _store.savePlans(_plans);
  }

  Future<void> _replan() async {
    final plan = _selectedPlan;
    if (plan == null) return;
    try {
      final schedule = await _api.replan(plan);
      if (!mounted) return;
      setState(() => plan.schedule = schedule);
      await _store.savePlans(_plans);
    } catch (error) {
      _message(_friendlyError(error));
      rethrow;
    }
  }

  Future<void> _confirmDailyProgress(
    ScheduleDay day,
    bool completed,
    LearningFeedback? feedback,
  ) async {
    final plan = _selectedPlan;
    if (plan == null) return;
    final key = _dateOnly(day.date);
    final previous = plan.dailyCheckIns[key];
    plan.dailyCheckIns[key] = completed;

    if (completed) {
      if (feedback != null) plan.learningFeedback[key] = feedback;
      for (final block in day.blocks) {
        plan.completedIds.addAll(block.contentIds);
      }
      await _store.savePlans(_plans);
      _message('오늘 학습을 완료로 기록했어요.');
      return;
    }

    try {
      final schedule = await _api.replan(plan);
      if (!mounted) return;
      setState(() => plan.schedule = schedule);
      await _store.savePlans(_plans);
      _message('미완료 분량을 남은 날짜에 맞춰 다시 배정했어요.');
    } catch (error) {
      if (previous == null) {
        plan.dailyCheckIns.remove(key);
      } else {
        plan.dailyCheckIns[key] = previous;
      }
      _message(_friendlyError(error));
      rethrow;
    }
  }

  Future<void> _updateDay(DateStudyOverride override) async {
    final plan = _selectedPlan;
    if (plan == null) return;
    final key = _dateOnly(override.date);
    final previous = plan.preferences.dateOverrides[key];
    plan.preferences.dateOverrides[key] = override;
    try {
      final schedule = await _api.replan(plan);
      if (!mounted) return;
      setState(() => plan.schedule = schedule);
      await _store.savePlans(_plans);
      _message(
          '${DateFormat('M월 d일', 'ko_KR').format(override.date)} 리듬을 반영했어요.');
    } catch (error) {
      if (previous == null) {
        plan.preferences.dateOverrides.remove(key);
      } else {
        plan.preferences.dateOverrides[key] = previous;
      }
      _message(_friendlyError(error));
      rethrow;
    }
  }

  Future<void> _deleteSelectedPlan() async {
    final plan = _selectedPlan;
    if (plan == null) return;
    _plans = _plans.where((item) => item.planId != plan.planId).toList();
    await _store.savePlans(_plans);
    if (!mounted) return;
    setState(() {
      _selectedPlan = null;
      _stage = _Stage.home;
    });
  }

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('ApiException: ', '');

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: _green)),
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      child: switch (_stage) {
        _Stage.home => HomeScreen(
            key: const ValueKey('home'),
            plans: _plans,
            onAdd: _startAdding,
            onOpen: _openPlan,
          ),
        _Stage.setup => PlanSetupScreen(
            key: const ValueKey('setup'),
            busy: _extracting,
            onBack: () => setState(() => _stage = _Stage.home),
            onCamera: (kind, title) =>
                _extract(kind, title, ImageSource.camera),
            onGallery: _extractMultiple,
            onFiles: _pickFromFiles,
            onManual: _startManual,
          ),
        _Stage.contents => ContentsScreen(
            key: const ValueKey('contents'),
            title: _draftTitle,
            kind: _draftKind,
            items: _draftContents,
            onBack: () => setState(() => _stage = _Stage.setup),
            onContinue: (items) => setState(() {
              _draftContents = items;
              _stage = _Stage.preferences;
            }),
          ),
        _Stage.preferences => PreferencesScreen(
            key: const ValueKey('preferences'),
            kind: _draftKind,
            onBack: () => setState(() => _stage = _Stage.contents),
            onGenerate: _createPlan,
          ),
        _Stage.plan => PlanScreen(
            key: ValueKey(_selectedPlan!.planId),
            plan: _selectedPlan!,
            onBack: () => setState(() => _stage = _Stage.home),
            onAddPlan: _startAdding,
            onDelete: _deleteSelectedPlan,
            onToggle: _toggleCompleted,
            onReplan: _replan,
            onConfirmDailyProgress: _confirmDailyProgress,
            onUpdateDay: _updateDay,
          ),
      },
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.plans,
    required this.onAdd,
    required this.onOpen,
  });

  final List<LocalPlan> plans;
  final VoidCallback onAdd;
  final ValueChanged<LocalPlan> onOpen;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayPlans = <(LocalPlan, ScheduleDay)>[];
    for (final plan in plans) {
      for (final day in plan.schedule.days) {
        if (_sameDay(day.date, today) && day.blocks.isNotEmpty) {
          todayPlans.add((plan, day));
        }
      }
    }
    final totalMinutes = todayPlans.fold<int>(
      0,
      (sum, entry) =>
          sum +
          entry.$2.blocks.fold<int>(
            0,
            (blockSum, block) => blockSum + block.durationMinutes,
          ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const _BrandMark(),
        actions: [
          IconButton(
            tooltip: '계획 추가',
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
          children: [
            Text(
              DateFormat('M월 d일 EEEE', 'ko_KR').format(today),
              style: const TextStyle(
                color: _muted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '오늘도 내 속도로.',
              style: TextStyle(
                fontSize: 30,
                height: 1.15,
                letterSpacing: -0.8,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 22),
            _TodayCard(
              entries: todayPlans,
              totalMinutes: totalMinutes,
              onOpen: onOpen,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('새 계획 추가'),
            ),
            const SizedBox(height: 30),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '내 계획',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  '${plans.length}개',
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (plans.isEmpty)
              _EmptyPlans(onAdd: onAdd)
            else
              ...plans.map(
                (plan) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _PlanCard(plan: plan, onTap: () => onOpen(plan)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class PlanSetupScreen extends StatefulWidget {
  const PlanSetupScreen({
    super.key,
    required this.busy,
    required this.onBack,
    required this.onCamera,
    required this.onGallery,
    required this.onFiles,
    required this.onManual,
  });

  final bool busy;
  final VoidCallback onBack;
  final void Function(PlanKind, String) onCamera;
  final void Function(PlanKind, String) onGallery;
  final void Function(PlanKind, String) onFiles;
  final void Function(PlanKind, String) onManual;

  @override
  State<PlanSetupScreen> createState() => _PlanSetupScreenState();
}

class _PlanSetupScreenState extends State<PlanSetupScreen> {
  final _title = TextEditingController();
  PlanKind _kind = PlanKind.book;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: '홈으로',
            icon: const Icon(Icons.close_rounded),
            onPressed: widget.onBack,
          ),
          title: const _TopProgress(step: 1),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
            children: [
              const Text(
                '무엇을 이루고\n싶나요?',
                style: TextStyle(
                  fontSize: 30,
                  height: 1.17,
                  letterSpacing: -0.8,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '책 한 권부터 자격증·포트폴리오 같은 목표까지\n하나의 계획으로 나눌 수 있어요.',
                style: TextStyle(color: _muted, height: 1.5),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _KindCard(
                      icon: Icons.menu_book_rounded,
                      title: '책으로 시작',
                      subtitle: '목차 사진 사용',
                      selected: _kind == PlanKind.book,
                      onTap: () => setState(() => _kind = PlanKind.book),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _KindCard(
                      icon: Icons.flag_rounded,
                      title: '과목 · 단원',
                      subtitle: '하루 계획표 만들기',
                      selected: _kind == PlanKind.goal,
                      onTap: () => setState(() => _kind = PlanKind.goal),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              TextField(
                controller: _title,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: _kind == PlanKind.book ? '책 제목' : '계획 이름 · 선택',
                  hintText: _kind == PlanKind.book
                      ? '예: 해커스 토익 리딩'
                      : '비워두면 나의 과목 계획으로 만들어요',
                ),
              ),
              const SizedBox(height: 26),
              Text(
                _kind == PlanKind.book
                    ? '목차를 어떻게 가져올까요?'
                    : '공부할 과목과 단원을 입력해 주세요',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              if (_kind == PlanKind.book) ...[
                _ActionCard(
                  icon: Icons.document_scanner_rounded,
                  color: _green,
                  title: '카메라로 목차 촬영',
                  subtitle: 'AI가 장·절을 읽고 순서대로 정리해요',
                  onTap: widget.busy
                      ? null
                      : () => widget.onCamera(_kind, _title.text),
                ),
                const SizedBox(height: 10),
                _ActionCard(
                  icon: Icons.photo_library_rounded,
                  color: const Color(0xffb56735),
                  title: '사진 여러 장 선택',
                  subtitle: '연속된 목차 사진을 한 번에 최대 8장까지 골라요',
                  onTap: widget.busy
                      ? null
                      : () => widget.onGallery(_kind, _title.text),
                ),
                if (Platform.isAndroid) ...[
                  const SizedBox(height: 10),
                  _ActionCard(
                    icon: Icons.folder_open_rounded,
                    color: const Color(0xff536c9e),
                    title: '파일에서 여러 장 선택',
                    subtitle: 'JPG, PNG, WEBP 파일을 함께 사용할 수 있어요',
                    onTap: widget.busy
                        ? null
                        : () => widget.onFiles(_kind, _title.text),
                  ),
                ],
                const SizedBox(height: 10),
              ],
              _ActionCard(
                icon: _kind == PlanKind.book
                    ? Icons.edit_note_rounded
                    : Icons.today_rounded,
                color: const Color(0xff74558f),
                title: _kind == PlanKind.book ? '목차 직접 입력' : '과목 · 단원 입력',
                subtitle: _kind == PlanKind.book
                    ? '사진 없이 장·절을 추가해요'
                    : '입력한 과목과 단원으로 오늘 계획을 만들어요',
                onTap: widget.busy
                    ? null
                    : () => widget.onManual(_kind, _title.text),
              ),
              if (widget.busy)
                const Padding(
                  padding: EdgeInsets.only(top: 26),
                  child: _LoadingMessage(label: '목차 사진을 순서대로 읽고 있어요…'),
                ),
            ],
          ),
        ),
      );
}

class ContentsScreen extends StatefulWidget {
  const ContentsScreen({
    super.key,
    required this.title,
    required this.kind,
    required this.items,
    required this.onBack,
    required this.onContinue,
  });

  final String title;
  final PlanKind kind;
  final List<ContentItem> items;
  final VoidCallback onBack;
  final ValueChanged<List<ContentItem>> onContinue;

  @override
  State<ContentsScreen> createState() => _ContentsScreenState();
}

class _ContentsScreenState extends State<ContentsScreen> {
  late final List<ContentItem> _items = [...widget.items];

  List<_ContentGroup> get _groups {
    final grouped = <String, List<ContentItem>>{};
    for (final item in _items) {
      grouped.putIfAbsent(item.chapter.trim(), () => []).add(item);
    }
    return grouped.entries
        .map((entry) => _ContentGroup(entry.key, entry.value))
        .toList();
  }

  Future<void> _edit([ContentItem? item]) async {
    final result = await showModalBottomSheet<ContentItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ContentItemSheet(
        item: item,
        kind: widget.kind,
        nextId: 'c${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      if (item == null) {
        _items.add(result);
      } else {
        _items[_items.indexOf(item)] = result;
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: widget.onBack,
          ),
          title: const _TopProgress(step: 2),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _KindPill(kind: widget.kind),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _green,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${widget.kind.itemLabel}를 확인해 주세요',
                            style: const TextStyle(
                              fontSize: 27,
                              letterSpacing: -0.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          key: const ValueKey('contents-add-button'),
                          onPressed: _edit,
                          icon: const Icon(Icons.add_rounded, size: 19),
                          label: Text(
                            '${widget.kind.itemLabel} 추가',
                            softWrap: false,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _greenDark,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            side: const BorderSide(color: Color(0xffcbd3ce)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _items.isEmpty
                          ? '사진에서 읽은 목차가 여기에 정리돼요.'
                          : '${_groups.length}개 단원 · ${_items.length}개 항목  '
                              '단원을 펼쳐 세부 내용을 확인하세요.',
                      style: const TextStyle(color: _muted),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _items.isEmpty
                    ? _EmptyContents(kind: widget.kind)
                    : ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: _groups.length,
                        onReorder: (oldIndex, newIndex) => setState(() {
                          if (newIndex > oldIndex) newIndex -= 1;
                          final groups = _groups;
                          final moved = groups.removeAt(oldIndex);
                          groups.insert(newIndex, moved);
                          _items
                            ..clear()
                            ..addAll(groups.expand((group) => group.items));
                        }),
                        itemBuilder: (context, index) {
                          final group = _groups[index];
                          return _ContentGroupCard(
                            key: ValueKey('group-${group.chapter}'),
                            group: group,
                            index: index,
                            onEdit: _edit,
                            onDeleteItem: (item) =>
                                setState(() => _items.remove(item)),
                            onDeleteGroup: () => setState(
                              () => _items.removeWhere(group.items.contains),
                            ),
                          );
                        },
                      ),
              ),
              _BottomButton(
                label: '기본 학습 리듬 정하기',
                enabled: _items.isNotEmpty,
                onPressed: () => widget.onContinue(_items),
              ),
            ],
          ),
        ),
      );
}

class _ContentGroup {
  const _ContentGroup(this.chapter, this.items);

  final String chapter;
  final List<ContentItem> items;

  ContentItem? get header {
    for (final item in items) {
      if (item.section == null) return item;
    }
    return null;
  }

  List<ContentItem> get details =>
      header == null ? items : items.where((item) => item != header).toList();

  String get title {
    final headerTitle = header?.title.trim();
    if (headerTitle == null ||
        headerTitle.isEmpty ||
        chapter.contains(headerTitle)) {
      return chapter;
    }
    return '$chapter · $headerTitle';
  }
}

class _ContentGroupCard extends StatelessWidget {
  const _ContentGroupCard({
    super.key,
    required this.group,
    required this.index,
    required this.onEdit,
    required this.onDeleteItem,
    required this.onDeleteGroup,
  });

  final _ContentGroup group;
  final int index;
  final ValueChanged<ContentItem> onEdit;
  final ValueChanged<ContentItem> onDeleteItem;
  final VoidCallback onDeleteGroup;

  @override
  Widget build(BuildContext context) {
    final details = group.details;
    if (details.isEmpty) {
      final item = group.header ?? group.items.first;
      return Container(
        key: key,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: _cardDecoration(radius: 18),
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
          leading: ReorderableDragStartListener(
            index: index,
            child: const _DragHandle(),
          ),
          title: Text(
            group.title,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: item.estimatedMinutes == null
              ? const Text('세부 항목 없음')
              : Text('약 ${item.estimatedMinutes}분'),
          trailing: IconButton(
            tooltip: '단원 삭제',
            onPressed: onDeleteGroup,
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
          onTap: () => onEdit(item),
        ),
      );
    }

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: _cardDecoration(radius: 18),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(12, 5, 10, 5),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: _green,
        collapsedIconColor: _muted,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          group.title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const _DragHandle(),
            ),
            IconButton(
              tooltip: '단원 삭제',
              visualDensity: VisualDensity.compact,
              onPressed: onDeleteGroup,
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
          ],
        ),
        subtitle: Text('${details.length}개 세부 항목'),
        children: [
          const Divider(height: 1, color: _line),
          const SizedBox(height: 6),
          ...details.map(
            (item) => ListTile(
              contentPadding: const EdgeInsets.only(left: 4),
              minLeadingWidth: 34,
              leading: Container(
                constraints: const BoxConstraints(minWidth: 34),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                decoration: BoxDecoration(
                  color: _sage,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  item.section ?? '·',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _greenDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              title: Text(
                item.title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: item.estimatedMinutes == null
                  ? null
                  : Text('약 ${item.estimatedMinutes}분'),
              trailing: IconButton(
                tooltip: '항목 삭제',
                onPressed: () => onDeleteItem(item),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
              onTap: () => onEdit(item),
            ),
          ),
        ],
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 40,
        height: 44,
        child: Icon(
          Icons.drag_indicator_rounded,
          color: Color(0xff9aa49f),
        ),
      );
}

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({
    super.key,
    required this.kind,
    required this.onBack,
    required this.onGenerate,
  });

  final PlanKind kind;
  final VoidCallback onBack;
  final Future<void> Function(StudyPreferences) onGenerate;

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class BlockedTimeSheet extends StatefulWidget {
  const BlockedTimeSheet({super.key});

  @override
  State<BlockedTimeSheet> createState() => _BlockedTimeSheetState();
}

class _BlockedTimeSheetState extends State<BlockedTimeSheet> {
  final _label = TextEditingController(text: '학교');
  int _weekday = DateTime.now().weekday - 1;
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 16, minute: 0);
  static const _days = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  int _minutes(TimeOfDay value) => value.hour * 60 + value.minute;

  void _save() {
    if (_label.text.trim().isEmpty || _minutes(_end) <= _minutes(_start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이름과 올바른 시작·종료 시간을 입력해 주세요.')),
      );
      return;
    }
    Navigator.pop(
      context,
      BlockedTime(
        label: _label.text.trim(),
        weekday: _weekday,
        startTime: _timeValue(_start),
        endTime: _timeValue(_end),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Container(
          padding: EdgeInsets.fromLTRB(
            20,
            18,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Wrap(
            runSpacing: 16,
            children: [
              const Text('학교 · 학원 일정 추가',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
              TextField(
                controller: _label,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '일정 이름',
                  hintText: '예: 학교, 수학 학원',
                ),
              ),
              DropdownButtonFormField<int>(
                value: _weekday,
                decoration: const InputDecoration(labelText: '요일'),
                items: List.generate(
                  7,
                  (index) => DropdownMenuItem(
                    value: index,
                    child: Text('${_days[index]}요일'),
                  ),
                ),
                onChanged: (value) => setState(() => _weekday = value!),
              ),
              Row(
                children: [
                  Expanded(
                    child: _TimeInput(
                      label: '시작',
                      value: _start,
                      onTap: () async {
                        final next = await showTimePicker(
                          context: context,
                          initialTime: _start,
                        );
                        if (next != null) setState(() => _start = next);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TimeInput(
                      label: '종료',
                      value: _end,
                      onTap: () async {
                        final next = await showTimePicker(
                          context: context,
                          initialTime: _end,
                        );
                        if (next != null) setState(() => _end = next);
                      },
                    ),
                  ),
                ],
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('일정 추가'),
                ),
              ),
            ],
          ),
        ),
      );
}

class _TimeInput extends StatelessWidget {
  const _TimeInput({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final TimeOfDay value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(labelText: label),
          child: Text(value.format(context)),
        ),
      );
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  DateTime _startDate = DateUtils.dateOnly(DateTime.now());
  DateTime _deadline = DateTime.now().add(const Duration(days: 30));
  TimeOfDay _start = const TimeOfDay(hour: 19, minute: 0);
  final Map<int, int> _minutes = {
    0: 60,
    1: 60,
    2: 60,
    3: 60,
    4: 60,
    5: 90,
    6: 90,
  };
  int _selectedDay = DateTime.now().weekday - 1;
  int _focus = 40;
  int _break = 10;
  int _buffer = 20;
  final List<BlockedTime> _blockedTimes = [];
  bool _busy = false;
  static const _days = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  void initState() {
    super.initState();
    if (widget.kind == PlanKind.goal) _deadline = _startDate;
  }

  Future<void> _addBlockedTime() async {
    final blocked = await showModalBottomSheet<BlockedTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const BlockedTimeSheet(),
    );
    if (blocked != null && mounted) {
      setState(() => _blockedTimes.add(blocked));
    }
  }

  Future<void> _submit() async {
    final availability = <int, int>{
      for (final entry in _minutes.entries.where((entry) => entry.value > 0))
        entry.key: entry.value,
    };
    if (availability.isEmpty) return;
    final preferences = StudyPreferences(
      startDate: _startDate,
      deadline: _deadline,
      dailyAvailability: availability,
      preferredStartTime: _timeValue(_start),
      focusMinutes: _focus,
      breakMinutes: _break,
      bufferMinutes: _buffer,
      blockedTimes: _blockedTimes,
    );
    setState(() => _busy = true);
    try {
      await widget.onGenerate(preferences);
    } catch (_) {
      // The parent presents a localized error.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: widget.onBack,
          ),
          title: const _TopProgress(step: 3),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 112),
            children: [
              const Text(
                '평소의 리듬을\n알려주세요.',
                style: TextStyle(
                  fontSize: 30,
                  height: 1.17,
                  letterSpacing: -0.8,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '이 설정은 기본값이에요. 계획을 만든 뒤 날짜마다\n학습 시간과 휴식 간격을 따로 바꿀 수 있어요.',
                style: TextStyle(color: _muted, height: 1.5),
              ),
              const SizedBox(height: 24),
              _PreferenceCard(
                children: [
                  _SettingsRow(
                    icon: Icons.play_circle_outline_rounded,
                    title: '학습 시작일',
                    value: DateFormat('M월 d일 (E)', 'ko_KR').format(_startDate),
                    onTap: () async {
                      final next = await showDatePicker(
                        context: context,
                        initialDate: _startDate,
                        firstDate: DateUtils.dateOnly(DateTime.now()),
                        lastDate: widget.kind == PlanKind.goal
                            ? DateTime.now().add(const Duration(days: 730))
                            : _deadline,
                        locale: const Locale('ko'),
                      );
                      if (next != null) {
                        setState(() {
                          _startDate = next;
                          if (widget.kind == PlanKind.goal) _deadline = next;
                        });
                      }
                    },
                  ),
                  if (widget.kind != PlanKind.goal) ...[
                    const Divider(height: 28, color: _line),
                    _SettingsRow(
                      icon: Icons.event_rounded,
                      title: '마감일',
                      value: DateFormat('M월 d일 (E)', 'ko_KR').format(_deadline),
                      onTap: () async {
                        final next = await showDatePicker(
                          context: context,
                          initialDate: _deadline,
                          firstDate: _startDate,
                          lastDate:
                              DateTime.now().add(const Duration(days: 730)),
                          locale: const Locale('ko'),
                        );
                        if (next != null) setState(() => _deadline = next);
                      },
                    ),
                  ],
                  const Divider(height: 28, color: _line),
                  _SettingsRow(
                    icon: Icons.schedule_rounded,
                    title: '기본 시작 시간',
                    value: _start.format(context),
                    onTap: () async {
                      final next = await showTimePicker(
                        context: context,
                        initialTime: _start,
                      );
                      if (next != null) setState(() => _start = next);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const _FieldTitle(
                title: '학교 · 학원 일정',
                subtitle: '이 시간에는 학습 블록을 만들지 않아요.',
              ),
              const SizedBox(height: 10),
              _PreferenceCard(
                children: [
                  if (_blockedTimes.isEmpty)
                    const Text(
                      '등록한 고정 일정이 없어요. 학교나 학원 시간을 추가해 보세요.',
                      style: TextStyle(color: _muted, height: 1.45),
                    )
                  else
                    ..._blockedTimes.asMap().entries.map(
                          (entry) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: const Icon(Icons.event_busy_rounded,
                                  color: _green),
                              title: Text(entry.value.label,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800)),
                              subtitle: Text(
                                '${_days[entry.value.weekday]}요일 · ${entry.value.startTime}–${entry.value.endTime}',
                              ),
                              trailing: IconButton(
                                tooltip: '일정 삭제',
                                onPressed: () => setState(
                                  () => _blockedTimes.removeAt(entry.key),
                                ),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ),
                          ),
                        ),
                  OutlinedButton.icon(
                    onPressed: _addBlockedTime,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('학교 · 학원 일정 추가'),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const _FieldTitle(
                title: '요일별 학습 가능 시간',
                subtitle: '요일을 누른 뒤 시간을 조절하세요',
              ),
              const SizedBox(height: 10),
              _PreferenceCard(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(
                      7,
                      (index) => _DayChip(
                        label: _days[index],
                        active: _selectedDay == index,
                        minutes: _minutes[index]!,
                        onTap: () => setState(() => _selectedDay = index),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Text(
                        '${_days[_selectedDay]}요일',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      Text(
                        _minutes[_selectedDay] == 0
                            ? '쉬는 날'
                            : '${_minutes[_selectedDay]}분',
                        style: const TextStyle(
                          color: _green,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _minutes[_selectedDay]!.toDouble(),
                    min: 0,
                    max: 360,
                    divisions: 24,
                    label: '${_minutes[_selectedDay]}분',
                    activeColor: _green,
                    onChanged: (value) => setState(
                      () => _minutes[_selectedDay] = value.round(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const _FieldTitle(
                title: '기본 집중 방식',
                subtitle: 'AI가 학습 블록을 나눌 때 사용해요',
              ),
              const SizedBox(height: 10),
              _PreferenceCard(
                children: [
                  _MinutePicker(
                    label: '한 번에 집중',
                    value: _focus,
                    options: const [25, 40, 50, 60],
                    onChanged: (value) => setState(() => _focus = value),
                  ),
                  const SizedBox(height: 18),
                  _MinutePicker(
                    label: '블록 사이 휴식',
                    value: _break,
                    options: const [5, 10, 15, 20],
                    onChanged: (value) => setState(() => _break = value),
                  ),
                  const SizedBox(height: 18),
                  _MinutePicker(
                    label: '하루 여유 시간',
                    value: _buffer,
                    options: const [0, 10, 20, 30],
                    onChanged: (value) => setState(() => _buffer = value),
                  ),
                ],
              ),
            ],
          ),
        ),
        bottomNavigationBar: _BottomButton(
          label: _busy ? 'AI가 계획을 나누고 있어요…' : '맞춤 일정 만들기',
          enabled: !_busy,
          onPressed: _submit,
        ),
      );
}

class PlanScreen extends StatefulWidget {
  const PlanScreen({
    super.key,
    required this.plan,
    required this.onBack,
    required this.onAddPlan,
    required this.onDelete,
    required this.onToggle,
    required this.onReplan,
    required this.onConfirmDailyProgress,
    required this.onUpdateDay,
  });

  final LocalPlan plan;
  final VoidCallback onBack;
  final VoidCallback onAddPlan;
  final Future<void> Function() onDelete;
  final Future<void> Function(String, bool) onToggle;
  final Future<void> Function() onReplan;
  final Future<void> Function(ScheduleDay, bool, LearningFeedback?)
      onConfirmDailyProgress;
  final Future<void> Function(DateStudyOverride) onUpdateDay;

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  bool _replanning = false;
  String? _adjustingDate;
  String? _checkingDate;
  bool _automaticCheckInShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _askForMissedDay());
  }

  ScheduleDay? _unconfirmedPastDay() {
    final today = DateUtils.dateOnly(DateTime.now());
    return widget.plan.schedule.days
        .where(
          (day) =>
              day.blocks.isNotEmpty &&
              day.date.isBefore(today) &&
              !widget.plan.dailyCheckIns.containsKey(_dateOnly(day.date)),
        )
        .firstOrNull;
  }

  Future<void> _askForMissedDay() async {
    if (!mounted || _automaticCheckInShown) return;
    final day = _unconfirmedPastDay();
    if (day == null) return;
    _automaticCheckInShown = true;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('어제 학습을 마쳤나요?'),
        content: Text(
          '${DateFormat('M월 d일', 'ko_KR').format(day.date)}에 계획한 학습을 모두 완료했는지 알려주세요. 미완료라면 남은 날짜에 맞춰 일정을 다시 배정합니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('미완료, 일정 조정'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('완료했어요'),
          ),
        ],
      ),
    );
    if (result != null && mounted) await _confirmDay(day, result);
  }

  Future<void> _confirmDay(ScheduleDay day, bool completed) async {
    final feedback = completed ? await _collectFeedback(day) : null;
    if (completed && feedback == null) return;
    setState(() => _checkingDate = _dateOnly(day.date));
    try {
      await widget.onConfirmDailyProgress(day, completed, feedback);
    } catch (_) {
      // The parent presents a localized error.
    } finally {
      if (mounted) setState(() => _checkingDate = null);
    }
  }

  Future<LearningFeedback?> _collectFeedback(ScheduleDay day) async {
    var fatigue = 3;
    var difficulty = 3;
    return showDialog<LearningFeedback>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('오늘 학습은 어땠나요?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('다음 계획의 학습량과 휴식에 반영할게요.'),
              const SizedBox(height: 16),
              _FeedbackRating(
                label: '피로도',
                value: fatigue,
                lowLabel: '여유로움',
                highLabel: '매우 피곤',
                onChanged: (value) => setDialogState(() => fatigue = value),
              ),
              const SizedBox(height: 12),
              _FeedbackRating(
                label: '체감 난이도',
                value: difficulty,
                lowLabel: '쉬웠음',
                highLabel: '매우 어려움',
                onChanged: (value) => setDialogState(() => difficulty = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('나중에'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                LearningFeedback(
                  date: day.date,
                  fatigue: fatigue,
                  difficulty: difficulty,
                ),
              ),
              child: const Text('다음 계획에 반영'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _completeTimerBlock(StudyBlock block) async {
    for (final id in block.contentIds) {
      await widget.onToggle(id, true);
    }
  }

  Future<void> _runReplan() async {
    setState(() => _replanning = true);
    try {
      await widget.onReplan();
    } catch (_) {
      // The parent presents a localized error.
    } finally {
      if (mounted) setState(() => _replanning = false);
    }
  }

  Future<void> _editDay(ScheduleDay day) async {
    final result = await showModalBottomSheet<DateStudyOverride>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DailyRhythmSheet(
        day: day,
        preferences: widget.plan.preferences,
      ),
    );
    if (result == null || !mounted) return;
    final key = _dateOnly(day.date);
    setState(() => _adjustingDate = key);
    try {
      await widget.onUpdateDay(result);
    } catch (_) {
      // The parent presents a localized error.
    } finally {
      if (mounted) setState(() => _adjustingDate = null);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('계획을 삭제할까요?'),
        content: Text(
          '“${widget.plan.title}”의 일정과 완료 기록이 이 기기에서 삭제됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.plan.contents.length;
    final done = widget.plan.completedIds.length.clamp(0, total);
    final percent = total == 0 ? 0.0 : done / total;
    final nextDay = widget.plan.schedule.days
        .where((day) =>
            !day.date.isBefore(DateTime(
              DateTime.now().year,
              DateTime.now().month,
              DateTime.now().day,
            )) &&
            day.blocks.isNotEmpty)
        .firstOrNull;
    final today = DateUtils.dateOnly(DateTime.now());
    final todayDay = widget.plan.schedule.days
        .where((day) => _sameDay(day.date, today) && day.blocks.isNotEmpty)
        .firstOrNull;
    final todayCheckIn = todayDay == null
        ? null
        : widget.plan.dailyCheckIns[_dateOnly(todayDay.date)];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '홈',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: widget.onBack,
        ),
        title: const _BrandMark(compact: true),
        actions: [
          IconButton(
            tooltip: '새 계획 추가',
            icon: const Icon(Icons.add_rounded),
            onPressed: widget.onAddPlan,
          ),
          PopupMenuButton<String>(
            tooltip: '더 보기',
            onSelected: (value) {
              if (value == 'delete') _confirmDelete();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline_rounded, color: Colors.red),
                    SizedBox(width: 10),
                    Text('계획 삭제'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
          children: [
            Row(
              children: [
                _KindPill(kind: widget.plan.kind),
                const SizedBox(width: 8),
                Text(
                  'D-${_daysUntil(widget.plan.preferences.deadline)}',
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              widget.plan.title,
              style: const TextStyle(
                fontSize: 29,
                height: 1.18,
                letterSpacing: -0.7,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: _greenDark,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '전체 진행률',
                        style: TextStyle(
                          color: Color(0xffc9d9d1),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${(percent * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$done / $total ${widget.plan.kind.itemLabel} 완료',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      letterSpacing: -0.4,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: percent,
                      minHeight: 8,
                      backgroundColor: const Color(0xff3c6254),
                      color: const Color(0xffb9dfc9),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    nextDay == null
                        ? widget.plan.schedule.summary
                        : '다음 학습은 ${DateFormat('M월 d일 (E)', 'ko_KR').format(nextDay.date)} · '
                            '${nextDay.blocks.fold<int>(0, (sum, block) => sum + block.durationMinutes)}분이에요.',
                    style: const TextStyle(
                      color: Color(0xffe1ebe6),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.plan.schedule.warnings.isNotEmpty) ...[
              const SizedBox(height: 14),
              ...widget.plan.schedule.warnings
                  .map((warning) => _Notice(text: warning)),
            ],
            if (todayDay != null) ...[
              const SizedBox(height: 18),
              _DailyCheckInCard(
                day: todayDay,
                status: todayCheckIn,
                loading: _checkingDate == _dateOnly(todayDay.date),
                onDone: () => _confirmDay(todayDay, true),
                onMissed: () => _confirmDay(todayDay, false),
              ),
              const SizedBox(height: 14),
              _StudyTimerCard(
                blocks: todayDay.blocks,
                onCompleteBlock: _completeTimerBlock,
              ),
            ],
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _replanning ? null : _runReplan,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: Text(
                _replanning ? '진행 상황을 반영하고 있어요…' : '완료 기록으로 일정 다시 맞추기',
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                side: const BorderSide(color: Color(0xffcbd3ce)),
                foregroundColor: _greenDark,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
            const SizedBox(height: 28),
            const _FieldTitle(
              title: '학습 일정',
              subtitle: '날짜의 설정 버튼으로 그날 리듬만 바꿀 수 있어요',
            ),
            const SizedBox(height: 12),
            ...widget.plan.schedule.days.map(
              (day) => _ScheduleDayCard(
                day: day,
                completed: widget.plan.completedIds,
                dailyCheckIn: widget.plan.dailyCheckIns[_dateOnly(day.date)],
                adjusting: _adjustingDate == _dateOnly(day.date),
                onEdit: () => _editDay(day),
                onToggle: widget.onToggle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedbackRating extends StatelessWidget {
  const _FeedbackRating({
    required this.label,
    required this.value,
    required this.lowLabel,
    required this.highLabel,
    required this.onChanged,
  });

  final String label;
  final int value;
  final String lowLabel;
  final String highLabel;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('$value / 5', style: const TextStyle(color: _green)),
            ],
          ),
          Slider(
            value: value.toDouble(),
            min: 1,
            max: 5,
            divisions: 4,
            label: '$value',
            activeColor: _green,
            onChanged: (next) => onChanged(next.round()),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(lowLabel,
                  style: const TextStyle(color: _muted, fontSize: 12)),
              Text(highLabel,
                  style: const TextStyle(color: _muted, fontSize: 12)),
            ],
          ),
        ],
      );
}

class _DailyCheckInCard extends StatelessWidget {
  const _DailyCheckInCard({
    required this.day,
    required this.status,
    required this.loading,
    required this.onDone,
    required this.onMissed,
  });

  final ScheduleDay day;
  final bool? status;
  final bool loading;
  final VoidCallback onDone;
  final VoidCallback onMissed;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: status == true ? const Color(0xffe7f3e8) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: status == true ? const Color(0xffb9d8bf) : _line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _sage,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child:
                      const Icon(Icons.fact_check_rounded, color: _greenDark),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    '${DateFormat('M월 d일', 'ko_KR').format(day.date)} 학습 확인',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
                if (loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _green),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (status == true)
              const Text('완료로 기록됐어요. 다음 학습도 이어가 볼까요?',
                  style: TextStyle(color: _muted))
            else if (status == false)
              const Text('미완료 분량을 남은 학습일에 맞춰 다시 배정했어요.',
                  style: TextStyle(color: _muted))
            else ...[
              const Text('오늘 계획한 학습을 모두 마쳤나요?',
                  style: TextStyle(color: _muted)),
              const SizedBox(height: 13),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: loading ? null : onMissed,
                      child: const Text('미완료, 일정 조정'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: loading ? null : onDone,
                      child: const Text('완료했어요'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
}

class _StudyTimerCard extends StatefulWidget {
  const _StudyTimerCard({
    required this.blocks,
    required this.onCompleteBlock,
  });

  final List<StudyBlock> blocks;
  final Future<void> Function(StudyBlock block) onCompleteBlock;

  @override
  State<_StudyTimerCard> createState() => _StudyTimerCardState();
}

class _StudyTimerCardState extends State<_StudyTimerCard> {
  Timer? _ticker;
  int _blockIndex = 0;
  int _remainingSeconds = 0;
  int _totalSeconds = 1;
  bool _running = false;
  bool _isBreak = false;
  bool _workFinished = false;
  bool _savingCompletion = false;

  StudyBlock get _block =>
      widget.blocks[_blockIndex.clamp(0, widget.blocks.length - 1)];

  @override
  void initState() {
    super.initState();
    _resetTimer();
  }

  @override
  void didUpdateWidget(covariant _StudyTimerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_blockIndex >= widget.blocks.length) {
      _blockIndex = 0;
      _resetTimer();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _resetTimer() {
    _ticker?.cancel();
    final seconds = _block.durationMinutes * 60;
    _remainingSeconds = seconds;
    _totalSeconds = seconds;
    _running = false;
    _isBreak = false;
    _workFinished = false;
  }

  void _toggleTimer() {
    if (_running) {
      _ticker?.cancel();
      setState(() => _running = false);
      return;
    }
    setState(() => _running = true);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remainingSeconds <= 1) {
        _ticker?.cancel();
        final wasBreak = _isBreak;
        setState(() {
          _remainingSeconds = 0;
          _running = false;
          if (_isBreak) {
            _isBreak = false;
            _remainingSeconds = _block.durationMinutes * 60;
            _totalSeconds = _remainingSeconds;
          } else {
            _workFinished = true;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(wasBreak
                ? '휴식이 끝났어요. 다음 집중을 시작해요.'
                : '집중 시간이 끝났어요. 완료 여부를 기록해 주세요.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        setState(() => _remainingSeconds--);
      }
    });
  }

  void _startBreak() {
    if (_block.breakAfterMinutes == 0) return;
    _ticker?.cancel();
    setState(() {
      _isBreak = true;
      _workFinished = false;
      _remainingSeconds = _block.breakAfterMinutes * 60;
      _totalSeconds = _remainingSeconds;
    });
    _toggleTimer();
  }

  Future<void> _markComplete() async {
    setState(() => _savingCompletion = true);
    try {
      await widget.onCompleteBlock(_block);
      if (!mounted) return;
      final next = _blockIndex + 1;
      setState(() {
        _blockIndex = next >= widget.blocks.length ? _blockIndex : next;
        _resetTimer();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('학습 완료로 표시했어요.'),
            behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (mounted) setState(() => _savingCompletion = false);
    }
  }

  void _changeBlock(int delta) {
    final next = _blockIndex + delta;
    if (next < 0 || next >= widget.blocks.length) return;
    setState(() {
      _blockIndex = next;
      _resetTimer();
    });
  }

  String get _timeLabel {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final progress =
        _totalSeconds == 0 ? 0.0 : _remainingSeconds / _totalSeconds;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _greenDark,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.timer_outlined, color: Color(0xffc8ead2)),
              SizedBox(width: 8),
              Text('학습 타이머',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 17)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _isBreak ? '휴식 중 · ${_block.breakAfterMinutes}분' : _block.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xffd6e6dc), height: 1.35),
          ),
          const SizedBox(height: 18),
          Center(
            child: SizedBox(
              width: 136,
              height: 136,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    strokeWidth: 9,
                    backgroundColor: const Color(0xff3d6858),
                    color: const Color(0xffb9dfc9),
                  ),
                  Center(
                    child: Text(
                      _timeLabel,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 27),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 17),
          Row(
            children: [
              IconButton(
                onPressed: _blockIndex == 0 ? null : () => _changeBlock(-1),
                color: Colors.white,
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xffb9dfc9),
                      foregroundColor: _greenDark),
                  onPressed: _workFinished ? null : _toggleTimer,
                  icon: Icon(_running
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded),
                  label: Text(_running
                      ? '일시정지'
                      : _isBreak
                          ? '휴식 시작'
                          : '집중 시작'),
                ),
              ),
              IconButton(
                onPressed: _blockIndex + 1 >= widget.blocks.length
                    ? null
                    : () => _changeBlock(1),
                color: Colors.white,
                icon: const Icon(Icons.skip_next_rounded),
              ),
              IconButton(
                onPressed: _resetTimer,
                color: const Color(0xffc8ead2),
                icon: const Icon(Icons.restart_alt_rounded),
              ),
            ],
          ),
          if (_workFinished) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (_block.breakAfterMinutes > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _startBreak,
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xff87b19b))),
                      child: Text('${_block.breakAfterMinutes}분 휴식'),
                    ),
                  ),
                if (_block.breakAfterMinutes > 0) const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _savingCompletion ? null : _markComplete,
                    child: Text(_savingCompletion ? '저장 중...' : '완료 처리'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Center(
            child: Text('${_blockIndex + 1} / ${widget.blocks.length}번째 학습',
                style: const TextStyle(color: Color(0xffb5d0c0), fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class DailyRhythmSheet extends StatefulWidget {
  const DailyRhythmSheet({
    super.key,
    required this.day,
    required this.preferences,
  });

  final ScheduleDay day;
  final StudyPreferences preferences;

  @override
  State<DailyRhythmSheet> createState() => _DailyRhythmSheetState();
}

class _DailyRhythmSheetState extends State<DailyRhythmSheet> {
  late int _available;
  late TimeOfDay _start;
  late int _focus;
  late int _break;

  @override
  void initState() {
    super.initState();
    final override = widget.preferences.overrideFor(widget.day.date);
    _available = override?.availableMinutes ??
        widget.preferences.dailyAvailability[widget.day.date.weekday - 1] ??
        0;
    _start = _parseTime(
      override?.preferredStartTime ??
          (widget.day.blocks.isEmpty
              ? widget.preferences.preferredStartTime
              : widget.day.blocks.first.startTime),
    );
    _focus = override?.focusMinutes ?? widget.preferences.focusMinutes;
    _break = override?.breakMinutes ?? widget.preferences.breakMinutes;
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Material(
          color: _paper,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(child: _SheetHandle()),
                  const SizedBox(height: 18),
                  Text(
                    DateFormat('M월 d일 EEEE', 'ko_KR').format(widget.day.date),
                    style: const TextStyle(
                        color: _green, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '이날의 리듬만 바꾸기',
                    style: TextStyle(
                      fontSize: 25,
                      letterSpacing: -0.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '다른 요일의 기본 설정은 그대로 유지돼요.',
                    style: TextStyle(color: _muted),
                  ),
                  const SizedBox(height: 22),
                  _PreferenceCard(
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '학습 가능 시간',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          Text(
                            _available == 0 ? '쉬는 날' : '$_available분',
                            style: const TextStyle(
                              color: _green,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _available.toDouble(),
                        min: 0,
                        max: 360,
                        divisions: 24,
                        activeColor: _green,
                        onChanged: (value) =>
                            setState(() => _available = value.round()),
                      ),
                      const Divider(height: 26, color: _line),
                      _SettingsRow(
                        icon: Icons.schedule_rounded,
                        title: '시작 시간',
                        value: _start.format(context),
                        onTap: () async {
                          final next = await showTimePicker(
                            context: context,
                            initialTime: _start,
                          );
                          if (next != null) setState(() => _start = next);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _PreferenceCard(
                    children: [
                      _MinutePicker(
                        label: '한 번에 집중',
                        value: _focus,
                        options: const [25, 40, 50, 60],
                        onChanged: (value) => setState(() => _focus = value),
                      ),
                      const SizedBox(height: 18),
                      _MinutePicker(
                        label: '블록 사이 휴식',
                        value: _break,
                        options: const [0, 5, 10, 15, 20],
                        onChanged: (value) => setState(() => _break = value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      DateStudyOverride(
                        date: widget.day.date,
                        availableMinutes: _available,
                        preferredStartTime: _timeValue(_start),
                        focusMinutes: _focus,
                        breakMinutes: _break,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                    ),
                    child: const Text('이 설정으로 일정 다시 맞추기'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class ContentItemSheet extends StatefulWidget {
  const ContentItemSheet({
    super.key,
    this.item,
    required this.kind,
    required this.nextId,
  });

  final ContentItem? item;
  final PlanKind kind;
  final String nextId;

  @override
  State<ContentItemSheet> createState() => _ContentItemSheetState();
}

class _ContentItemSheetState extends State<ContentItemSheet> {
  late final _chapter = TextEditingController(
    text: widget.item?.chapter ?? '',
  );
  late final _section = TextEditingController(
    text: widget.item?.section ?? '',
  );
  late final _title = TextEditingController(text: widget.item?.title ?? '');
  late final _minutes = TextEditingController(
    text: widget.item?.estimatedMinutes?.toString() ?? '',
  );

  @override
  void dispose() {
    _chapter.dispose();
    _section.dispose();
    _title.dispose();
    _minutes.dispose();
    super.dispose();
  }

  void _save() {
    if (_chapter.text.trim().isEmpty || _title.text.trim().isEmpty) return;
    Navigator.pop(
      context,
      ContentItem(
        id: widget.item?.id ?? widget.nextId,
        chapter: _chapter.text.trim(),
        section: _section.text.trim().isEmpty ? null : _section.text.trim(),
        title: _title.text.trim(),
        estimatedMinutes: int.tryParse(_minutes.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
          14,
          14,
          14,
          MediaQuery.viewInsetsOf(context).bottom + 14,
        ),
        child: Material(
          color: _paper,
          borderRadius: BorderRadius.circular(28),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: _SheetHandle()),
                const SizedBox(height: 18),
                Text(
                  widget.item == null
                      ? '새 ${widget.kind.itemLabel}'
                      : '${widget.kind.itemLabel} 수정',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _chapter,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: widget.kind == PlanKind.book ? '장' : '과목',
                    hintText: widget.kind == PlanKind.book ? '예: 1장' : '예: 수학',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _section,
                  decoration: InputDecoration(
                    labelText:
                        widget.kind == PlanKind.book ? '절 · 선택' : '단원 · 선택',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _title,
                  decoration: InputDecoration(
                    labelText:
                        widget.kind == PlanKind.book ? '학습할 제목' : '학습할 단원',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _minutes,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '예상 시간(분) · 선택'),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: Text('${widget.kind.itemLabel}에 저장'),
                ),
              ],
            ),
          ),
        ),
      );
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.entries,
    required this.totalMinutes,
    required this.onOpen,
  });

  final List<(LocalPlan, ScheduleDay)> entries;
  final int totalMinutes;
  final ValueChanged<LocalPlan> onOpen;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: _line),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0d18211d),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: entries.isEmpty
            ? const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Eyebrow(icon: Icons.wb_sunny_rounded, label: '오늘'),
                  SizedBox(height: 14),
                  Text(
                    '오늘은 비워 둔 날이에요.',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '충분히 쉬거나, 새 계획을 가볍게 시작해 보세요.',
                    style: TextStyle(color: _muted, height: 1.45),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Eyebrow(
                    icon: Icons.bolt_rounded,
                    label: '오늘의 학습',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$totalMinutes분 · ${entries.length}개 계획',
                    style: const TextStyle(
                      fontSize: 24,
                      letterSpacing: -0.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ...entries.map(
                    (entry) => InkWell(
                      onTap: () => onOpen(entry.$1),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: entry.$1.kind == PlanKind.book
                                    ? _sage
                                    : _peach,
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Icon(
                                entry.$1.kind == PlanKind.book
                                    ? Icons.menu_book_rounded
                                    : Icons.flag_rounded,
                                size: 19,
                                color: _greenDark,
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.$1.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    entry.$2.blocks.first.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _muted,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: Color(0xffa4ada8),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      );
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.onTap});

  final LocalPlan plan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final total = plan.contents.length;
    final done = plan.completedIds.length.clamp(0, total);
    final percent = total == 0 ? 0.0 : done / total;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _line),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: plan.kind == PlanKind.book ? _sage : _peach,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  plan.kind == PlanKind.book
                      ? Icons.menu_book_rounded
                      : Icons.flag_rounded,
                  color: _greenDark,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            plan.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Text(
                          '${(percent * 100).round()}%',
                          style: const TextStyle(
                            color: _green,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: percent,
                        minHeight: 5,
                        backgroundColor: const Color(0xffedf0ec),
                        color: _green,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '${plan.kind.label} · ${DateFormat('M월 d일', 'ko_KR').format(plan.preferences.deadline)}까지',
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xffa4ada8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyPlans extends StatelessWidget {
  const _EmptyPlans({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xffecefe9),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.route_rounded,
                color: _green,
                size: 30,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '첫 계획을 만들어 볼까요?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            const Text(
              '책이 없어도 괜찮아요. 원하는 목표를\n실행 가능한 일정으로 나눠 드려요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, height: 1.45),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('계획 추가'),
            ),
          ],
        ),
      );
}

class _ScheduleDayCard extends StatelessWidget {
  const _ScheduleDayCard({
    required this.day,
    required this.completed,
    required this.dailyCheckIn,
    required this.adjusting,
    required this.onEdit,
    required this.onToggle,
  });

  final ScheduleDay day;
  final Set<String> completed;
  final bool? dailyCheckIn;
  final bool adjusting;
  final VoidCallback onEdit;
  final Future<void> Function(String, bool) onToggle;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(17, 14, 17, 14),
        decoration: _cardDecoration(radius: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    DateFormat('M월 d일 (E)', 'ko_KR').format(day.date),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: adjusting ? null : onEdit,
                  icon: adjusting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.tune_rounded, size: 18),
                  label: Text(adjusting ? '조정 중' : '이날 설정'),
                  style: TextButton.styleFrom(
                    foregroundColor: _green,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            if (dailyCheckIn != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text(
                  dailyCheckIn! ? '✓ 일일 학습 완료 확인' : '↻ 미완료 분량 일정 재조정 완료',
                  style: TextStyle(
                    color: dailyCheckIn! ? _green : _muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            if (day.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 6),
                child: Text(
                  day.note,
                  style: const TextStyle(color: _muted, height: 1.4),
                ),
              ),
            ...day.blocks.map((block) {
              final isDone = block.contentIds.every(completed.contains);
              return CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: isDone,
                activeColor: _green,
                checkboxShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
                onChanged: (value) async {
                  for (final id in block.contentIds) {
                    await onToggle(id, value ?? false);
                  }
                },
                title: Text(
                  block.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    decoration: isDone ? TextDecoration.lineThrough : null,
                    color: isDone ? _muted : _ink,
                  ),
                ),
                subtitle: Text(
                  '${block.startTime} · ${block.durationMinutes}분'
                  '${block.breakAfterMinutes == 0 ? '' : ' · 휴식 ${block.breakAfterMinutes}분'}',
                ),
              );
            }),
            if (day.reviewMinutes > 0 || day.bufferMinutes > 0)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xfff0f2ee),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '복습 ${day.reviewMinutes}분 · 여유 ${day.bufferMinutes}분',
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
              ),
          ],
        ),
      );
}

class _KindCard extends StatelessWidget {
  const _KindCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? _greenDark : Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? _greenDark : _line,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  color: selected ? Colors.white : _green,
                  size: 27,
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: TextStyle(
                    color: selected ? Colors.white : _ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: selected ? const Color(0xffc9d9d1) : _muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              border: Border.all(color: _line),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xffa4ada8),
                ),
              ],
            ),
          ),
        ),
      );
}

class _EmptyContents extends StatelessWidget {
  const _EmptyContents({required this.kind});
  final PlanKind kind;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: kind == PlanKind.book ? _sage : _peach,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  kind == PlanKind.book
                      ? Icons.format_list_bulleted_add
                      : Icons.account_tree_rounded,
                  color: _greenDark,
                  size: 34,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '첫 ${kind.itemLabel}를 추가해 볼까요?',
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
              ),
              const SizedBox(height: 6),
              Text(
                kind == PlanKind.book
                    ? '상단의 목차 추가 버튼으로 항목을 입력해 주세요.'
                    : '목표를 이루기 위한 작은 단계부터 시작해요.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted),
              ),
            ],
          ),
        ),
      );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _greenDark,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 9),
          const Text(
            '하루공부',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 19,
              letterSpacing: -0.5,
            ),
          ),
        ],
      );
}

class _TopProgress extends StatelessWidget {
  const _TopProgress({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          3,
          (index) => AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: index < step ? 28 : 18,
            height: 5,
            margin: const EdgeInsets.only(right: 5),
            decoration: BoxDecoration(
              color: index < step ? _green : const Color(0xffd8ddd9),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      );
}

class _KindPill extends StatelessWidget {
  const _KindPill({required this.kind});
  final PlanKind kind;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: kind == PlanKind.book ? _sage : _peach,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          kind.label,
          style: const TextStyle(
            color: _greenDark,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _green, size: 18),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: _green,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      );
}

class _FieldTitle extends StatelessWidget {
  const _FieldTitle({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
        ],
      );
}

class _PreferenceCard extends StatelessWidget {
  const _PreferenceCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(17),
        decoration: _cardDecoration(radius: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Icon(icon, color: _green),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: _green,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xffa4ada8),
              ),
            ],
          ),
        ),
      );
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.active,
    required this.minutes,
    required this.onTap,
  });

  final String label;
  final bool active;
  final int minutes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 39,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? _greenDark : const Color(0xfff0f2ee),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: active ? Colors.white : _ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                minutes == 0 ? '쉼' : '${minutes}m',
                style: TextStyle(
                  fontSize: 9,
                  color: active ? const Color(0xffc9d9d1) : _muted,
                ),
              ),
            ],
          ),
        ),
      );
}

class _MinutePicker extends StatelessWidget {
  const _MinutePicker({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final int value;
  final List<int> options;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options
                .map(
                  (option) => ChoiceChip(
                    label: Text(option == 0 ? '없음' : '$option분'),
                    selected: value == option,
                    selectedColor: _sage,
                    side: BorderSide(
                      color: value == option ? _green : _line,
                    ),
                    labelStyle: TextStyle(
                      color: value == option ? _greenDark : _muted,
                      fontWeight: FontWeight.w800,
                    ),
                    onSelected: (_) => onChanged(option),
                  ),
                )
                .toList(),
          ),
        ],
      );
}

class _BottomButton extends StatelessWidget {
  const _BottomButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xf8f5f3ed),
            border: Border(top: BorderSide(color: _line)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: FilledButton(
            onPressed: enabled ? onPressed : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              disabledBackgroundColor: const Color(0xffcdd2ce),
            ),
            child: Text(label),
          ),
        ),
      );
}

class _LoadingMessage extends StatelessWidget {
  const _LoadingMessage({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: _green,
            ),
          ),
          const SizedBox(height: 12),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0xffffead8),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline_rounded,
              color: Color(0xff9a5c2d),
              size: 20,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Color(0xff714927),
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) => Container(
        width: 38,
        height: 5,
        decoration: BoxDecoration(
          color: const Color(0xffcbd0cc),
          borderRadius: BorderRadius.circular(8),
        ),
      );
}

BoxDecoration _cardDecoration({required double radius}) => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: _line),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0918211d),
          blurRadius: 16,
          offset: Offset(0, 5),
        ),
      ],
    );

TimeOfDay _parseTime(String value) {
  final parts = value.split(':');
  return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}

String _timeValue(TimeOfDay value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

String _dateOnly(DateTime value) => value.toIso8601String().substring(0, 10);

bool _sameDay(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

int _daysUntil(DateTime deadline) {
  final today = DateTime.now();
  final date = DateTime(today.year, today.month, today.day);
  return deadline.difference(date).inDays.clamp(0, 9999);
}
