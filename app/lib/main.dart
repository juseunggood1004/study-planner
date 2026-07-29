import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'api_client.dart';
import 'local_store.dart';
import 'models.dart';

const _ink = Color(0xff17213a);
const _navy = Color(0xff1d2f6f);
const _blue = Color(0xff4169e1);
const _mint = Color(0xffd9f5ed);
const _paper = Color(0xfff6f7fb);

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
          colorScheme: ColorScheme.fromSeed(seedColor: _blue, brightness: Brightness.light),
          appBarTheme: const AppBarTheme(backgroundColor: _paper, foregroundColor: _ink, elevation: 0, centerTitle: false),
          textTheme: ThemeData.light().textTheme.apply(bodyColor: _ink, displayColor: _ink),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xffd8ddea))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xffd8ddea))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _blue, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
        home: const StudyShell(),
      );
}

enum _Stage { start, contents, preferences, plan }

class StudyShell extends StatefulWidget {
  const StudyShell({super.key});

  @override
  State<StudyShell> createState() => _StudyShellState();
}

class _StudyShellState extends State<StudyShell> {
  final _store = LocalStore();
  final _api = ApiClient();
  _Stage _stage = _Stage.start;
  bool _loading = true;
  bool _extracting = false;
  LocalPlan? _plan;
  String _bookTitle = '';
  List<ContentItem> _contents = [];

  @override
  void initState() {
    super.initState();
    _restorePlan();
  }

  Future<void> _restorePlan() async {
    final saved = await _store.loadPlan();
    if (!mounted) return;
    setState(() {
      _plan = saved;
      _stage = saved == null ? _Stage.start : _Stage.plan;
      _loading = false;
    });
  }

  Future<void> _extract(String bookTitle, ImageSource source) async {
    if (bookTitle.trim().isEmpty) {
      _message('먼저 책 제목을 입력해 주세요.');
      return;
    }
    final image = await ImagePicker().pickImage(source: source, imageQuality: 88, maxWidth: 2400);
    if (image == null) return;
    await _extractFromFile(bookTitle, File(image.path));
  }

