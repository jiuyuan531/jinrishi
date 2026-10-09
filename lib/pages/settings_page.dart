import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';

import '../services/desktop.dart';
import '../services/holidays.dart';
import '../services/reminders.dart';
import '../services/store.dart';
import '../services/sync.dart';

const androidPackage = 'com.shen.jinrishi';

Future<void> _openIntent(BuildContext context, AndroidIntent intent, {AndroidIntent? fallback}) async {
  try {
    await intent.launch();
  } catch (_) {
    if (fallback != null) {
      try {
        await fallback.launch();
        return;
      } catch (_) {}
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法自动打开，请在系统设置里手动找到“今日事”')));
    }
  }
}

const _appDetails = AndroidIntent(
  action: 'action_application_details_settings',
  data: 'package:$androidPackage',
);

Future<void> openMiuiAutostart(BuildContext context) => _openIntent(
      context,
      const AndroidIntent(
        componentName: 'com.miui.permcenter.autostart.AutoStartManagementActivity',
        package: 'com.miui.securitycenter',
      ),
      fallback: _appDetails,
    );

Future<void> openBatterySettings(BuildContext context) => _openIntent(
      context,
      const AndroidIntent(
        action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
        data: 'package:$androidPackage',
      ),
      fallback: _appDetails,
    );

Future<void> openAppDetails(BuildContext context) => _openIntent(context, _appDetails);

