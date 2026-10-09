import 'package:flutter/material.dart';

import '../models/task.dart';

Color priorityColor(BuildContext context, int p) {
  final cs = Theme.of(context).colorScheme;
  return switch (p) {
    2 => const Color(0xFFE76F51),
    1 => cs.primary,
    _ => cs.outlineVariant,
  };
}

/// 清单中的一行：左侧优先级色条，勾选框，标题与时间/分类。
class OccurrenceTile extends StatelessWidget {
  final Occurrence occ;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;
  final bool dense;

  const OccurrenceTile({
    super.key,
    required this.occ,
    required this.onToggle,
    required this.onTap,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = occ.task;
    final cs = Theme.of(context).colorScheme;
    final muted = occ.done;
    final now = DateTime.now();
    final late = !occ.done && occ.dueTime != null && occ.dueTime!.isBefore(now);

    final meta = <String>[
      if (occ.overdue) '原定 ${occ.day}',
      t.timeText.isEmpty ? '全天' : t.timeText,
      t.category,
      if (t.isRepeating) t.repeatText,
    ];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 2 : 6),
          child: Row(
            children: [
              Container(
                width: 4,
                height: dense ? 28 : 40,
                decoration: BoxDecoration(
                  color: muted ? cs.outlineVariant : priorityColor(context, t.priority),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Checkbox(
                value: occ.done,
                onChanged: (v) => onToggle(v ?? false),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: dense ? 14 : 16,
                        fontWeight: t.priority == 2 && !muted ? FontWeight.w600 : FontWeight.normal,
                        decoration: muted ? TextDecoration.lineThrough : null,
                        color: muted ? cs.outline : null,
                      ),
                    ),
                    if (!dense)
                      Text(
                        meta.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: occ.overdue || late ? const Color(0xFFE76F51) : cs.outline,
                        ),
                      ),
                  ],
                ),
              ),
              if (dense && t.timeText.isNotEmpty)
                Text(t.timeText, style: TextStyle(fontSize: 12, color: cs.outline)),
              if (!dense && t.remind && t.minuteOfDay != null && !muted)
                Icon(Icons.notifications_active_outlined, size: 16, color: cs.outline),
            ],
          ),
        ),
      ),
    );
  }
}