  Future<void> _extractFromFile(String bookTitle, File image) async {
    setState(() => _extracting = true);
    try {
      final extracted = await _api.extractContents(image);
      if (!mounted) return;
      setState(() {
        _bookTitle = bookTitle.trim();
        _contents = extracted;
        _stage = _Stage.contents;
      });
    } catch (error) {
      _message(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  void _startManual(String bookTitle) {
    if (bookTitle.trim().isEmpty) {
      _message('먼저 책 제목을 입력해 주세요.');
      return;
    }
    setState(() {
      _bookTitle = bookTitle.trim();
      _contents = [];
      _stage = _Stage.contents;
    });
  }

  Future<void> _createPlan(StudyPreferences preferences) async {
    if (_contents.isEmpty) {
      _message('목차를 하나 이상 추가해 주세요.');
      return;
    }
    try {
      final draft = LocalPlanDraft(bookTitle: _bookTitle, contents: _contents, preferences: preferences);
      final schedule = await _api.generate(draft);
      final plan = LocalPlan(
        installationId: await _store.installationId(),
        bookTitle: _bookTitle,
        contents: _contents,
        preferences: preferences,
        schedule: schedule,
        completedIds: {},
      );
      await _store.savePlan(plan);
      if (mounted) setState(() { _plan = plan; _stage = _Stage.plan; });
    } catch (error) {
      _message(_friendlyError(error));
      rethrow;
    }
  }

  Future<void> _toggleCompleted(String id, bool selected) async {
    final plan = _plan;
    if (plan == null) return;
    setState(() {
      if (selected) { plan.completedIds.add(id); } else { plan.completedIds.remove(id); }
    });
    await _store.savePlan(plan);
  }

  Future<void> _replan() async {
    final plan = _plan;
    if (plan == null) return;
    try {
      final schedule = await _api.replan(plan);
      if (!mounted) return;
      setState(() => plan.schedule = schedule);
      await _store.savePlan(plan);
    } catch (error) {
      _message(_friendlyError(error));
      rethrow;
    }
  }

  Future<void> _newPlan() async {
    await _store.clearPlan();
    if (mounted) setState(() { _plan = null; _bookTitle = ''; _contents = []; _stage = _Stage.start; });
  }

  String _friendlyError(Object error) => error.toString().replaceFirst('Exception: ', '').replaceFirst('ApiException: ', '');
  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: switch (_stage) {
        _Stage.start => WelcomeScreen(
            key: const ValueKey('start'),
            busy: _extracting,
            onCamera: (title) => _extract(title, ImageSource.camera),
            onGallery: (title) => _extract(title, ImageSource.gallery),
            onManual: _startManual,
          ),
        _Stage.contents => ContentsScreen(
            key: const ValueKey('contents'),
            bookTitle: _bookTitle,
            items: _contents,
            onBack: () => setState(() => _stage = _Stage.start),
            onContinue: (items) => setState(() { _contents = items; _stage = _Stage.preferences; }),
          ),
        _Stage.preferences => PreferencesScreen(
            key: const ValueKey('preferences'),
            onBack: () => setState(() => _stage = _Stage.contents),
            onGenerate: _createPlan,
          ),
        _Stage.plan => PlanScreen(
            key: const ValueKey('plan'),
            plan: _plan!,
            onNewPlan: _newPlan,
            onToggle: _toggleCompleted,
            onReplan: _replan,
          ),
      },
    );
  }
}

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.busy, required this.onCamera, required this.onGallery, required this.onManual});
  final bool busy;
  final ValueChanged<String> onCamera;
  final ValueChanged<String> onGallery;
  final ValueChanged<String> onManual;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _title = TextEditingController();
  @override
  void dispose() { _title.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 32), children: [
            const _BrandMark(),
            const SizedBox(height: 26),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(colors: [_navy, _blue], begin: Alignment.topLeft, end: Alignment.bottomRight),
              ),
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('마감일까지,\n하루씩 가볍게.', style: TextStyle(fontSize: 29, height: 1.22, color: Colors.white, fontWeight: FontWeight.w800)),
                SizedBox(height: 12),
                Text('목차와 나의 시간을 알려주면\n오늘 해야 할 공부를 정리해 드려요.', style: TextStyle(fontSize: 15, height: 1.55, color: Color(0xffdfe8ff))),
              ]),
            ),
            const SizedBox(height: 28),
            const _SectionLabel(number: '01', title: '공부할 책을 알려주세요'),
            const SizedBox(height: 12),
            TextField(controller: _title, textInputAction: TextInputAction.done, decoration: const InputDecoration(labelText: '책 제목', hintText: '예: 해커스 토익 리딩')),
            const SizedBox(height: 26),
            const _SectionLabel(number: '02', title: '목차를 가져오는 방법을 골라주세요'),
            const SizedBox(height: 12),
            _ActionCard(icon: Icons.document_scanner_outlined, color: const Color(0xff7d5ce6), title: '목차 사진으로 시작', subtitle: 'AI가 장·절 목록을 읽어드려요', onTap: widget.busy ? null : () => widget.onCamera(_title.text)),
            const SizedBox(height: 10),
            _ActionCard(icon: Icons.photo_library_outlined, color: const Color(0xffe27644), title: '갤러리에서 사진 선택', subtitle: '이미 찍어둔 목차 사진을 사용해요', onTap: widget.busy ? null : () => widget.onGallery(_title.text)),
            const SizedBox(height: 10),
            _ActionCard(icon: Icons.edit_note_outlined, color: const Color(0xff238b78), title: '직접 목차 입력', subtitle: '사진 없이 바로 항목을 추가할 수 있어요', onTap: widget.busy ? null : () => widget.onManual(_title.text)),
            if (widget.busy) const Padding(padding: EdgeInsets.only(top: 26), child: _LoadingMessage(label: '목차를 읽고 있어요…')),
          ]),
        ),
      );
}

