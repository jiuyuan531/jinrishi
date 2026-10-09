import '../models/task.dart';
import 'holidays.dart';

/// 判断某个事项在某天是否需要做。
bool occursOn(Task t, DateTime day) {
  if (t.deleted) return false;
  final d = dateOnly(day);
  final start = parseDay(t.date);
  final h = Holidays.I;

  switch (t.repeat) {
    case RepeatType.none:
      return d == start;
    case RepeatType.daily:
      if (d.isBefore(start)) return false;
      return !(t.skipHolidays && h.isHoliday(d));
    case RepeatType.workday:
      if (d.isBefore(start)) return false;
      return h.isWorkday(d);
    case RepeatType.weekly:
      if (d.isBefore(start)) return false;
      if (!t.weekdays.contains(d.weekday)) return false;
      return !(t.skipHolidays && h.isHoliday(d));
    case RepeatType.monthly:
      if (d.isBefore(start)) return false;
      final lastDay = DateTime(d.year, d.month + 1, 0).day;
      final hit = t.monthDays.contains(d.day) ||
          (d.day == lastDay && t.monthDays.any((m) => m > lastDay));
      if (!hit) return false;
      return !(t.skipHolidays && h.isHoliday(d));
  }
}

int compareOccurrences(Occurrence a, Occurrence b) {
  if (a.done != b.done) return a.done ? 1 : -1;
  if (a.overdue != b.overdue) return a.overdue ? -1 : 1;
  final ma = a.task.minuteOfDay ?? 24 * 60;
  final mb = b.task.minuteOfDay ?? 24 * 60;
  if (ma != mb) return ma.compareTo(mb);
  if (a.task.priority != b.task.priority) {
    return b.task.priority.compareTo(a.task.priority);
  }
  return a.task.createdAt.compareTo(b.task.createdAt);
}
