import 'dart:io';

import 'package:flutter/material.dart';

import '../models/task.dart';
import '../services/desktop.dart';
import '../services/reminders.dart';
import '../services/store.dart';
import 'task_tile.dart';

/// 依次弹出提醒，避免多个对话框叠在一起。
class PopupQueue {
  final BuildContext Function() contextOf;
  final List<PopupRequest> _queue = [];
  bool _showing = false;

  PopupQueue(this.contextOf);

  void add(PopupRequest r) {
    // 同一个事项不要重复排队
    if (!r.isSummary &&
        _queue.any((q) =>
            !q.isSummary &&
            q.items.first.task.id == r.items.first.task.id &&
            q.items.first.day == r.items.first.day)) {
      return;
    }
    if (r.isSummary) _queue.removeWhere((q) => q.isSummary);
    _queue.add(r);
    _next();
  }

  Future<void> _next() async {
    if (_showing || _queue.isEmpty) return;
    _showing = true;
    final r = _queue.removeAt(0);
    if (Platform.isWindows) await Desktop.I.popToFront();
    final ctx = contextOf();
    if (ctx.mounted) {
      await showDialog<void>(
        context: ctx,
        barrierDismissible: false,
        builder: (_) => r.isSummary ? SummaryDialog(items: r.items) : ReminderDialog(occ: r.items.first),
      );
    }
    if (Platform.isWindows && _queue.isEmpty) await Desktop.I.releaseTop();
    _showing = false;
    _next();
  }
}

class ReminderDialog extends StatelessWidget {
  final Occurrence occ;
  const ReminderDialog({super.key, required this.occ});

  @override
  Widget build(BuildContext context) {
    final t = occ.task;
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(Icons.alarm, size: 40, color: priorityColor(context, t.priority)),
      title: Text(t.title, textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            [t.timeText, t.category, '优先级${priorityLabels[t.priority]}'].where((e) => e.isNotEmpty).join(' · '),
            style: TextStyle(color: cs.outline),
          ),
          if (t.note.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(t.note),
          ],
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () {
            Reminders.I.snooze(occ, const Duration(minutes: 10));
            Navigator.pop(context);
          },
          child: const Text('10 分钟后'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
        FilledButton.icon(
          onPressed: () {
            Store.I.setDone(t.id, occ.day, true);
            Navigator.pop(context);
          },
          icon: const Icon(Icons.check),
          label: const Text('完成'),
        ),
      ],
    );
  }
}

class SummaryDialog extends StatefulWidget {
  final List<Occurrence> items;
  const SummaryDialog({super.key, required this.items});

  @override
  State<SummaryDialog> createState() => _SummaryDialogState();
}

class _SummaryDialogState extends State<SummaryDialog> {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final items = Store.I.occurrencesFor(now, includeOverdue: true);
    return AlertDialog(
      title: Text('早上好 · ${dayTitle(now)}'),
      content: SizedBox(
        width: 380,
        child: items.isEmpty
            ? const Text('今天没有安排，放松一下。')
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final o in items)
                    OccurrenceTile(
                      occ: o,
                      dense: true,
                      onTap: () {},
                      onToggle: (v) => setState(() => Store.I.setDone(o.task.id, o.day, v)),
                    ),
                ],
              ),
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('开始今天')),
      ],
    );
  }
}
