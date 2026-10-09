import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jinrishi/models/task.dart';
import 'package:jinrishi/services/holidays.dart';
import 'package:jinrishi/services/schedule_rules.dart';

Task make(RepeatType r, {List<int>? weekdays, List<int>? monthDays, bool skip = false, String start = '2026-01-01'}) =>
    Task(
      id: 't',
      title: 'x',
      date: start,
      repeat: r,
      weekdays: weekdays,
      monthDays: monthDays,
      skipHolidays: skip,
      createdAt: 0,
      updatedAt: 0,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Holidays.I.init(Directory.systemTemp.createTempSync('jrs'));
  });

  test('2026 国庆放假、调休上班', () {
    expect(Holidays.I.hasYear(2026), isTrue);
    expect(Holidays.I.isHoliday(DateTime(2026, 10, 1)), isTrue);
    expect(Holidays.I.isWorkday(DateTime(2026, 10, 2)), isFalse);
    expect(Holidays.I.isWorkday(DateTime(2026, 10, 12)), isTrue); // 普通周一
  });

  test('工作日规则跳过节假日、包含调休', () {
    final t = make(RepeatType.workday);
    expect(occursOn(t, DateTime(2026, 10, 1)), isFalse);
    expect(occursOn(t, DateTime(2026, 10, 10)), Holidays.I.isMakeupWorkday(DateTime(2026, 10, 10)));
    expect(occursOn(t, DateTime(2026, 10, 9)), isTrue); // 周五
    expect(occursOn(t, DateTime(2026, 10, 11)), Holidays.I.isMakeupWorkday(DateTime(2026, 10, 11)));
  });

  test('每天，可选跳过节假日', () {
    expect(occursOn(make(RepeatType.daily), DateTime(2026, 10, 1)), isTrue);
    expect(occursOn(make(RepeatType.daily, skip: true), DateTime(2026, 10, 1)), isFalse);
    expect(occursOn(make(RepeatType.daily, start: '2026-10-05'), DateTime(2026, 10, 4)), isFalse);
  });

  test('每周、每月（月末兜底）', () {
    final w = make(RepeatType.weekly, weekdays: [1, 3]);
    expect(occursOn(w, DateTime(2026, 10, 12)), isTrue); // 周一
    expect(occursOn(w, DateTime(2026, 10, 13)), isFalse);
    final m = make(RepeatType.monthly, monthDays: [31]);
    expect(occursOn(m, DateTime(2026, 11, 30)), isTrue);
    expect(occursOn(m, DateTime(2026, 12, 31)), isTrue);
    expect(occursOn(m, DateTime(2026, 12, 30)), isFalse);
  });

  test('一次性待办只在当天', () {
    final t = make(RepeatType.none, start: '2026-10-20');
    expect(occursOn(t, DateTime(2026, 10, 20)), isTrue);
    expect(occursOn(t, DateTime(2026, 10, 21)), isFalse);
  });

  test('复制事项不共享列表', () {
    final a = make(RepeatType.weekly, weekdays: [1]);
    final b = a.copy()..weekdays.add(2);
    expect(a.weekdays, [1]);
    expect(b.weekdays, [1, 2]);
  });
}
