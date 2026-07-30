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
    if (!_validTitle(title)) return;
    setState(() {
      _draftKind = kind;
      _draftTitle = title.trim();
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
                      title: '자유 목표',
                      subtitle: '단계를 직접 구성',
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
                  labelText: _kind == PlanKind.book ? '책 제목' : '목표 이름',
                  hintText: _kind == PlanKind.book
                      ? '예: 해커스 토익 리딩'
                      : '예: 8월까지 포트폴리오 완성',
                ),
              ),
              const SizedBox(height: 26),
              Text(
                _kind == PlanKind.book ? '목차를 어떻게 가져올까요?' : '학습 단계를 만들어 볼까요?',
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
                    : Icons.account_tree_rounded,
                color: const Color(0xff74558f),
                title: _kind == PlanKind.book ? '목차 직접 입력' : '학습 단계 직접 만들기',
                subtitle: _kind == PlanKind.book
                    ? '사진 없이 장·절을 추가해요'
                    : '목표를 작은 실행 단계로 나눠요',
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
    required this.onBack,
    required this.onGenerate,
  });

  final VoidCallback onBack;
  final Future<void> Function(StudyPreferences) onGenerate;

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
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
  bool _busy = false;
  static const _days = ['월', '화', '수', '목', '금', '토', '일'];

  Future<void> _submit() async {
    final availability = <int, int>{
      for (final entry in _minutes.entries.where((entry) => entry.value > 0))
        entry.key: entry.value,
    };
    if (availability.isEmpty) return;
    final preferences = StudyPreferences(
      deadline: _deadline,
      dailyAvailability: availability,
      preferredStartTime: _timeValue(_start),
      focusMinutes: _focus,
      breakMinutes: _break,
      bufferMinutes: _buffer,
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
                    icon: Icons.event_rounded,
                    title: '마감일',
                    value: DateFormat('M월 d일 (E)', 'ko_KR').format(_deadline),
                    onTap: () async {
                      final next = await showDatePicker(
                        context: context,
                        initialDate: _deadline,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 730)),
                        locale: const Locale('ko'),
                      );
                      if (next != null) setState(() => _deadline = next);
                    },
                  ),
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
    required this.onUpdateDay,
  });

  final LocalPlan plan;
  final VoidCallback onBack;
  final VoidCallback onAddPlan;
  final Future<void> Function() onDelete;
  final Future<void> Function(String, bool) onToggle;
  final Future<void> Function() onReplan;
  final Future<void> Function(DateStudyOverride) onUpdateDay;

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  bool _replanning = false;
  String? _adjustingDate;

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
                    labelText: widget.kind == PlanKind.book ? '장' : '단계',
                    hintText: widget.kind == PlanKind.book ? '예: 1장' : '예: 1단계',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _section,
                  decoration: InputDecoration(
                    labelText:
                        widget.kind == PlanKind.book ? '절 · 선택' : '분류 · 선택',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _title,
                  decoration: InputDecoration(
                    labelText:
                        widget.kind == PlanKind.book ? '학습할 제목' : '실행할 내용',
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
    required this.adjusting,
    required this.onEdit,
    required this.onToggle,
  });

  final ScheduleDay day;
  final Set<String> completed;
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