class ContentsScreen extends StatefulWidget {
  const ContentsScreen({super.key, required this.bookTitle, required this.items, required this.onBack, required this.onContinue});
  final String bookTitle;
  final List<ContentItem> items;
  final VoidCallback onBack;
  final ValueChanged<List<ContentItem>> onContinue;
  @override
  State<ContentsScreen> createState() => _ContentsScreenState();
}

class _ContentsScreenState extends State<ContentsScreen> {
  late final List<ContentItem> _items = [...widget.items];

  Future<void> _edit([ContentItem? item]) async {
    final result = await showModalBottomSheet<ContentItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ContentItemSheet(item: item, nextId: 'c${DateTime.now().microsecondsSinceEpoch}'),
    );
    if (!mounted || result == null) return;
    setState(() {
      if (item == null) { _items.add(result); } else { _items[_items.indexOf(item)] = result; }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack), title: const _TopProgress(step: 2)),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: _ink,
          foregroundColor: Colors.white,
          onPressed: _edit,
          icon: const Icon(Icons.add),
          label: const Text('항목 추가'),
        ),
        body: SafeArea(
          child: Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.bookTitle, style: const TextStyle(color: _blue, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('목차를 확인해 주세요', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('순서를 바꾸거나 내용을 눌러 수정할 수 있어요.'),
            ])),
            Expanded(
              child: _items.isEmpty
                  ? const _EmptyContents()
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                      itemCount: _items.length,
                      onReorderItem: (from, to) => setState(() { final moved = _items.removeAt(from); _items.insert(to, moved); }),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return Container(
                          key: ValueKey(item.id),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: const [BoxShadow(color: Color(0x0a17213a), blurRadius: 12, offset: Offset(0, 4))]),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                            leading: ReorderableDragStartListener(index: index, child: const Icon(Icons.drag_indicator, color: Color(0xff9ba5ba))),
                            title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text('${item.chapter}${item.section == null ? '' : ' · ${item.section}'}${item.estimatedMinutes == null ? '' : ' · 약 ${item.estimatedMinutes}분'}'),
                            trailing: IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => setState(() => _items.removeAt(index))),
                            onTap: () => _edit(item),
                          ),
                        );
                      },
                    ),
            ),
            _BottomButton(label: '학습 시간 정하기', enabled: _items.isNotEmpty, onPressed: () => widget.onContinue(_items)),
          ]),
        ),
      );
}

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({super.key, required this.onBack, required this.onGenerate});
  final VoidCallback onBack;
  final Future<void> Function(StudyPreferences) onGenerate;
  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  DateTime _deadline = DateTime.now().add(const Duration(days: 30));
  TimeOfDay _start = const TimeOfDay(hour: 19, minute: 0);
  final Map<int, int> _minutes = {0: 60, 1: 60, 2: 60, 3: 60, 4: 60, 5: 90, 6: 90};
  int _selectedDay = DateTime.now().weekday - 1;
  int _focus = 40;
  int _break = 10;
  int _buffer = 20;
  bool _busy = false;
  static const _days = ['월', '화', '수', '목', '금', '토', '일'];

  Future<void> _submit() async {
    final availability = <int, int>{for (final entry in _minutes.entries.where((entry) => entry.value > 0)) entry.key: entry.value};
    if (availability.isEmpty) return;
    final preferences = StudyPreferences(
      deadline: _deadline,
      dailyAvailability: availability,
      preferredStartTime: '${_start.hour.toString().padLeft(2, '0')}:${_start.minute.toString().padLeft(2, '0')}',
      focusMinutes: _focus,
      breakMinutes: _break,
      bufferMinutes: _buffer,
    );
    setState(() => _busy = true);
    try { await widget.onGenerate(preferences); } catch (_) {} finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack), title: const _TopProgress(step: 3)),
        body: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 112), children: [
          const Text('나만의 리듬을\n정해볼까요?', style: TextStyle(fontSize: 27, height: 1.25, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('지킬 수 있는 분량으로 AI가 일정을 나눠 드려요.'),
          const SizedBox(height: 26),
          _PreferenceCard(children: [
            _SettingsRow(icon: Icons.event_outlined, title: '마감일', value: DateFormat('M월 d일 (E)', 'ko_KR').format(_deadline), onTap: () async { final next = await showDatePicker(context: context, initialDate: _deadline, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 730)), locale: const Locale('ko')); if (next != null) setState(() => _deadline = next); }),
            const Divider(height: 24),
            _SettingsRow(icon: Icons.schedule_outlined, title: '공부 시작 시간', value: _start.format(context), onTap: () async { final next = await showTimePicker(context: context, initialTime: _start); if (next != null) setState(() => _start = next); }),
          ]),
          const SizedBox(height: 18),
          const Text('요일별 공부 가능 시간', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 12),
          _PreferenceCard(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: List.generate(7, (index) => _DayChip(label: _days[index], active: _selectedDay == index, minutes: _minutes[index]!, onTap: () => setState(() => _selectedDay = index)))),
            const SizedBox(height: 18),
            Row(children: [Text('${_days[_selectedDay]}요일', style: const TextStyle(fontWeight: FontWeight.w700)), const Spacer(), Text('${_minutes[_selectedDay]}분', style: const TextStyle(color: _blue, fontWeight: FontWeight.w800))]),
            Slider(value: _minutes[_selectedDay]!.toDouble(), min: 0, max: 360, divisions: 12, label: '${_minutes[_selectedDay]}분', onChanged: (value) => setState(() => _minutes[_selectedDay] = value.round())),
          ]),
          const SizedBox(height: 18),
          const Text('집중 방식', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 12),
          _PreferenceCard(children: [
            _MinutePicker(label: '한 번에 집중', value: _focus, options: const [25, 40, 50, 60], onChanged: (value) => setState(() => _focus = value)),
            const SizedBox(height: 16),
            _MinutePicker(label: '휴식 간격', value: _break, options: const [5, 10, 15, 20], onChanged: (value) => setState(() => _break = value)),
            const SizedBox(height: 16),
            _MinutePicker(label: '하루 여유 시간', value: _buffer, options: const [0, 10, 20, 30], onChanged: (value) => setState(() => _buffer = value)),
          ]),
        ])),
        bottomNavigationBar: _BottomButton(label: _busy ? 'AI가 일정을 만들고 있어요…' : '맞춤 일정 만들기', enabled: !_busy, onPressed: _submit),
      );
}

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key, required this.plan, required this.onNewPlan, required this.onToggle, required this.onReplan});
  final LocalPlan plan;
  final Future<void> Function() onNewPlan;
  final Future<void> Function(String, bool) onToggle;
  final Future<void> Function() onReplan;
  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  bool _replanning = false;
  Future<void> _runReplan() async { setState(() => _replanning = true); try { await widget.onReplan(); } catch (_) {} finally { if (mounted) setState(() => _replanning = false); } }

  @override
  Widget build(BuildContext context) {
    final allBlocks = widget.plan.schedule.days.expand((day) => day.blocks).toList();
    final done = allBlocks.where((block) => block.contentIds.every(widget.plan.completedIds.contains)).length;
    final percent = allBlocks.isEmpty ? 0.0 : done / allBlocks.length;
    return Scaffold(
      appBar: AppBar(title: const _BrandMark(compact: true), actions: [IconButton(tooltip: '새 계획', icon: const Icon(Icons.add_circle_outline), onPressed: widget.onNewPlan)]),
      body: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
        Text(widget.plan.bookTitle, style: const TextStyle(color: _blue, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        const Text('오늘의 학습 플랜', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(25)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('완독까지의 여정', style: TextStyle(color: Color(0xffbdc8e6))),
            const SizedBox(height: 8),
            Text('$done / ${allBlocks.length} 블록 완료', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            ClipRRect(borderRadius: BorderRadius.circular(10), child: LinearProgressIndicator(value: percent, minHeight: 9, backgroundColor: const Color(0xff3a4665), color: const Color(0xff86e5cb))),
            const SizedBox(height: 12),
            Text(widget.plan.schedule.summary, style: const TextStyle(color: Color(0xffdce4f7), height: 1.45)),
          ]),
        ),
        if (widget.plan.schedule.warnings.isNotEmpty) ...[
          const SizedBox(height: 14),
          ...widget.plan.schedule.warnings.map((warning) => _Notice(text: warning)),
        ],
        const SizedBox(height: 18),
        OutlinedButton.icon(onPressed: _replanning ? null : _runReplan, icon: const Icon(Icons.auto_awesome_outlined), label: Text(_replanning ? '일정을 조정하고 있어요…' : '진행 상황 반영해 다시 짜기')),
        const SizedBox(height: 22),
        ...widget.plan.schedule.days.map((day) => _ScheduleDayCard(day: day, completed: widget.plan.completedIds, onToggle: widget.onToggle)),
      ])),
    );
  }
}

