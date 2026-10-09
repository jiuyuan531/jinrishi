import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/task.dart';
import '../services/desktop.dart';
import '../services/holidays.dart';
import '../services/reminders.dart';
import '../services/store.dart';
import '../services/sync.dart';
import '../widgets/popup.dart';
import '../widgets/task_tile.dart';
import 'edit_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;
  DateTime _day = dateOnly(DateTime.now());
  String? _category; // null = 全部
  late final PopupQueue _popups = PopupQueue(() => context);
  StreamSubscription<PopupRequest>? _sub;

  @override
  void initState() {
    super.initState();
    Store.I.addListener(_refresh);
    SyncService.I.addListener(_refresh);
    _sub = Reminders.I.popups.stream.listen(_popups.add);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (Reminders.I.launchPayload != null) {
        Reminders.I.handlePayload(Reminders.I.launchPayload);
        Reminders.I.launchPayload = null;
      }
      if (Platform.isAndroid && !Store.I.settings.guideShown) {
        await showAndroidGuide(context);
      }
    });
  }

  @override
  void dispose() {
    Store.I.removeListener(_refresh);
    SyncService.I.removeListener(_refresh);
    _sub?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  bool get _isToday => _day == dateOnly(DateTime.now());

  Future<void> _openEditor([Task? t]) async {
    final initial = t?.copy() ?? (Task.blank()..date = dayKey(_day)..category = _category ?? '工作');
    await Navigator.push(context, MaterialPageRoute(builder: (_) => EditPage(task: initial, isNew: t == null)));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Desktop.I.miniNotifier,
      builder: (context, mini, _) => mini ? _buildMini(context) : _buildFull(context),
    );
  }

  // ---------- 小窗（Windows 置顶） ----------
  Widget _buildMini(BuildContext context) {
    final items = Store.I.occurrencesFor(DateTime.now(), includeOverdue: true);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(
        children: [
          Container(
            color: cs.primaryContainer,
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(children: [
              Expanded(
                child: Text('${dayTitle(DateTime.now())} · 剩 ${items.where((o) => !o.done).length} 项',
                    style: TextStyle(fontWeight: FontWeight.w600, color: cs.onPrimaryContainer)),
              ),
              IconButton(
                tooltip: '退出小窗',
                icon: const Icon(Icons.open_in_full, size: 18),
                onPressed: Desktop.I.toggleMini,
              ),
            ]),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final o in items)
                  OccurrenceTile(
                    occ: o,
                    dense: true,
                    onTap: () {},
                    onToggle: (v) => Store.I.setDone(o.task.id, o.day, v),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 正常界面 ----------
  Widget _buildFull(BuildContext context) {
    final sync = SyncService.I;
    final s = Store.I.settings;
    return Scaffold(
      appBar: AppBar(
        title: const Text('今日事'),
        actions: [
          if (s.syncConfigured)
            IconButton(
              tooltip: s.lastSyncMsg.isEmpty ? '同步' : s.lastSyncMsg,
              onPressed: sync.busy ? null : sync.syncNow,
              icon: sync.busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(s.lastSyncMsg.startsWith('同步失败') ? Icons.cloud_off : Icons.cloud_done_outlined),
            ),
          if (Platform.isWindows)
            IconButton(tooltip: '小窗置顶', onPressed: Desktop.I.toggleMini, icon: const Icon(Icons.picture_in_picture_alt_outlined)),
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
        ],
      ),
      body: _tab == 0 ? _buildToday(context) : _buildAll(context),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        tooltip: '新建事项',
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: '今天'),
          NavigationDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt), label: '全部事项'),
        ],
      ),
    );
  }

  Widget _categoryChips() {
    final cats = Store.I.categories;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: const Text('全部'),
              selected: _category == null,
              onSelected: (_) => setState(() => _category = null),
            ),
          ),
          for (final c in cats)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(c),
                selected: _category == c,
                onSelected: (_) => setState(() => _category = _category == c ? null : c),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToday(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    var items = Store.I.occurrencesFor(_day, includeOverdue: _isToday);
    if (_category != null) items = items.where((o) => o.task.category == _category).toList();
    final done = items.where((o) => o.done).length;
    final overdue = items.where((o) => o.overdue).toList();
    final pending = items.where((o) => !o.done && !o.overdue).toList();
    final finished = items.where((o) => o.done).toList();

    Widget section(String title, List<Occurrence> list) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('$title（${list.length}）',
                  style: TextStyle(fontSize: 13, color: cs.outline, fontWeight: FontWeight.w600)),
            ),
            for (final o in list)
              OccurrenceTile(
                occ: o,
                onTap: () => _openEditor(o.task),
                onToggle: (v) => Store.I.setDone(o.task.id, o.day, v),
              ),
          ],
        );

    return Column(
      children: [
        // 日期栏
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() => _day = _day.subtract(const Duration(days: 1))),
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _day,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setState(() => _day = dateOnly(d));
                  },
                  child: Column(
                    children: [
                      Text(
                        _isToday ? '今天 · ${dayTitle(_day)}' : dayTitle(_day),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      Text(Holidays.I.describe(_day), style: TextStyle(fontSize: 12, color: cs.outline)),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(() => _day = _day.add(const Duration(days: 1))),
              ),
            ],
          ),
        ),
        if (!_isToday)
          TextButton(onPressed: () => setState(() => _day = dateOnly(DateTime.now())), child: const Text('回到今天')),
        _categoryChips(),
        if (items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: items.isEmpty ? 0 : done / items.length, minHeight: 6),
                ),
              ),
              const SizedBox(width: 10),
              Text('$done / ${items.length}', style: TextStyle(color: cs.outline)),
            ]),
          ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.wb_sunny_outlined, size: 48, color: cs.outlineVariant),
                    const SizedBox(height: 8),
                    Text('这一天没有安排', style: TextStyle(color: cs.outline)),
                    TextButton(onPressed: () => _openEditor(), child: const Text('添加一件事')),
                  ]),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    if (overdue.isNotEmpty) section('逾期未完成', overdue),
                    if (pending.isNotEmpty) section('待完成', pending),
                    if (finished.isNotEmpty) section('已完成', finished),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildAll(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    var all = Store.I.tasks;
    if (_category != null) all = all.where((t) => t.category == _category).toList();
    final habits = all.where((t) => t.isRepeating).toList()
      ..sort((a, b) => (a.minuteOfDay ?? 9999).compareTo(b.minuteOfDay ?? 9999));
    final today = dayKey(DateTime.now());
    final todos = all.where((t) => !t.isRepeating).toList()..sort((a, b) => a.date.compareTo(b.date));
    final upcoming = todos.where((t) => !Store.I.isDone(t.id, t.date)).toList();
    final doneTodos = todos.where((t) => Store.I.isDone(t.id, t.date)).toList().reversed.take(30).toList();

    Widget header(String s) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(s, style: TextStyle(fontSize: 13, color: cs.outline, fontWeight: FontWeight.w600)),
        );

    Widget tile(Task t, {String? trailing}) => ListTile(
          leading: Container(
            width: 4,
            height: 32,
            decoration: BoxDecoration(color: priorityColor(context, t.priority), borderRadius: BorderRadius.circular(2)),
          ),
          minLeadingWidth: 4,
          title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [t.timeText.isEmpty ? '全天' : t.timeText, t.category, t.repeatText].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: trailing == null ? null : Text(trailing, style: TextStyle(color: cs.primary, fontSize: 12)),
          onTap: () => _openEditor(t),
        );

    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        _categoryChips(),
        if (all.isEmpty)
          Padding(
            padding: const EdgeInsets.all(48),
            child: Center(child: Text('还没有事项，点右下角 + 添加', style: TextStyle(color: cs.outline))),
          ),
        if (habits.isNotEmpty) header('重复事项 / 习惯（${habits.length}）'),
        for (final t in habits)
          tile(t, trailing: () {
            final n = Store.I.streak(t);
            return n > 0 ? '连续 $n 次' : null;
          }()),
        if (upcoming.isNotEmpty) header('待办（${upcoming.length}）'),
        for (final t in upcoming) tile(t, trailing: t.date.compareTo(today) < 0 ? '逾期' : null),
        if (doneTodos.isNotEmpty) header('最近完成的待办'),
        for (final t in doneTodos) tile(t, trailing: '✓'),
      ],
    );
  }
}