/// 安卓首次打开时的权限引导（小米手机不设置的话，后台提醒容易被系统拦截）。
Future<void> showAndroidGuide(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      title: const Text('让提醒准时弹出'),
      content: const SingleChildScrollView(
        child: Text(
          '小米手机会限制后台应用，请依次完成：\n\n'
          '1. 允许通知、闹钟和提醒、全屏通知（点下面第一个按钮）\n'
          '2. 开启“自启动”\n'
          '3. 省电策略设为“无限制”\n'
          '4. 在“通知管理 → 今日事 → 到点提醒”里打开“悬浮通知”和“锁屏通知”\n\n'
          '之后可以在“设置 → 后台与权限”里重新打开这些页面。',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Reminders.I.requestAndroidPermissions(),
          child: const Text('1 授予权限'),
        ),
        TextButton(onPressed: () => openMiuiAutostart(c), child: const Text('2 自启动')),
        TextButton(onPressed: () => openBatterySettings(c), child: const Text('3 省电')),
        FilledButton(
          onPressed: () async {
            Store.I.settings.guideShown = true;
            await Store.I.saveSettings();
            Reminders.I.scheduleSoon();
            if (c.mounted) Navigator.pop(c);
          },
          child: const Text('完成'),
        ),
      ],
    ),
  );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final s = Store.I.settings;
  late final _user = TextEditingController(text: s.davUser);
  late final _pass = TextEditingController(text: s.davPass);
  bool _testing = false;
  bool? _autoStart;
  Map<String, bool> _perm = {};

  @override
  void initState() {
    super.initState();
    SyncService.I.addListener(_refresh);
    if (Platform.isWindows) {
      Desktop.I.isAutoStartEnabled().then((v) => setState(() => _autoStart = v));
    }
    _loadPerm();
  }

  Future<void> _loadPerm() async {
    if (!Platform.isAndroid) return;
    final p = await Reminders.I.androidPermissionState();
    if (mounted) setState(() => _perm = p);
  }

  @override
  void dispose() {
    SyncService.I.removeListener(_refresh);
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _saveDav() async {
    final u = _user.text.trim(), p = _pass.text.trim();
    if (u.isEmpty || p.isEmpty) {
      s.davUser = '';
      s.davPass = '';
      await Store.I.saveSettings();
      _toast('已关闭同步');
      setState(() {});
      return;
    }
    setState(() => _testing = true);
    final err = await SyncService.I.testLogin(u, p);
    setState(() => _testing = false);
    if (err != null) {
      _toast(err);
      return;
    }
    s.davUser = u;
    s.davPass = p;
    await Store.I.saveSettings();
    _toast('连接成功，开始同步');
    await SyncService.I.syncNow();
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Text(t, style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final summary = TimeOfDay(hour: s.summaryMinute ~/ 60, minute: s.summaryMinute % 60);
    final year = DateTime.now().year;
    final lastSync = s.lastSyncAt == 0 ? '从未同步' : DateTime.fromMillisecondsSinceEpoch(s.lastSyncAt).toString().substring(0, 16);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          _header('每日清单'),
          SwitchListTile(
            title: const Text('早上推送今日清单'),
            value: s.summaryEnabled,
            onChanged: (v) async {
              setState(() => s.summaryEnabled = v);
              await Store.I.saveSettings();
              Reminders.I.scheduleSoon();
            },
          ),
          ListTile(
            title: const Text('推送时间'),
            trailing: Text(summary.format(context), style: const TextStyle(fontSize: 16)),
            onTap: () async {
              final r = await showTimePicker(
                context: context,
                initialTime: summary,
                builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
              );
              if (r == null) return;
              setState(() => s.summaryMinute = r.hour * 60 + r.minute);
              await Store.I.saveSettings();
              Reminders.I.resetSummaryFlag();
              Reminders.I.scheduleSoon();
            },
          ),

          _header('坚果云同步（手机和电脑填同一个账号）'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              TextField(
                controller: _user,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: '坚果云账号（邮箱或手机号）', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pass,
                obscureText: true,
                decoration: const InputDecoration(labelText: '第三方应用密码', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              Text(
                '应用密码获取：登录坚果云网页版 → 右上角账户信息 → 安全选项 → 第三方应用管理 → 添加应用，名称填“今日事”，生成的密码填到这里。数据存在坚果云的“jinrishi”文件夹里。',
                style: TextStyle(fontSize: 12, color: cs.outline),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _testing ? null : _saveDav,
                    child: Text(_testing ? '正在连接…' : '测试并保存'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: s.syncConfigured && !SyncService.I.busy ? SyncService.I.syncNow : null,
                    child: Text(SyncService.I.busy ? '同步中…' : '立即同步'),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              if (s.syncConfigured)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('上次同步：$lastSync  ${s.lastSyncMsg}', style: TextStyle(fontSize: 12, color: cs.outline)),
                ),
            ]),
          ),

          _header('法定节假日'),
          ListTile(
            title: Text('$year 年：${Holidays.I.hasYear(year) ? '已有数据' : '暂无数据'}　'
                '${year + 1} 年：${Holidays.I.hasYear(year + 1) ? '已有数据' : '未公布或未下载'}'),
            subtitle: const Text('每年 11 月前后国务院公布次年安排，联网时会自动下载'),
            trailing: IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '立即检查',
              onPressed: () async {
                final added = await Holidays.I.refresh();
                Reminders.I.scheduleSoon();
                if (mounted) {
                  setState(() {});
                  _toast(added.isEmpty ? '没有新的节假日安排' : '已更新 ${added.join('、')} 年');
                }
              },
            ),
          ),

          if (Platform.isAndroid) ...[
            _header('后台与权限（小米手机必看）'),
            ListTile(
              leading: Icon(_perm['notify'] == true ? Icons.check_circle : Icons.error_outline,
                  color: _perm['notify'] == true ? cs.primary : const Color(0xFFE76F51)),
              title: const Text('通知权限'),
              subtitle: const Text('同时会申请“闹钟和提醒”“全屏通知”'),
              onTap: () async {
                await Reminders.I.requestAndroidPermissions();
                await _loadPerm();
              },
            ),
            ListTile(
              leading: Icon(_perm['exact'] == true ? Icons.check_circle : Icons.error_outline,
                  color: _perm['exact'] == true ? cs.primary : const Color(0xFFE76F51)),
              title: const Text('准时提醒（闹钟和提醒权限）'),
              subtitle: Text(_perm['exact'] == true ? '已开启' : '未开启时提醒可能延迟几分钟'),
              onTap: () async {
                await Reminders.I.requestAndroidPermissions();
                await _loadPerm();
              },
            ),
            ListTile(
              leading: const Icon(Icons.rocket_launch_outlined),
              title: const Text('自启动'),
              subtitle: const Text('打开“今日事”的开关，重启手机后提醒才不会丢'),
              onTap: () => openMiuiAutostart(context),
            ),
            ListTile(
              leading: const Icon(Icons.battery_charging_full),
              title: const Text('省电策略'),
              subtitle: const Text('设为“无限制”'),
              onTap: () => openBatterySettings(context),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('悬浮通知 / 锁屏通知'),
              subtitle: const Text('应用信息 → 通知管理 → 到点提醒 → 打开悬浮通知、锁屏通知'),
              onTap: () => openAppDetails(context),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('说明'),
              subtitle: const Text('手机上会提前排好未来 14 天的提醒，每次打开应用或同步后自动更新。'),
            ),
          ],

          if (Platform.isWindows) ...[
            _header('电脑端'),
            SwitchListTile(
              title: const Text('开机自动启动'),
              value: _autoStart ?? false,
              onChanged: _autoStart == null
                  ? null
                  : (v) async {
                      await Desktop.I.setAutoStart(v);
                      setState(() => _autoStart = v);
                    },
            ),
            SwitchListTile(
              title: const Text('开机启动时只显示在托盘'),
              subtitle: const Text('关闭窗口也会缩到右下角托盘，提醒照常'),
              value: s.startHidden,
              onChanged: (v) async {
                setState(() => s.startHidden = v);
                await Store.I.saveSettings();
              },
            ),
          ],

          _header('分类'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 8, runSpacing: 4, children: [
              for (final c in Store.I.categories)
                InputChip(
                  label: Text(c),
                  onDeleted: Store.I.categories.length <= 1
                      ? null
                      : () => setState(() => Store.I.setCategories(Store.I.categories.where((e) => e != c).toList())),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text('删除分类不会删除其中的事项。', style: TextStyle(fontSize: 12, color: cs.outline)),
          ),

          _header('关于'),
          const ListTile(title: Text('今日事 1.0.0'), subtitle: Text('数据保存在本机，并可通过你自己的坚果云同步')),
        ],
      ),
    );
  }
}
