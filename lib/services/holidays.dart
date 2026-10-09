import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../models/task.dart';

/// 中国法定节假日与调休数据。
/// 内置数据来自 NateScarlet/holiday-cn，联网时自动补充新年份。
class Holidays {
  Holidays._();
  static final Holidays I = Holidays._();

  /// 日期 -> (是否放假, 节日名)
  final Map<String, (bool, String)> _days = {};
  final Set<int> _years = {};
  late File _cacheFile;

  Future<void> init(Directory dataDir) async {
    _cacheFile = File('${dataDir.path}/holidays_cache.json');
    try {
      final builtin = jsonDecode(await rootBundle.loadString('assets/holidays.json'))
          as Map<String, dynamic>;
      _absorb(builtin);
    } catch (_) {}
    try {
      if (await _cacheFile.exists()) {
        _absorb(jsonDecode(await _cacheFile.readAsString()) as Map<String, dynamic>);
      }
    } catch (_) {}
  }

  void _absorb(Map<String, dynamic> data) {
    data.forEach((year, list) {
      final items = list as List;
      if (items.isEmpty) return;
      _years.add(int.parse(year));
      for (final e in items) {
        final m = e as Map<String, dynamic>;
        _days[m['d'] as String] = (m['off'] as bool, (m['n'] ?? '') as String);
      }
    });
  }

  bool hasYear(int y) => _years.contains(y);

  /// 联网获取今年和明年的数据（明年的安排一般在 11 月前后公布）。
  /// 返回本次新增的年份。
  Future<List<int>> refresh() async {
    final now = DateTime.now();
    final added = <int>[];
    Map<String, dynamic> cache = {};
    try {
      if (await _cacheFile.exists()) {
        cache = jsonDecode(await _cacheFile.readAsString()) as Map<String, dynamic>;
      }
    } catch (_) {}
    for (final y in [now.year, now.year + 1]) {
      if (_years.contains(y)) continue;
      for (final url in [
        'https://fastly.jsdelivr.net/gh/NateScarlet/holiday-cn@master/$y.json',
        'https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master/$y.json',
        'https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/$y.json',
      ]) {
        try {
          final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
          if (r.statusCode != 200) continue;
          final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
          final days = (j['days'] as List)
              .map((e) => {
                    'd': e['date'],
                    'off': e['isOffDay'],
                    'n': e['name'],
                  })
              .toList();
          if (days.isEmpty) break; // 当年尚未公布
          cache['$y'] = days;
          _absorb({'$y': days});
          added.add(y);
          break;
        } catch (_) {}
      }
    }
    if (added.isNotEmpty) {
      try {
        await _cacheFile.writeAsString(jsonEncode(cache));
      } catch (_) {}
    }
    return added;
  }

  /// 是否法定放假日
  bool isHoliday(DateTime d) => _days[dayKey(d)]?.$1 == true;

  /// 是否调休上班日（周末但要上班）
  bool isMakeupWorkday(DateTime d) => _days[dayKey(d)]?.$1 == false;

  /// 是否工作日：考虑节假日与调休
  bool isWorkday(DateTime d) {
    final info = _days[dayKey(d)];
    if (info != null) return !info.$1;
    return d.weekday <= 5;
  }

  /// 给界面用的当天说明，例如“国庆节 · 放假”“调休上班”
  String describe(DateTime d) {
    final info = _days[dayKey(d)];
    if (info != null) {
      return info.$1 ? '${info.$2} · 放假' : '调休上班（${info.$2}）';
    }
    return d.weekday <= 5 ? '工作日' : '周末';
  }
}
