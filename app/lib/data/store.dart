import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/misc.dart';
import '../models/space.dart';
import '../models/thread.dart';
import '../logic/outbox.dart';
import 'api.dart';

/// Everything persisted on the device: tokens (secure), and a per-user cache
/// of threads, spaces, outbox, and sync cursor (so the app opens instantly and
/// works offline).
class LocalStore {
  LocalStore(this._p);
  LocalStore.noop() : _p = null;

  final SharedPreferences? _p;
  static const _secure = FlutterSecureStorage();

  static Future<LocalStore> open() async => LocalStore(await SharedPreferences.getInstance());

  String get clientId {
    final p = _p;
    if (p == null) return 'test-client-id';
    var id = p.getString('clientId');
    if (id == null) {
      final r = Random.secure();
      id = 'app-${List.generate(12, (_) => r.nextInt(16).toRadixString(16)).join()}';
      p.setString('clientId', id);
    }
    return id;
  }

  String? get serverUrl => _p?.getString('serverUrl');
  Future<void> setServerUrl(String v) async => await _p?.setString('serverUrl', v);

  AppSettings get settings {
    final s = _p?.getString('settings');
    if (s == null) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> saveSettings(AppSettings s) async => await _p?.setString('settings', jsonEncode(s.toJson()));

  Future<AuthTokens?> readTokens() async {
    try {
      final a = await _secure.read(key: 'access');
      final r = await _secure.read(key: 'refresh');
      return a == null || r == null ? null : AuthTokens(a, r);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeTokens(AuthTokens? t) async {
    try {
      if (t == null) {
        await _secure.delete(key: 'access');
        await _secure.delete(key: 'refresh');
      } else {
        await _secure.write(key: 'access', value: t.access);
        await _secure.write(key: 'refresh', value: t.refresh);
      }
    } catch (_) {}
  }

  UserProfile? get user {
    final s = _p?.getString('user');
    if (s == null) return null;
    try {
      return UserProfile.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveUser(UserProfile? u) async => u == null ? await _p?.remove('user') : await _p?.setString('user', jsonEncode(u.toJson()));

  List<Thread> get threads => _list('threads', Thread.fromJson);
  List<Space> get spaces => _list('spaces', Space.fromJson);
  List<OutboxOp> get outbox => _list('outbox', OutboxOp.fromJson);
  String? get cursor => _p?.getString('cursor');

  List<T> _list<T>(String key, T Function(Map<String, dynamic>) f) {
    final s = _p?.getString(key);
    if (s == null) return [];
    try {
      return [for (final e in jsonDecode(s) as List) f(Map<String, dynamic>.from(e as Map))];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveThreads(Iterable<Thread> t) async => await _p?.setString('threads', jsonEncode([for (final x in t) x.toCacheJson()]));
  Future<void> saveSpaces(Iterable<Space> s) async => await _p?.setString('spaces', jsonEncode([for (final x in s) x.toJson()]));
  Future<void> saveOutbox(Iterable<OutboxOp> o) async => await _p?.setString('outbox', jsonEncode([for (final x in o) x.toJson()]));
  Future<void> saveCursor(String? c) async => c == null ? await _p?.remove('cursor') : await _p?.setString('cursor', c);

  Future<void> clearAccountData() async {
    final p = _p;
    if (p == null) return;
    for (final k in ['threads', 'spaces', 'outbox', 'cursor']) {
      await p.remove(k);
    }
  }

  /// Wipes account data (keeps server URL, settings, client id).
  Future<void> clearAccount() async {
    final p = _p;
    if (p != null) {
      for (final k in ['threads', 'spaces', 'outbox', 'cursor', 'user']) {
        await p.remove(k);
      }
    }
    await writeTokens(null);
  }
}
