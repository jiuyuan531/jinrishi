import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/task.dart';
import 'schedule_rules.dart';

/// 只保存在本机的设置（坚果云密码不会上传）。
class Settings {
  int summaryMinute = 8 * 60;
  bool summaryEnabled = true;
  String davUser = '';
  String davPass = '';
  int lastSyncAt = 0;
  String lastSyncMsg = '';
  bool startHidden = true;
  bool guideShown = false;

  Map<String, dynamic> toJson() => {
        'summaryMinute': summaryMinute,
        'summaryEnabled': summaryEnabled,
        'davUser': davUser,
        'davPass': davPass,
        'lastSyncAt': lastSyncAt,
        'lastSyncMsg': lastSyncMsg,
        'startHidden': startHidden,
        'guideShown': guideShown,
      };

  void load(Map<String, dynamic> j) {
    summaryMinute = (j['summaryMinute'] ?? summaryMinute) as int;
    summaryEnabled = (j['summaryEnabled'] ?? true) as bool;
    davUser = (j['davUser'] ?? '') as String;
    davPass = (j['davPass'] ?? '') as String;
    lastSyncAt = (j['lastSyncAt'] ?? 0) as int;
    lastSyncMsg = (j['lastSyncMsg'] ?? '') as String;
    startHidden = (j['startHidden'] ?? true) as bool;
    guideShown = (j['guideShown'] ?? false) as bool;
  }

  bool get syncConfigured => davUser.isNotEmpty && davPass.isNotEmpty;
}

/// 所有事项与完成记录。数据保存在本地 data.json，并通过坚果云同步。
class Store extends ChangeNotifier {
  Store._();
  static final Store I = Store._();

  late Directory dir;
  final Map<String, Task> _tasks = {};
  final Map<String, Completion> _completions = {};
  List<String> categories = ['工作', '生活', '学习', '健康'];
  int categoriesUpdatedAt = 0;
  final Settings settings = Settings();

  /// 本地数据发生变化（不含同步合并）时触发，用于安排上传。
  void Function()? onLocalChange;

  File get _dataFile => File('${dir.path}/data.json');
  File get _settingsFile => File('${dir.path}/settings.json');
  File get actionsFile => File('${dir.path}/pending_actions.jsonl');

  Future<void> init(Directory dataDir) async {
    dir = dataDir;
    try {
      if (await _settingsFile.exists()) {
        settings.load(jsonDecode(await _settingsFile.readAsString()));
      }
    } catch (_) {}
    try {
      if (await _dataFile.exists()) {
        _loadDoc(jsonDecode(await _dataFile.readAsString()) as Map<String, dynamic>);
      }
    } catch (e) {
      // 数据文件损坏时保留一份备份，避免被覆盖
      try {
        await _dataFile.copy('${dir.path}/data.broken.${nowMs()}.json');
      } catch (_) {}
    }
    await applyPendingActions(save: true);
  }

  void _loadDoc(Map<String, dynamic> doc) {
    _tasks.clear();
    _completions.clear();
    for (final t in (doc['tasks'] ?? []) as List) {
      final task = Task.fromJson(t as Map<String, dynamic>);
      _tasks[task.id] = task;
    }
    ((doc['completions'] ?? {}) as Map<String, dynamic>).forEach((k, v) {
      _completions[k] = Completion.fromJson(v as Map<String, dynamic>);
    });
    final cats = doc['categories'];
    if (cats is Map) {
      categories = ((cats['list'] ?? categories) as List).cast<String>();
      categoriesUpdatedAt = (cats['updatedAt'] ?? 0) as int;
    }
  }

  Map<String, dynamic> exportDoc() => {
        'version': 1,
        'tasks': _tasks.values.map((t) => t.toJson()).toList(),
        'completions': _completions.map((k, v) => MapEntry(k, v.toJson())),
        'categories': {'list': categories, 'updatedAt': categoriesUpdatedAt},
      };

  Timer? _saveTimer;
  Future<void> save() async {
    _saveTimer?.cancel();
    final tmp = File('${_dataFile.path}.tmp');
    await tmp.writeAsString(jsonEncode(exportDoc()));
    await tmp.rename(_dataFile.path);
  }

  Future<void> saveSettings() async {
    await _settingsFile.writeAsString(jsonEncode(settings.toJson()));
  }

