import 'dart:math';

/// 事项类型：习惯（按规则重复）或待办（某天要做的一次性事情）。
enum TaskKind { habit, todo }

/// 重复方式。
enum RepeatType { none, daily, workday, weekly, monthly }

String repeatLabel(RepeatType t) => switch (t) {
      RepeatType.none => '不重复',
      RepeatType.daily => '每天',
      RepeatType.workday => '工作日',
      RepeatType.weekly => '每周',
      RepeatType.monthly => '每月',
    };

const priorityLabels = ['低', '中', '高'];

String newId() {
  final r = Random.secure();
  final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final rnd = List.generate(6, (_) => r.nextInt(36).toRadixString(36)).join();
  return '$ts$rnd';
}

int nowMs() => DateTime.now().millisecondsSinceEpoch;

/// 日期键 yyyy-MM-dd
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDay(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

class Task {
  String id;
  String title;
  String note;
  TaskKind kind;
  String category;

  /// 0 低 / 1 中 / 2 高
  int priority;

  /// 提醒时间（分钟数，0~1439），null 表示不定时（只出现在清单里，不弹窗）
  int? minuteOfDay;

  /// 待办的日期 yyyy-MM-dd；习惯为开始日期
  String date;

  RepeatType repeat;

  /// 每周几（1=周一 … 7=周日）
  List<int> weekdays;

  /// 每月几号（1~31；超过当月天数时取月末）
  List<int> monthDays;

  /// 遇到法定节假日跳过（工作日规则天然跳过）
  bool skipHolidays;

  bool remind;

  int createdAt;
  int updatedAt;
  bool deleted;

  Task({
    required this.id,
    required this.title,
    this.note = '',
    this.kind = TaskKind.todo,
    this.category = '工作',
    this.priority = 1,
    this.minuteOfDay,
    required this.date,
    this.repeat = RepeatType.none,
    List<int>? weekdays,
    List<int>? monthDays,
    this.skipHolidays = false,
    this.remind = true,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
  })  : weekdays = weekdays ?? [],
        monthDays = monthDays ?? [];

  factory Task.blank() {
    final now = nowMs();
    return Task(
      id: newId(),
      title: '',
      date: dayKey(DateTime.now()),
      createdAt: now,
      updatedAt: now,
    );
  }

  bool get isRepeating => repeat != RepeatType.none;

  String get timeText {
    final m = minuteOfDay;
    if (m == null) return '';
    return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  }

  String get repeatText {
    switch (repeat) {
      case RepeatType.none:
        return date;
      case RepeatType.daily:
        return skipHolidays ? '每天（节假日跳过）' : '每天';
      case RepeatType.workday:
        return '工作日（含调休上班）';
      case RepeatType.weekly:
        const names = ['一', '二', '三', '四', '五', '六', '日'];
        final w = [...weekdays]..sort();
        return '每周${w.map((e) => names[e - 1]).join('、')}${skipHolidays ? '（节假日跳过）' : ''}';
      case RepeatType.monthly:
        final m = [...monthDays]..sort();
        return '每月${m.map((e) => '$e号').join('、')}${skipHolidays ? '（节假日跳过）' : ''}';
    }
  }

  Task copy() => Task.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'kind': kind.name,
        'category': category,
        'priority': priority,
        'minute': minuteOfDay,
        'date': date,
        'repeat': repeat.name,
        'weekdays': weekdays,
        'monthDays': monthDays,
        'skipHolidays': skipHolidays,
        'remind': remind,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'deleted': deleted,
      };

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id'] as String,
        title: (j['title'] ?? '') as String,
        note: (j['note'] ?? '') as String,
        kind: TaskKind.values.firstWhere((e) => e.name == j['kind'],
            orElse: () => TaskKind.todo),
        category: (j['category'] ?? '工作') as String,
        priority: (j['priority'] ?? 1) as int,
        minuteOfDay: j['minute'] as int?,
        date: (j['date'] ?? dayKey(DateTime.now())) as String,
        repeat: RepeatType.values.firstWhere((e) => e.name == j['repeat'],
            orElse: () => RepeatType.none),
        weekdays: List<int>.from((j['weekdays'] ?? []) as List),
        monthDays: List<int>.from((j['monthDays'] ?? []) as List),
        skipHolidays: (j['skipHolidays'] ?? false) as bool,
        remind: (j['remind'] ?? true) as bool,
        createdAt: (j['createdAt'] ?? 0) as int,
        updatedAt: (j['updatedAt'] ?? 0) as int,
        deleted: (j['deleted'] ?? false) as bool,
      );
}

/// 某个事项在某一天的完成记录，键为 "任务id@日期"。
class Completion {
  bool done;
  int updatedAt;
  Completion(this.done, this.updatedAt);

  Map<String, dynamic> toJson() => {'done': done, 'updatedAt': updatedAt};
  factory Completion.fromJson(Map<String, dynamic> j) =>
      Completion((j['done'] ?? false) as bool, (j['updatedAt'] ?? 0) as int);
}

String completionKey(String taskId, String day) => '$taskId@$day';

/// 今日清单中的一行：某个事项在某天的一次出现。
class Occurrence {
  final Task task;
  final String day;
  final bool done;
  final bool overdue;
  Occurrence(this.task, this.day, this.done, {this.overdue = false});

  DateTime? get dueTime {
    final m = task.minuteOfDay;
    if (m == null) return null;
    final d = parseDay(day);
    return DateTime(d.year, d.month, d.day, m ~/ 60, m % 60);
  }
}
