import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/task.dart';
import 'store.dart';

/// 通过坚果云 WebDAV 同步。云端只有一个文件：/我的坚果云/jinrishi/data.json
class SyncService extends ChangeNotifier {
  SyncService._();
  static final SyncService I = SyncService._();

  static const base = 'https://dav.jianguoyun.com/dav/';
  static const folder = 'jinrishi';
  static const fileName = 'data.json';

  bool busy = false;
  Timer? _debounce;
  Timer? _periodic;
  bool _again = false;

  Store get _store => Store.I;

  Map<String, String> _headers(String user, String pass) => {
        'Authorization': 'Basic ${base64Encode(utf8.encode('$user:$pass'))}',
      };

  void start() {
    _store.onLocalChange = () {
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 3), () => syncNow());
    };
    _periodic?.cancel();
    _periodic = Timer.periodic(const Duration(minutes: 5), (_) => syncNow());
  }

  /// 测试账号是否可用，返回错误信息；成功返回 null。
  Future<String?> testLogin(String user, String pass) async {
    try {
      final req = http.Request('PROPFIND', Uri.parse(base))
        ..headers.addAll(_headers(user, pass))
        ..headers['Depth'] = '0';
      final res = await http.Client().send(req).timeout(const Duration(seconds: 15));
      if (res.statusCode == 207 || res.statusCode == 200) return null;
      if (res.statusCode == 401) return '账号或应用密码不正确（注意要用“第三方应用密码”，不是登录密码）';
      return '服务器返回 ${res.statusCode}';
    } catch (e) {
      return '连接失败：$e';
    }
  }

  Future<void> syncNow() async {
    final s = _store.settings;
    if (!s.syncConfigured) return;
    if (busy) {
      _again = true;
      return;
    }
    busy = true;
    notifyListeners();
    try {
      await _syncOnce(s.davUser, s.davPass);
      s.lastSyncAt = nowMs();
      s.lastSyncMsg = '同步成功';
    } catch (e) {
      s.lastSyncMsg = '同步失败：$e';
    } finally {
      busy = false;
      await _store.saveSettings();
      notifyListeners();
    }
    if (_again) {
      _again = false;
      unawaited(syncNow());
    }
  }

  Future<void> _syncOnce(String user, String pass) async {
    final h = _headers(user, pass);
    final dirUri = Uri.parse('$base$folder/');
    final fileUri = Uri.parse('$base$folder/$fileName');
    final client = http.Client();
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        final get = await client.get(fileUri, headers: h).timeout(const Duration(seconds: 20));
        String? etag;
        String? remoteCanon;
        if (get.statusCode == 200) {
          etag = get.headers['etag'];
          final remote = jsonDecode(utf8.decode(get.bodyBytes)) as Map<String, dynamic>;
          _store.mergeRemote(remote);
          remoteCanon = _canonical(remote);
        } else if (get.statusCode == 404 || get.statusCode == 409) {
          final mk = await client
              .send(http.Request('MKCOL', dirUri)..headers.addAll(h))
              .timeout(const Duration(seconds: 15));
          if (mk.statusCode >= 400 && mk.statusCode != 405) {
            throw '创建云端文件夹失败（${mk.statusCode}）';
          }
        } else if (get.statusCode == 401) {
          throw '坚果云账号或应用密码不正确';
        } else {
          throw '下载失败（${get.statusCode}）';
        }

        final local = _store.exportDoc();
        if (remoteCanon != null && remoteCanon == _canonical(local)) return;

        final putHeaders = {...h, 'Content-Type': 'application/json; charset=utf-8'};
        if (etag != null) putHeaders['If-Match'] = etag;
        final put = await client
            .put(fileUri, headers: putHeaders, body: utf8.encode(jsonEncode(local)))
            .timeout(const Duration(seconds: 20));
        if (put.statusCode == 412) continue; // 另一台设备刚好也上传了，重新合并
        if (put.statusCode >= 300) throw '上传失败（${put.statusCode}）';
        return;
      }
      throw '多台设备同时修改，稍后会自动重试';
    } finally {
      client.close();
    }
  }

  /// 规范化后比较，避免没有变化时也上传。
  String _canonical(Map<String, dynamic> doc) {
    final tasks = ((doc['tasks'] ?? []) as List)
        .map((e) => Task.fromJson(e as Map<String, dynamic>).toJson())
        .toList()
      ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    final comps = Map<String, dynamic>.from((doc['completions'] ?? {}) as Map);
    final keys = comps.keys.toList()..sort();
    final cats = doc['categories'] ?? {};
    return jsonEncode({
      't': tasks,
      'c': [for (final k in keys) [k, comps[k]['done'], comps[k]['updatedAt']]],
      'g': cats is Map ? [cats['list'], cats['updatedAt']] : null,
    });
  }
}