  void _changed() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), save);
    notifyListeners();
    onLocalChange?.call();
  }

  // ---------- 查询 ----------

  List<Task> get tasks =>
      _tasks.values.where((t) => !t.deleted).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  Task? task(String id) {
    final t = _tasks[id];
    return (t == null || t.deleted) ? null : t;
  }

  bool isDone(String taskId, String day) =>
      _completions[completionKey(taskId, day)]?.done ?? false;

  /// 某天的清单；当天为今天时，额外带上过去没完成的待办。
  List<Occurrence> occurrencesFor(DateTime day, {bool includeOverdue = false}) {
    final key = dayKey(day);
    final list = <Occurrence>[];
    for (final t in tasks) {
      if (occursOn(t, day)) {
        list.add(Occurrence(t, key, isDone(t.id, key)));
      } else if (includeOverdue &&
          t.repeat == RepeatType.none &&
          parseDay(t.date).isBefore(dateOnly(day)) &&
          !isDone(t.id, t.date)) {
        list.add(Occurrence(t, t.date, false, overdue: true));
      }
    }
    list.sort(compareOccurrences);
    return list;
  }

  /// 连续完成天数（习惯打卡用，最多回看 365 天）
  int streak(Task t) {
    var d = dateOnly(DateTime.now());
    if (occursOn(t, d) && !isDone(t.id, dayKey(d))) {
      d = d.subtract(const Duration(days: 1));
    }
    var n = 0;
    for (var i = 0; i < 365; i++) {
      if (d.isBefore(parseDay(t.date))) break;
      if (occursOn(t, d)) {
        if (!isDone(t.id, dayKey(d))) break;
        n++;
      }
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  // ---------- 修改 ----------

  void upsertTask(Task t) {
    t.updatedAt = nowMs();
    _tasks[t.id] = t;
    if (!categories.contains(t.category) && t.category.isNotEmpty) {
      categories = [...categories, t.category];
      categoriesUpdatedAt = nowMs();
    }
    _changed();
  }

  void deleteTask(String id) {
    final t = _tasks[id];
    if (t == null) return;
    t.deleted = true;
    t.updatedAt = nowMs();
    _changed();
  }

  void setDone(String taskId, String day, bool done) {
    _completions[completionKey(taskId, day)] = Completion(done, nowMs());
    _changed();
  }

  void setCategories(List<String> list) {
    categories = list;
    categoriesUpdatedAt = nowMs();
    _changed();
  }

  /// 处理通知栏里点“完成”留下的记录（通知回调运行在后台，不能直接改内存数据）。
  Future<bool> applyPendingActions({bool save = false}) async {
    final f = actionsFile;
    if (!await f.exists()) return false;
    var any = false;
    try {
      final lines = await f.readAsLines();
      await f.delete();
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final j = jsonDecode(line) as Map<String, dynamic>;
        if (j['type'] == 'done') {
          final key = j['key'] as String;
          final at = (j['at'] ?? nowMs()) as int;
          final cur = _completions[key];
          if (cur == null || cur.updatedAt < at) {
            _completions[key] = Completion(true, at);
            any = true;
          }
        }
      }
    } catch (_) {}
    if (any) {
      if (save) {
        await this.save();
        notifyListeners();
        onLocalChange?.call();
      } else {
        _changed();
      }
    }
    return any;
  }

  /// 与云端数据合并：同一条记录取更新时间较新的一份。返回本地是否有变化。
  bool mergeRemote(Map<String, dynamic> remote) {
    var changed = false;
    for (final raw in (remote['tasks'] ?? []) as List) {
      final r = Task.fromJson(raw as Map<String, dynamic>);
      final l = _tasks[r.id];
      if (l == null || l.updatedAt < r.updatedAt) {
        _tasks[r.id] = r;
        changed = true;
      }
    }
    ((remote['completions'] ?? {}) as Map<String, dynamic>).forEach((k, v) {
      final r = Completion.fromJson(v as Map<String, dynamic>);
      final l = _completions[k];
      if (l == null || l.updatedAt < r.updatedAt) {
        _completions[k] = r;
        changed = true;
      }
    });
    final cats = remote['categories'];
    if (cats is Map && ((cats['updatedAt'] ?? 0) as int) > categoriesUpdatedAt) {
      categories = ((cats['list'] ?? categories) as List).cast<String>();
      categoriesUpdatedAt = cats['updatedAt'] as int;
      changed = true;
    }
    // 清理 120 天前的完成记录和已删除事项，控制同步文件大小
    final cutoff = dayKey(DateTime.now().subtract(const Duration(days: 120)));
    _completions.removeWhere((k, _) => k.split('@').last.compareTo(cutoff) < 0);
    final tombCutoff = nowMs() - 60 * 24 * 3600 * 1000;
    _tasks.removeWhere((_, t) => t.deleted && t.updatedAt < tombCutoff);
    if (changed) {
      save();
      notifyListeners();
    }
    return changed;
  }
}
