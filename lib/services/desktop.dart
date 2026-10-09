import 'dart:io';

import 'package:flutter/material.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

/// Windows 专用：托盘、关闭到托盘、开机自启、置顶弹窗、小窗模式。
class Desktop with WindowListener, TrayListener {
  Desktop._();
  static final Desktop I = Desktop._();

  static const normalSize = Size(460, 760);
  static const miniSize = Size(320, 420);

  bool mini = false;
  final miniNotifier = ValueNotifier<bool>(false);

  Future<void> init(List<String> args, {required bool startHidden}) async {
    await WindowsSingleInstance.ensureSingleInstance(
      args,
      'jinrishi_single_instance',
      onSecondWindow: (_) => showWindow(),
    );
    await windowManager.ensureInitialized();
    final launchedHidden = args.contains('--hidden') && startHidden;
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: normalSize,
        minimumSize: Size(300, 360),
        center: true,
        title: '今日事',
      ),
      () async {
        if (!launchedHidden) {
          await windowManager.show();
          await windowManager.focus();
        }
      },
    );
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    launchAtStartup.setup(
      appName: '今日事',
      appPath: Platform.resolvedExecutable,
      args: const ['--hidden'],
    );

    await trayManager.setIcon('assets/tray_icon.ico');
    await trayManager.setToolTip('今日事');
    await _buildMenu();
    trayManager.addListener(this);
  }

  Future<void> _buildMenu() async {
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'show', label: '打开今日事'),
      MenuItem(key: 'mini', label: mini ? '退出小窗' : '小窗置顶'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: '退出'),
    ]));
  }

  Future<bool> isAutoStartEnabled() => launchAtStartup.isEnabled();
  Future<void> setAutoStart(bool on) async {
    if (on) {
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
    }
  }

  Future<void> showWindow() async {
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  }

  /// 弹窗提醒：把窗口拉到最前面并暂时置顶
  Future<void> popToFront() async {
    await showWindow();
    await windowManager.setAlwaysOnTop(true);
    await windowManager.focus();
  }

  Future<void> releaseTop() async {
    if (!mini) await windowManager.setAlwaysOnTop(false);
  }

  Future<void> toggleMini() async {
    mini = !mini;
    miniNotifier.value = mini;
    if (mini) {
      await windowManager.setSize(miniSize);
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setAlignment(Alignment.topRight);
    } else {
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setSize(normalSize);
      await windowManager.center();
    }
    await showWindow();
    await _buildMenu();
  }

  @override
  void onWindowClose() async {
    // 点关闭只是缩到托盘，提醒照常工作
    await windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() => showWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show':
        await showWindow();
      case 'mini':
        await toggleMini();
      case 'quit':
        await trayManager.destroy();
        await windowManager.setPreventClose(false);
        await windowManager.destroy();
        exit(0);
    }
  }
}
