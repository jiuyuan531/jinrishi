import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/task.dart';
import 'holidays.dart';
import 'store.dart';

const _weekNames = ['一', '二', '三', '四', '五', '六', '日'];
String dayTitle(DateTime d) => '${d.month}月${d.day}日 周${_weekNames[d.weekday - 1]}';

String summaryTitle(DateTime d) => '今日事 · ${dayTitle(d)} · ${Holidays.I.describe(d)}';

String summaryBody(List<Occurrence> items) {
  final todo = items.where((o) => !o.done).toList();
  if (todo.isEmpty) return '今天没有安排，放松一下。';
  return todo.map((o) {
    final t = o.task.timeText.isEmpty ? '全天' : o.task.timeText;
    final flag = o.overdue ? '【逾期】' : (o.task.priority == 2 ? '【重要】' : '');
    return '$t  $flag${o.task.title}';
  }).join('\n');
}

/// 通知栏“完成”按钮的回调。它在后台独立运行，只能写文件，主程序下次打开时再合并。
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse r) {
  if (r.actionId != 'done' || r.payload == null) return;
  try {
    final p = jsonDecode(r.payload!) as Map<String, dynamic>;
    File('${p['dir']}/pending_actions.jsonl').writeAsStringSync(
      '${jsonEncode({'type': 'done', 'key': p['key'], 'at': DateTime.now().millisecondsSinceEpoch})}\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {}
}

/// 弹窗请求：主界面监听后弹出对话框。
class PopupRequest {
  final bool isSummary;
  final List<Occurrence> items;
  PopupRequest.summary(this.items) : isSummary = true;
  PopupRequest.reminder(Occurrence o)
      : isSummary = false,
        items = [o];
}

class Reminders {
  Reminders._();
  static final Reminders I = Reminders._();

  final plugin = FlutterLocalNotificationsPlugin();
  final popups = StreamController<PopupRequest>.broadcast();

  /// 启动时若是点通知打开的，记住它的内容
  String? launchPayload;

  bool get isAndroid => Platform.isAndroid;
  bool get isWindows => Platform.isWindows;

  Timer? _ticker;
  DateTime _lastTick = DateTime.now();
  String _lastSummaryDay = '';

  static const _reminderChannel = AndroidNotificationDetails(
    'reminder_v1',
    '到点提醒',
    channelDescription: '事项到时间时弹出提醒',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.alarm,
    fullScreenIntent: true,
    visibility: NotificationVisibility.public,
    ticker: '今日事提醒',
    actions: [
      AndroidNotificationAction('done', '完成', cancelNotification: true),
      AndroidNotificationAction('open', '查看',
          showsUserInterface: true, cancelNotification: true),
    ],
  );

  Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    }

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      windows: WindowsInitializationSettings(
        appName: '今日事',
        appUserModelId: 'Shen.Jinrishi.App',
        guid: '6f1c2d4e-8b3a-4c5d-9e7f-1a2b3c4d5e6f',
      ),
    );
    await plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onForegroundResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    if (isAndroid) {
      final launch = await plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        final r = launch!.notificationResponse;
        if (r != null) {
          if (r.actionId == 'done') {
            notificationTapBackground(r);
          } else {
            launchPayload = r.payload;
          }
        }
      }
    }
    if (isWindows) _startTicker();
  }

  void _onForegroundResponse(NotificationResponse r) {
    if (r.actionId == 'done') {
      notificationTapBackground(r);
      Store.I.applyPendingActions();
      return;
    }
    handlePayload(r.payload);
  }

  /// 点通知打开应用后，按内容弹出对应窗口
  void handlePayload(String? payload) {
    if (payload == null) return;
    try {
      final p = jsonDecode(payload) as Map<String, dynamic>;
      if (p['summary'] == true) {
        popups.add(PopupRequest.summary(
            Store.I.occurrencesFor(DateTime.now(), includeOverdue: true)));
      } else {
        final key = p['key'] as String;
        final parts = key.split('@');
        final t = Store.I.task(parts[0]);
        if (t != null) {
          popups.add(PopupRequest.reminder(
              Occurrence(t, parts[1], Store.I.isDone(t.id, parts[1]))));
        }
      }
    } catch (_) {}
  }

  // ---------------- 权限（安卓） ----------------

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<void> requestAndroidPermissions() async {
    final a = _android;
    if (a == null) return;
    await a.requestNotificationsPermission();
    if (await a.canScheduleExactNotifications() != true) {
      await a.requestExactAlarmsPermission();
    }
    await a.requestFullScreenIntentPermission();
  }

  Future<Map<String, bool>> androidPermissionState() async {
    final a = _android;
    if (a == null) return {};
    return {
      'notify': await a.areNotificationsEnabled() ?? false,
      'exact': await a.canScheduleExactNotifications() ?? false,
    };
  }

  // ---------------- 安排提醒 ----------------

  Timer? _rescheduleTimer;
  void scheduleSoon() {
    _rescheduleTimer?.cancel();
    _rescheduleTimer = Timer(const Duration(seconds: 2), reschedule);
  }

  /// 安卓：提前排好未来 14 天的系统闹钟（打开应用、修改或同步后会重排）。
  Future<void> reschedule() async {
    if (!isAndroid) return;
    final store = Store.I;
    final a = _android;
    final exact = await a?.canScheduleExactNotifications() ?? false;
    final mode = exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    await plugin.cancelAll();
    final now = DateTime.now();
    var id = 1;
    const maxCount = 450; // 安卓单个应用最多约 500 个闹钟

    for (var i = 0; i < 14 && id < maxCount; i++) {
      final day = dateOnly(now).add(Duration(days: i));
      final occ = store.occurrencesFor(day, includeOverdue: i == 0);

      // 早报
      final s = store.settings;
      if (s.summaryEnabled) {
        final at = day.add(Duration(minutes: s.summaryMinute));
        if (at.isAfter(now)) {
          await _schedule(
            id++,
            summaryTitle(day),
            summaryBody(occ),
            at,
            NotificationDetails(
              android: AndroidNotificationDetails(
                'summary_v1',
                '每日清单',
                channelDescription: '每天早上推送当天要做的事',
                importance: Importance.high,
                priority: Priority.high,
                styleInformation: BigTextStyleInformation(summaryBody(occ)),
              ),
            ),
            jsonEncode({'summary': true}),
            mode,
          );
        }
      }

      for (final o in occ) {
        if (id >= maxCount) break;
        final due = o.dueTime;
        if (!o.task.remind || o.done || o.overdue || due == null || !due.isAfter(now)) {
          continue;
        }
        final body = [
          o.task.timeText,
          if (o.task.priority == 2) '重要',
          o.task.category,
          if (o.task.note.isNotEmpty) o.task.note,
        ].join(' · ');
        await _schedule(
          id++,
          o.task.title,
          body,
          due,
          const NotificationDetails(android: _reminderChannel),
          jsonEncode({'key': completionKey(o.task.id, o.day), 'dir': store.dir.path}),
          mode,
        );
      }
    }
    await _scheduleSnoozes(maxCount + 1, mode);
  }

  // ---------------- 稍后提醒 ----------------

  final List<(String key, DateTime at)> _snoozes = [];

  Future<void> snooze(Occurrence o, Duration d) async {
    final at = DateTime.now().add(d);
    final key = completionKey(o.task.id, o.day);
    _snoozes.add((key, at));
    if (isWindows) {
      Timer(d, () {
        final t = Store.I.task(o.task.id);
        if (t != null && !Store.I.isDone(t.id, o.day)) {
          popups.add(PopupRequest.reminder(Occurrence(t, o.day, false)));
          _toast(t.title, '稍后提醒');
        }
      });
    } else {
      await reschedule();
    }
  }

  Future<void> _scheduleSnoozes(int startId, AndroidScheduleMode mode) async {
    final now = DateTime.now();
    _snoozes.removeWhere((s) => !s.$2.isAfter(now));
    var id = startId;
    for (final (key, at) in _snoozes) {
      final parts = key.split('@');
      final t = Store.I.task(parts[0]);
      if (t == null || Store.I.isDone(t.id, parts[1])) continue;
      await _schedule(id++, t.title, '稍后提醒 · ${t.category}', at,
          const NotificationDetails(android: _reminderChannel),
          jsonEncode({'key': key, 'dir': Store.I.dir.path}), mode);
    }
  }

  Future<void> _schedule(int id, String title, String body, DateTime at,
      NotificationDetails details, String payload, AndroidScheduleMode mode) async {
    try {
      await plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(at, tz.local),
        details,
        androidScheduleMode: mode,
        payload: payload,
      );
    } catch (e) {
      debugPrint('schedule failed: $e');
    }
  }

  // ---------------- Windows：常驻后台，到点弹窗 ----------------

  void _startTicker() {
    _lastTick = DateTime.now().subtract(const Duration(minutes: 1));
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) => _tick());
    Timer(const Duration(seconds: 3), _tick);
  }

  void _tick() {
    final now = DateTime.now();
    final store = Store.I;
    final s = store.settings;
    final todayKey = dayKey(now);

    // 早报：到点后当天弹一次（开机晚于 8 点也会补弹）
    final summaryAt = dateOnly(now).add(Duration(minutes: s.summaryMinute));
    if (s.summaryEnabled && _lastSummaryDay != todayKey && !now.isBefore(summaryAt)) {
      _lastSummaryDay = todayKey;
      final items = store.occurrencesFor(now, includeOverdue: true);
      popups.add(PopupRequest.summary(items));
      _toast(summaryTitle(now), summaryBody(items));
    }

    for (final o in store.occurrencesFor(now)) {
      final due = o.dueTime;
      if (due == null || o.done || !o.task.remind) continue;
      if (due.isAfter(_lastTick) && !due.isAfter(now)) {
        popups.add(PopupRequest.reminder(o));
        _toast(o.task.title, '${o.task.timeText} · ${o.task.category}');
      }
    }
    _lastTick = now;
  }

  var _toastId = 1;
  Future<void> _toast(String title, String body) async {
    try {
      await plugin.show(_toastId++, title, body, const NotificationDetails());
    } catch (_) {}
  }

  /// 设置里修改早报时间后，允许当天重新弹一次
  void resetSummaryFlag() => _lastSummaryDay = '';

  void dispose() => _ticker?.cancel();
}