class ContentItemSheet extends StatefulWidget {
  const ContentItemSheet({super.key, this.item, required this.nextId});
  final ContentItem? item;
  final String nextId;
  @override
  State<ContentItemSheet> createState() => _ContentItemSheetState();
}

class _ContentItemSheetState extends State<ContentItemSheet> {
  late final _chapter = TextEditingController(text: widget.item?.chapter ?? '');
  late final _section = TextEditingController(text: widget.item?.section ?? '');
  late final _title = TextEditingController(text: widget.item?.title ?? '');
  late final _minutes = TextEditingController(text: widget.item?.estimatedMinutes?.toString() ?? '');
  @override
  void dispose() { _chapter.dispose(); _section.dispose(); _title.dispose(); _minutes.dispose(); super.dispose(); }

  void _save() {
    if (_chapter.text.trim().isEmpty || _title.text.trim().isEmpty) return;
    Navigator.pop(context, ContentItem(id: widget.item?.id ?? widget.nextId, chapter: _chapter.text.trim(), section: _section.text.trim().isEmpty ? null : _section.text.trim(), title: _title.text.trim(), estimatedMinutes: int.tryParse(_minutes.text)));
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.viewInsetsOf(context).bottom + 22),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          child: Padding(padding: const EdgeInsets.all(22), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: const Color(0xffd7dcea), borderRadius: BorderRadius.circular(8))),
            Text(widget.item == null ? '새 목차 항목' : '목차 항목 수정', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 18),
            TextField(controller: _chapter, autofocus: true, decoration: const InputDecoration(labelText: '장')),
            const SizedBox(height: 10),
            TextField(controller: _section, decoration: const InputDecoration(labelText: '절 · 선택')),
            const SizedBox(height: 10),
            TextField(controller: _title, decoration: const InputDecoration(labelText: '학습할 제목')),
            const SizedBox(height: 10),
            TextField(controller: _minutes, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '예상 시간(분) · 선택')),
            const SizedBox(height: 18),
            FilledButton(onPressed: _save, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: _ink), child: const Text('목차에 저장')),
          ])),
        ),
      );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max, children: [
    Container(width: 34, height: 34, decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.auto_stories_rounded, color: Colors.white, size: 20)),
    const SizedBox(width: 9),
    const Text('하루공부', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19, letterSpacing: -0.5)),
  ]);
}

