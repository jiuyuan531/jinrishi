import 'dart:io';

import 'package:flutter/services.dart';

import '../models/task.dart';
import 'reminders.dart';
import 'store.dart';

/// 安卓桌面小组件：把今日清单写成文字交给原生小组件显示。
class WidgetSync {
  static const _channel = MethodChannel('jinrishi/widget');

  static Future<void> update() async {
    if (!Platform.isAndroid) return;
    try {
      final now = DateTime.now();
      final items = Store.I.occurrencesFor(now, includeOverdue: true);
      final left = items.where((o) => !o.done).length;
      final lines = items.take(12).map((o) {
        final mark = o.done ? '✓' : '○';
        final time = o.task.timeText.isEmpty ? '全天' : o.task.timeText;
        final flag = o.overdue ? '[逾期]' : (o.task.priority == 2 ? '!' : '');
        return '$mark $time  $flag${o.task.title}';
      }).join('\n');
      await _channel.invokeMethod('update', {
        'title': '${dayTitle(now)} · 剩 $left 项',
        'body': lines.isEmpty ? '今天没有安排' : lines,
        'updated': dayKey(now),
      });
    } catch (_) {}
  }
}
