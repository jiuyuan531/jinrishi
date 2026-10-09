import 'package:flutter/material.dart';

import '../models/task.dart';
import '../services/store.dart';

class EditPage extends StatefulWidget {
  final Task task;
  final bool isNew;
  const EditPage({super.key, required this.task, required this.isNew});

  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  late final Task t = widget.task;
  late final _title = TextEditingController(text: t.title);
  late final _note = TextEditingController(text: t.note);

  static const _weekNames = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    String? err;
    if (title.isEmpty) err = '请填写事项内容';
    if (t.repeat == RepeatType.weekly && t.weekdays.isEmpty) err = '请选择每周哪几天';
    if (t.repeat == RepeatType.monthly && t.monthDays.isEmpty) err = '请选择每月哪几号';
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    t.title = title;
    t.note = _note.text.trim();
    t.kind = t.isRepeating ? TaskKind.habit : TaskKind.todo;
    Store.I.upsertTask(t);
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除这个事项？'),
        content: Text(t.isRepeating ? '删除后不会再提醒，以往的完成记录也不再显示。' : '删除后不会再提醒。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      Store.I.deleteTask(t.id);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _pickTime() async {
    final m = t.minuteOfDay ?? 9 * 60;
    final r = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (r != null) setState(() => t.minuteOfDay = r.hour * 60 + r.minute);
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: parseDay(t.date),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => t.date = dayKey(d));
  }

  Future<void> _addCategory() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新分类'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: '例如：项目A、家务')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('添加')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      if (!Store.I.categories.contains(name)) {
        Store.I.setCategories([...Store.I.categories, name]);
      }
      setState(() => t.category = name);
    }
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
        child: Text(s, style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? '新建事项' : '编辑事项'),
        actions: [
          if (!widget.isNew)
            IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline), tooltip: '删除'),
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          TextField(
            controller: _title,
            autofocus: widget.isNew,
            style: const TextStyle(fontSize: 18),
            decoration: const InputDecoration(hintText: '要做什么？', border: OutlineInputBorder()),
            textInputAction: TextInputAction.done,
          ),

          _label('重复'),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final r in RepeatType.values)
              ChoiceChip(
                label: Text(repeatLabel(r)),
                selected: t.repeat == r,
                onSelected: (_) => setState(() {
                  t.repeat = r;
                  if (r == RepeatType.weekly && t.weekdays.isEmpty) t.weekdays = [parseDay(t.date).weekday];
                  if (r == RepeatType.monthly && t.monthDays.isEmpty) t.monthDays = [parseDay(t.date).day];
                }),
              ),
          ]),
          if (t.repeat == RepeatType.workday)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('按国家法定安排：节假日不提醒，调休上班的周末会提醒。', style: TextStyle(fontSize: 12, color: cs.outline)),
            ),
          if (t.repeat == RepeatType.weekly) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              for (var i = 1; i <= 7; i++)
                FilterChip(
                  label: Text('周${_weekNames[i - 1]}'),
                  selected: t.weekdays.contains(i),
                  onSelected: (v) => setState(() => v ? t.weekdays.add(i) : t.weekdays.remove(i)),
                ),
            ]),
          ],
          if (t.repeat == RepeatType.monthly) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (var i = 1; i <= 31; i++)
                SizedBox(
                  width: 44,
                  child: FilterChip(
                    showCheckmark: false,
                    padding: EdgeInsets.zero,
                    label: SizedBox(width: 20, child: Text('$i', textAlign: TextAlign.center)),
                    selected: t.monthDays.contains(i),
                    onSelected: (v) => setState(() => v ? t.monthDays.add(i) : t.monthDays.remove(i)),
                  ),
                ),
            ]),
            Text('选 29~31 号时，当月没有这一天则在月末提醒。', style: TextStyle(fontSize: 12, color: cs.outline)),
          ],
          if (t.repeat == RepeatType.daily || t.repeat == RepeatType.weekly || t.repeat == RepeatType.monthly)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('法定节假日跳过'),
              subtitle: const Text('春节、国庆等放假期间不提醒'),
              value: t.skipHolidays,
              onChanged: (v) => setState(() => t.skipHolidays = v),
            ),

          _label('时间'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(t.isRepeating ? '从 ${t.date} 开始' : t.date),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickDate,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: Text(t.minuteOfDay == null ? '全天（不定时）' : t.timeText),
            trailing: t.minuteOfDay == null
                ? const Icon(Icons.chevron_right)
                : IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '改为全天',
                    onPressed: () => setState(() => t.minuteOfDay = null),
                  ),
            onTap: _pickTime,
          ),
          if (t.minuteOfDay != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.notifications_active_outlined),
              title: const Text('到点弹窗提醒'),
              value: t.remind,
              onChanged: (v) => setState(() => t.remind = v),
            ),

          _label('分类'),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final c in Store.I.categories)
              ChoiceChip(label: Text(c), selected: t.category == c, onSelected: (_) => setState(() => t.category = c)),
            ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('新分类'), onPressed: _addCategory),
          ]),

          _label('优先级'),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('低')),
              ButtonSegment(value: 1, label: Text('中')),
              ButtonSegment(value: 2, label: Text('高')),
            ],
            selected: {t.priority},
            onSelectionChanged: (s) => setState(() => t.priority = s.first),
          ),

          _label('备注'),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: const InputDecoration(hintText: '可选', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Padding(padding: EdgeInsets.all(12), child: Text('保存'))),
        ],
      ),
    );
  }
}