class _TopProgress extends StatelessWidget {
  const _TopProgress({required this.step});
  final int step;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          3,
          (index) => Container(
            width: 24,
            height: 5,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: index < step ? _blue : const Color(0xffdfe3ee),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.number, required this.title});
  final String number;
  final String title;
  @override
  Widget build(BuildContext context) => Row(children: [Text(number, style: const TextStyle(color: _blue, fontWeight: FontWeight.w900)), const SizedBox(width: 10), Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))]);
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(19),
    child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(19), child: Padding(padding: const EdgeInsets.all(15), child: Row(children: [
      Container(width: 46, height: 46, decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: color)),
      const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text(subtitle, style: const TextStyle(fontSize: 13, color: Color(0xff68738d)))])),
      const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Color(0xffaab2c3)),
    ]))),
  );
}

class _EmptyContents extends StatelessWidget {
  const _EmptyContents();
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Container(width: 72, height: 72, decoration: BoxDecoration(color: _mint, borderRadius: BorderRadius.circular(24)), child: const Icon(Icons.format_list_bulleted_add, color: Color(0xff238b78), size: 34)), const SizedBox(height: 14), const Text('첫 목차 항목을 추가해 볼까요?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)), const SizedBox(height: 6), const Text('오른쪽 아래의 추가 버튼을 눌러 주세요.', style: TextStyle(color: Color(0xff68738d)))]));
}

class _PreferenceCard extends StatelessWidget {
  const _PreferenceCard({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(17), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children));
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.icon, required this.title, required this.value, required this.onTap});
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, child: Row(children: [Icon(icon, color: _blue), const SizedBox(width: 12), Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))), Text(value, style: const TextStyle(color: _blue, fontWeight: FontWeight.w800)), const SizedBox(width: 5), const Icon(Icons.chevron_right, color: Color(0xffaab2c3))]));
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.label, required this.active, required this.minutes, required this.onTap});
  final String label;
  final bool active;
  final int minutes;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(13), child: Container(width: 38, padding: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: active ? _ink : const Color(0xfff0f2f7), borderRadius: BorderRadius.circular(13)), child: Column(children: [Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: active ? Colors.white : _ink)), const SizedBox(height: 2), Text(minutes == 0 ? '휴식' : '${minutes}m', style: TextStyle(fontSize: 9, color: active ? const Color(0xffcdd9ff) : const Color(0xff778198)))])));
}

