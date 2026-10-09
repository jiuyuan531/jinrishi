import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';

import 'pages/home_page.dart';
import 'services/desktop.dart';
import 'services/holidays.dart';
import 'services/reminders.dart';
import 'services/store.dart';
import 'services/sync.dart';
import 'services/widget_sync.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);

  await Holidays.I.init(dir);
  await Store.I.init(dir);
  if (Platform.isWindows) {
    await Desktop.I.init(args, startHidden: Store.I.settings.startHidden);
  }
  await Reminders.I.init();
  SyncService.I.start();

  Store.I.addListener(() {
    Reminders.I.scheduleSoon();
    WidgetSync.update();
  });

  runApp(const JinrishiApp());

  // 启动后的后台工作
  unawaited(() async {
    await Reminders.I.reschedule();
    await WidgetSync.update();
    final added = await Holidays.I.refresh();
    if (added.isNotEmpty) {
      Reminders.I.scheduleSoon();
      WidgetSync.update();
    }
    await SyncService.I.syncNow();
  }());
}

class JinrishiApp extends StatefulWidget {
  const JinrishiApp({super.key});

  @override
  State<JinrishiApp> createState() => _JinrishiAppState();
}

class _JinrishiAppState extends State<JinrishiApp> with WidgetsBindingObserver {
  Timer? _minuteTimer;
  Timer? _actionPoll;
  String _today = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _today = _todayKey();
    // 跨天时刷新清单、重排提醒
    _minuteTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final k = _todayKey();
      if (k != _today) {
        _today = k;
        setState(() {});
        Reminders.I.scheduleSoon();
        WidgetSync.update();
      }
    });
    // 通知栏里点了“完成”后，尽快反映到界面上
    _actionPoll = Timer.periodic(
        const Duration(seconds: 20), (_) => Store.I.applyPendingActions());
  }

  String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Store.I.applyPendingActions();
      Reminders.I.scheduleSoon();
      WidgetSync.update();
      SyncService.I.syncNow();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _minuteTimer?.cancel();
    _actionPoll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2E6F5E),
            brightness: b,
          ),
          fontFamilyFallback: const ['Microsoft YaHei UI', 'PingFang SC', 'Noto Sans CJK SC'],
        );
    return MaterialApp(
      title: '今日事',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const HomePage(),
    );
  }
}