class _MinutePicker extends StatelessWidget {
  const _MinutePicker({required this.label, required this.value, required this.options, required this.onChanged});
  final String label;
  final int value;
  final List<int> options;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options
                .map(
                  (option) => ChoiceChip(
                    label: Text(option == 0 ? '없음' : '$option분'),
                    selected: value == option,
                    onSelected: (_) => onChanged(option),
                  ),
                )
                .toList(),
          ),
        ],
      );
}

class _BottomButton extends StatelessWidget {
  const _BottomButton({required this.label, required this.enabled, required this.onPressed});
  final String label;
  final bool enabled;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          color: _paper,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
          child: FilledButton(
            onPressed: enabled ? onPressed : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              backgroundColor: _ink,
              disabledBackgroundColor: const Color(0xffcfd4df),
            ),
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      );
}

class _LoadingMessage extends StatelessWidget {
  const _LoadingMessage({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Column(children: [const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)), const SizedBox(height: 12), Text(label, style: const TextStyle(fontWeight: FontWeight.w700))]);
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: const Color(0xfffff1dd), borderRadius: BorderRadius.circular(15)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.info_outline, color: Color(0xffaa6717), size: 20), const SizedBox(width: 9), Expanded(child: Text(text, style: const TextStyle(color: Color(0xff73501d), height: 1.4)))]));
}

class _ScheduleDayCard extends StatelessWidget {
  const _ScheduleDayCard({required this.day, required this.completed, required this.onToggle});
  final ScheduleDay day;
  final Set<String> completed;
  final Future<void> Function(String, bool) onToggle;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat('M월 d일 (E)', 'ko_KR').format(day.date), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            if (day.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(day.note, style: const TextStyle(color: Color(0xff68738d))),
              ),
            const SizedBox(height: 8),
            ...day.blocks.map((block) {
              final isDone = block.contentIds.every(completed.contains);
              return CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: isDone,
                activeColor: _blue,
                onChanged: (value) async {
                  for (final id in block.contentIds) {
                    await onToggle(id, value ?? false);
                  }
                },
                title: Text('${block.startTime}  ${block.title}', style: TextStyle(fontWeight: FontWeight.w700, decoration: isDone ? TextDecoration.lineThrough : null)),
                subtitle: Text('${block.durationMinutes}분${block.breakAfterMinutes == 0 ? '' : ' · 휴식 ${block.breakAfterMinutes}분'}'),
              );
            }),
            if (day.reviewMinutes > 0 || day.bufferMinutes > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('복습 ${day.reviewMinutes}분 · 여유 ${day.bufferMinutes}분', style: const TextStyle(fontSize: 12, color: Color(0xff68738d))),
              ),
          ],
        ),
      );
}
