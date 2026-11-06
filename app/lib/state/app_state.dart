import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/config.dart';
import '../data/api.dart';
import '../data/notifications.dart';
import '../data/push.dart';
import '../data/realtime.dart';
import '../data/store.dart';
import '../features/web3d/web_edges.dart';
import '../logic/next_move.dart';
import '../logic/notification_plan.dart';
import '../logic/outbox.dart';
import '../models/misc.dart';
import '../models/space.dart';
import '../models/thread.dart';

enum AuthStatus { unknown, signedOut, signedIn }

enum LinkStatus { live, connecting, offline, syncing }

class NotificationHealth {
  const NotificationHealth({this.supported = false, this.permissionGranted = false, this.exactAlarmAllowed = true});
  final bool supported, permissionGranted, exactAlarmAllowed;
}

class AppState extends ChangeNotifier {
  late LocalStore _store;
  late ApiClient _api;
  final RealtimeService _rt = RealtimeService();
  final NotificationService _notif = NotificationService();
  final PushService _push = PushService();
  StreamSubscription<RealtimeMessage>? _rtSub;
  StreamSubscription<NotificationEvent>? _notifSub;

  AppState();

  AppState.test({
    AuthStatus auth = AuthStatus.signedIn,
    UserProfile? user,
    String? authError,
    bool busy = false,
    List<Space> spaces = const [],
    List<Thread> threads = const [],
    AppSettings settings = const AppSettings(),
    LinkStatus link = LinkStatus.live,
    LocalStore? store,
    ApiClient? api,
  }) {
    _auth = auth;
    _user = user ?? const UserProfile(id: 'u1', email: 'test@spidermind.app', name: 'Tester', timezone: 'UTC');
    _authError = authError;
    _busy = busy;
    _settings = settings;
    _link = link;
    _store = store ?? LocalStore.noop();
    _api = api ?? ApiClient(baseUrl: 'http://localhost', clientId: 'test-client');
    for (final s in spaces) {
      _spaces[s.id] = s;
    }
    for (final t in threads) {
      _threads[t.id] = t;
    }
    _invalidate();
  }

  @visibleForTesting
  void setAuthStatusForTest(AuthStatus s) {
    _auth = s;
    notifyListeners();
  }

  @visibleForTesting
  void setAuthErrorForTest(String? err) {
    _authError = err;
    notifyListeners();
  }

  @visibleForTesting
  void setBusyForTest(bool b) {
    _busy = b;
    notifyListeners();
  }

  AuthStatus _auth = AuthStatus.unknown;
  UserProfile? _user;
  String? _authError;
  bool _busy = false;
  final Map<String, Thread> _threads = {};
  final Map<String, Space> _spaces = {};
  List<OutboxOp> _outbox = [];
  List<ActivityEntry> _activity = [];
  LinkStatus _link = LinkStatus.offline;
  DateTime? _lastSync;
  AppSettings _settings = const AppSettings();
  String _serverUrl = kDefaultServerUrl;
  final Set<String> _flash = {};
  bool _flushing = false;
  Timer? _retry, _planTimer, _tick;
  List<Thread>? _threadsCache;
  List<WebEdge>? _edgesCache;
  Map<String, int>? _degCache;

  // ------------------------------------------------------------ getters
  AuthStatus get authStatus => _auth;
  UserProfile? get user => _user;
  String? get authError => _authError;
  bool get busy => _busy;
  List<Space> get spaces => (_spaces.values.toList()..sort((a, b) => a.order.compareTo(b.order)));
  List<Thread> get threads => _threadsCache ??= (_threads.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)));
  Thread? threadById(String id) => _threads[id];
  Space? spaceById(String id) => _spaces[id];
  List<WebEdge> get edges => _edgesCache ??= buildWebEdges(threads);
  Map<String, int> get degrees => _degCache ??= degreeMap(edges);
  Set<String> get flashIds => Set.unmodifiable(_flash);
  List<ActivityEntry> get activity => List.unmodifiable(_activity);
  LinkStatus get link => _link;
  int get pendingWrites => _outbox.length;
  DateTime? get lastSyncAt => _lastSync;
  AppSettings get settings => _settings;
  String get serverUrl => _serverUrl;
  Stream<String> get notificationTaps => _notif.taps;
  String? takeLaunchPayload() {
    final p = _notif.launchPayload;
    _notif.launchPayload = null;
    return p;
  }

  NotificationHealth get notificationHealth =>
      NotificationHealth(supported: _notif.supported, permissionGranted: _notif.permissionGranted, exactAlarmAllowed: _notif.exactAllowed);

  /// Computed locally so it works offline and is always consistent with the web.
  Insights get insights {
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    var open = 0, done = 0, overdue = 0, today = 0, next7 = 0;
    final byDay = <String, int>{};
    String key(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    for (final t in _threads.values) {
      if (t.isDone) {
        done++;
        final c = t.completedAt?.toLocal();
        if (c != null) byDay[key(c)] = (byDay[key(c)] ?? 0) + 1;
        continue;
      }
      open++;
      final d = t.dueAt?.toLocal();
      if (d == null) continue;
      if (d.isBefore(now)) overdue++;
      if (!d.isBefore(dayStart) && d.isBefore(dayEnd)) today++;
      if (!d.isBefore(now) && d.isBefore(now.add(const Duration(days: 7)))) next7++;
    }
    final days = [
      for (var i = 13; i >= 0; i--)
        () {
          final d = dayStart.subtract(Duration(days: i));
          return DayCount(key(d), byDay[key(d)] ?? 0);
        }()
    ];
    var streak = 0;
    var cursor = dayStart;
    if ((byDay[key(cursor)] ?? 0) == 0) cursor = cursor.subtract(const Duration(days: 1));
    while ((byDay[key(cursor)] ?? 0) > 0) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return Insights(
        counts: InsightCounts(total: _threads.length, open: open, done: done, overdue: overdue, dueToday: today, dueNext7: next7),
        completedByDay: days,
        streak: streak);
  }

  // ------------------------------------------------------------ lifecycle
  Future<void> init() async {
    _store = await LocalStore.open();
    _settings = _store.settings;
    _serverUrl = kDefaultServerUrl;
    await _store.setServerUrl(kDefaultServerUrl);
    _api = ApiClient(baseUrl: _serverUrl, clientId: _store.clientId)
      ..onTokens = (t) {
        _store.writeTokens(t);
        if (t == null) _expire();
      };
    await _notif.init();
    await _push.init();
    _notifSub?.cancel();
    _notifSub = _notif.events.listen(_onNotificationEvent);
    final tokens = await _store.readTokens();
    _user = _store.user;
    if (tokens == null || _user == null) {
      _auth = AuthStatus.signedOut;
      notifyListeners();
      return;
    }
    _api.setTokens(tokens);
    _loadCache();
    _auth = AuthStatus.signedIn;
    notifyListeners();
    _schedulePlan();
    unawaited(_start());
  }

  void _loadCache() {
    _threads
      ..clear()
      ..addEntries(_store.threads.map((t) => MapEntry(t.id, t)));
    _spaces
      ..clear()
      ..addEntries(_store.spaces.map((s) => MapEntry(s.id, s)));
    _outbox = _store.outbox;
    _invalidate();
  }

  Future<void> _start() async {
    _connectRealtime();
    await refresh();
    _tick?.cancel();
    // Re-plan notifications and re-evaluate overdue state periodically.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => notifyListeners());
  }

  void _expire() {
    if (_auth == AuthStatus.signedIn) {
      _teardown();
      _auth = AuthStatus.signedOut;
      _authError = 'Your session ended. Please sign in again.';
      notifyListeners();
    }
  }

  void _teardown() {
    _notifSub?.cancel();
    _rtSub?.cancel();
    _rt.disconnect();
    _retry?.cancel();
    _tick?.cancel();
    _planTimer?.cancel();
    _threads.clear();
    _spaces.clear();
    _outbox = [];
    _activity = [];
    _flash.clear();
    _lastSync = null;
    _invalidate();
    _notif.cancelAll();
  }

  void _invalidate() {
    _threadsCache = null;
    _edgesCache = null;
    _degCache = null;
  }

  // ------------------------------------------------------------ auth
  Future<bool> login(String email, String password) => _authCall('/auth/login', {'email': email.trim(), 'password': password});

  static String _currentTimeZone() {
    final tz = DateTime.now().timeZoneName.trim();
    final lower = tz.toLowerCase();
    if (lower.contains('india') || lower == 'ist') return 'Asia/Kolkata';
    if (lower.contains('pacific') || lower == 'pst') return 'America/Los_Angeles';
    if (lower.contains('eastern') || lower == 'est') return 'America/New_York';
    if (lower.contains('central') || lower == 'cst') return 'America/Chicago';
    if (lower.contains('mountain') || lower == 'mst') return 'America/Denver';
    return tz.isNotEmpty ? tz : 'UTC';
  }

  Future<bool> register({required String email, required String password, required String name}) =>
      _authCall('/auth/register', {'email': email.trim(), 'password': password, 'name': name.trim(), 'timezone': _currentTimeZone()});

  Future<bool> loginWithGoogle(String credential) =>
      _authCall('/auth/google', {'credential': credential, 'idToken': credential, 'accessToken': credential});

  Future<bool> signInWithGoogle() async {
    _busy = true;
    _authError = null;
    notifyListeners();
    try {
      final googleSignIn = GoogleSignIn(
        clientId: kIsWeb ? '493865528762-6g4edvbovdsmaai2q14rtfccv4icase5.apps.googleusercontent.com' : null,
        scopes: ['email', 'profile'],
      );
      // Disconnect/sign out any cached account so Google always shows the account chooser dialog
      try {
        await googleSignIn.signOut();
      } catch (_) {}
      final account = await googleSignIn.signIn();
      if (account == null) {
        _busy = false;
        notifyListeners();
        return false;
      }
      final auth = await account.authentication;
      final token = auth.idToken ?? auth.accessToken;
      if (token == null || token.isEmpty) {
        _authError = 'Google did not return an authentication token.';
        _busy = false;
        notifyListeners();
        return false;
      }
      return await loginWithGoogle(token);
    } catch (e) {
      _busy = false;
      _authError = 'Google Sign-In: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  Future<bool> _authCall(String path, Map<String, dynamic> body) async {
    _busy = true;
    _authError = null;
    notifyListeners();
    try {
      final j = await _api.call('POST', path, body: body, auth: false) as Map<String, dynamic>;
      _api.setTokens(AuthTokens(j['accessToken'] as String, j['refreshToken'] as String));
      _user = UserProfile.fromJson(Map<String, dynamic>.from(j['user'] as Map));
      await _store.saveUser(_user);
      await _store.clearAccountData();
      _threads.clear();
      _spaces.clear();
      _outbox = [];
      _invalidate();
      _auth = AuthStatus.signedIn;
      _busy = false;
      notifyListeners();
      unawaited(_start());
      return true;
    } on ApiException catch (e) {
      _authError = e.message;
    } catch (_) {
      _authError = 'Could not sign in. Please try again.';
    }
    _busy = false;
    notifyListeners();
    return false;
  }

  Future<bool> verifyCode({required String email, required String code}) async {
    _busy = true;
    _authError = null;
    notifyListeners();
    try {
      final res = await _api.call('POST', '/auth/verify-code', body: {
        'email': email.trim(),
        'code': code.trim(),
      }, auth: false) as Map<String, dynamic>;
      if (res['verified'] == true) {
        if (_user != null) {
          _user = _user!.copyWith(isVerified: true);
          await _store.saveUser(_user!);
        }
        _busy = false;
        notifyListeners();
        return true;
      }
    } on ApiException catch (e) {
      _authError = e.message;
    } catch (_) {
      _authError = 'Verification failed. Please check the code and try again.';
    }
    _busy = false;
    notifyListeners();
    return false;
  }

  Future<bool> resendVerification(String email) async {
    try {
      await _api.call('POST', '/auth/send-verification', body: {'email': email.trim()}, auth: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> signOut() async {
    final r = _api.refresh;
    if (r != null) {
      try {
        await _api.call('POST', '/auth/logout', body: {'refreshToken': r}, auth: false);
      } catch (_) {}
    }
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    await _finishSignOut();
  }

  Future<void> _finishSignOut() async {
    _teardown();
    _api.clear();
    await _store.clearAccount();
    _user = null;
    _authError = null;
    _auth = AuthStatus.signedOut;
    notifyListeners();
  }

  Future<bool> deleteAccount(String password) async {
    try {
      await _api.call('DELETE', '/me', body: {'password': password});
      await _finishSignOut();
      return true;
    } on ApiException catch (e) {
      _authError = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<void> updateProfile({String? name, String? timezone}) async {
    try {
      final j = await _api.call('PATCH', '/me', body: {if (name != null) 'name': name, if (timezone != null) 'timezone': timezone}) as Map<String, dynamic>;
      _user = UserProfile.fromJson(Map<String, dynamic>.from(j['user'] as Map));
      await _store.saveUser(_user);
      notifyListeners();
    } catch (_) {}
  }

  // ------------------------------------------------------------ persistence helpers
  void _persist({bool threads = false, bool spaces = false, bool outbox = false}) {
    _invalidate();
    if (threads) _store.saveThreads(_threads.values);
    if (spaces) _store.saveSpaces(_spaces.values);
    if (outbox) _store.saveOutbox(_outbox);
    _schedulePlan();
    notifyListeners();
  }

  void _enqueue(OutboxOp op) {
    _outbox = compactOutbox(_outbox, op);
    _persist(outbox: true);
    unawaited(_flush());
  }

  void _schedulePlan() {
    _planTimer?.cancel();
    _planTimer = Timer(const Duration(milliseconds: 600), () {
      _notif.apply(planNotifications(_threads.values.toList(), _spaces.values.toList(), _settings, DateTime.now()));
    });
  }

  // ------------------------------------------------------------ mutations
  Thread createThread({
    required String title,
    ThreadType type = ThreadType.task,
    Priority priority = Priority.medium,
    String? spaceId,
    DateTime? dueAt,
    List<Reminder> reminders = const [],
    String notes = '',
  }) {
    final sp = spaceId ?? (spaces.isNotEmpty ? spaces.first.id : '');
    final t = Thread.draft(title: title.trim(), spaceId: sp, type: type, priority: priority, dueAt: dueAt, reminders: reminders).copyWith(notes: notes);
    _threads[t.id] = t;
    _enqueue(OutboxOp(kind: OutboxKind.putThread, id: t.id, body: t.toJson()));
    _persist(threads: true);
    return t;
  }

  void saveThread(Thread t) {
    var next = t.copyWith(updatedAt: DateTime.now().toUtc());
    final old = _threads[t.id];
    if (old != null && old.status != t.status) {
      next = t.status == ThreadStatus.done
          ? next.copyWith(completedAt: DateTime.now().toUtc())
          : next.copyWith(clearCompletedAt: true);
    }
    _threads[t.id] = next;
    _enqueue(OutboxOp(kind: OutboxKind.putThread, id: t.id, body: next.toJson()));
    _persist(threads: true);
  }

  void setStatus(String id, ThreadStatus s) {
    final t = _threads[id];
    if (t != null) saveThread(t.copyWith(status: s));
  }

  Thread? deleteThread(String id) {
    final t = _threads.remove(id);
    if (t == null) return null;
    for (final o in _threads.values.where((o) => o.links.contains(id)).toList()) {
      _threads[o.id] = o.copyWith(links: o.links.where((l) => l != id).toList());
    }
    _enqueue(OutboxOp(kind: OutboxKind.deleteThread, id: id));
    _persist(threads: true);
    return t;
  }

  void restoreThread(Thread t) => saveThread(t);

  void toggleChecklist(String id, String itemId) {
    final t = _threads[id];
    if (t == null) return;
    saveThread(t.copyWith(checklist: [for (final c in t.checklist) c.id == itemId ? ChecklistItem(id: c.id, text: c.text, done: !c.done) : c]));
  }

  void toggleLink(String a, String b) {
    final ta = _threads[a], tb = _threads[b];
    if (ta == null || tb == null || a == b) return;
    final linked = ta.links.contains(b);
    List<String> flip(List<String> l, String x) => linked ? l.where((e) => e != x).toList() : [...l, x];
    saveThread(ta.copyWith(links: flip(ta.links, b)));
    saveThread(tb.copyWith(links: flip(tb.links, a)));
  }

  Space createSpace(String name, String colorHex) {
    final s = Space.create(name.trim(), colorHex, _spaces.length);
    _spaces[s.id] = s;
    _enqueue(OutboxOp(kind: OutboxKind.putSpace, id: s.id, body: s.toJson()));
    _persist(spaces: true);
    return s;
  }

  void saveSpace(Space s) {
    _spaces[s.id] = s;
    _enqueue(OutboxOp(kind: OutboxKind.putSpace, id: s.id, body: s.toJson()));
    _persist(spaces: true);
  }

  Future<String?> deleteSpace(String id, {String? moveTo}) async {
    if (_spaces.length <= 1) return 'You need at least one space.';
    final hasThreads = _threads.values.any((t) => t.spaceId == id);
    if (hasThreads && (moveTo == null || !_spaces.containsKey(moveTo) || moveTo == id)) return 'Choose a space to move its threads to.';
    _spaces.remove(id);
    if (moveTo != null) {
      for (final t in _threads.values.where((t) => t.spaceId == id).toList()) {
        _threads[t.id] = t.copyWith(spaceId: moveTo);
      }
    }
    _enqueue(OutboxOp(kind: OutboxKind.deleteSpace, id: id, moveTo: moveTo));
    _persist(spaces: true, threads: true);
    unawaited(_flush());
    return null;
  }

  void reorderSpaces(List<String> orderedIds) {
    for (var i = 0; i < orderedIds.length; i++) {
      final s = _spaces[orderedIds[i]];
      if (s != null && s.order != i) saveSpace(s.copyWith(order: i));
    }
  }

  // ------------------------------------------------------------ sync
  Future<void> refresh() async {
    if (_auth != AuthStatus.signedIn) return;
    _setLink(LinkStatus.syncing);
    try {
      await _flush();
      final sp = await _api.call('GET', '/spaces') as Map<String, dynamic>;
      final serverSpaces = [for (final s in sp['spaces'] as List) Space.fromJson(Map<String, dynamic>.from(s as Map))];
      final pendingSpaceIds = {for (final o in _outbox) if (o.kind == OutboxKind.putSpace) o.id};
      final deletedSpaceIds = {for (final o in _outbox) if (o.kind == OutboxKind.deleteSpace) o.id};
      _spaces.removeWhere((id, _) => deletedSpaceIds.contains(id) || (!pendingSpaceIds.contains(id) && !serverSpaces.any((s) => s.id == id)));
      for (final s in serverSpaces) {
        if (!pendingSpaceIds.contains(s.id) && !deletedSpaceIds.contains(s.id)) _spaces[s.id] = s;
      }
      final since = _store.cursor;
      final j = await _api.call('GET', '/threads', query: {if (since != null) 'since': since}) as Map<String, dynamic>;
      final incoming = [for (final t in j['threads'] as List) Thread.fromJson(Map<String, dynamic>.from(t as Map))];
      final deleted = [for (final d in (j['deletedIds'] as List? ?? const [])) d as String];
      if (since == null) {
        final pending = {for (final o in _outbox) o.id};
        _threads.removeWhere((id, _) => !pending.contains(id) && !incoming.any((t) => t.id == id));
      }
      for (final t in incoming) {
        _threads[t.id] = mergeThread(_threads[t.id], t);
      }
      for (final id in deleted) {
        _threads.remove(id);
      }
      await _store.saveCursor(j['serverTime'] as String?);
      try {
        final a = await _api.call('GET', '/activity', query: {'limit': '50'}) as Map<String, dynamic>;
        _activity = [for (final e in a['activity'] as List) ActivityEntry.fromJson(Map<String, dynamic>.from(e as Map))];
      } catch (_) {}
      _lastSync = DateTime.now();
      _persist(threads: true, spaces: true);
      _setLink(_rtConnected ? LinkStatus.live : LinkStatus.connecting);
    } on ApiException catch (e) {
      _setLink(e.offline ? LinkStatus.offline : LinkStatus.connecting);
      if (e.offline) _retry = Timer(const Duration(seconds: 15), refresh);
    }
  }

  Future<void> _flush() async {
    if (_flushing || _auth != AuthStatus.signedIn) return;
    _flushing = true;
    try {
      while (_outbox.isNotEmpty) {
        final op = _outbox.first;
        try {
          switch (op.kind) {
            case OutboxKind.putThread:
              final j = await _api.call('PUT', '/threads/${op.id}', body: op.body) as Map<String, dynamic>?;
              final tj = j?['thread'];
              if (tj is Map && _threads.containsKey(op.id) && _outbox.length == 1) {
                final server = Thread.fromJson(Map<String, dynamic>.from(tj));
                _threads[op.id] = mergeThread(_threads[op.id], server);
              }
              break;
            case OutboxKind.deleteThread:
              await _api.call('DELETE', '/threads/${op.id}');
              break;
            case OutboxKind.putSpace:
              await _api.call('PUT', '/spaces/${op.id}', body: op.body);
              break;
            case OutboxKind.deleteSpace:
              await _api.call('DELETE', '/spaces/${op.id}', query: {if (op.moveTo != null) 'moveTo': op.moveTo!});
              break;
          }
          _outbox = _outbox.sublist(1);
        } on ApiException catch (e) {
          if (e.offline || e.status >= 500 || e.status == 401) {
            op.attempts++;
            _retry?.cancel();
            _retry = Timer(backoffFor(op.attempts), () => unawaited(_flush()));
            _setLink(LinkStatus.offline);
            break;
          }
          // Rejected for good (validation / not found): drop it so it cannot block the queue.
          _outbox = _outbox.sublist(1);
        }
      }
      await _store.saveOutbox(_outbox);
      _invalidate();
      notifyListeners();
    } finally {
      _flushing = false;
    }
  }

  // ------------------------------------------------------------ realtime
  bool _rtConnected = false;

  void _setLink(LinkStatus s) {
    if (_link != s) {
      _link = s;
      notifyListeners();
    }
  }

  void _connectRealtime() {
    _rtSub?.cancel();
    final token = _api.access;
    if (token == null) return;
    _setLink(LinkStatus.connecting);
    _rt.connect(_serverUrl, token);
    _rtSub = _rt.stream.listen(_onRealtime);
  }

  void _onRealtime(RealtimeMessage m) {
    final d = m.data;
    final mine = d['origin'] == _api.clientId;
    switch (m.event) {
      case RealtimeEvent.connected:
        _rtConnected = true;
        _setLink(LinkStatus.live);
        unawaited(refresh());
        break;
      case RealtimeEvent.disconnected:
        _rtConnected = false;
        _setLink(LinkStatus.offline);
        break;
      case RealtimeEvent.unauthorized:
        _api.ensureFresh().then((ok) {
          if (ok) _connectRealtime();
        });
        break;
      case RealtimeEvent.threadUpsert:
        if (mine || d['thread'] is! Map) return;
        final t = Thread.fromJson(Map<String, dynamic>.from(d['thread'] as Map));
        if (_outbox.any((o) => o.id == t.id)) return;
        _threads[t.id] = mergeThread(_threads[t.id], t);
        _flashFor(t.id);
        _persist(threads: true);
        break;
      case RealtimeEvent.threadDelete:
        if (mine) return;
        if (_threads.remove(d['id']) != null) _persist(threads: true);
        break;
      case RealtimeEvent.spaceUpsert:
        if (mine || d['space'] is! Map) return;
        final s = Space.fromJson(Map<String, dynamic>.from(d['space'] as Map));
        _spaces[s.id] = s;
        _persist(spaces: true);
        break;
      case RealtimeEvent.spaceDelete:
        if (mine) return;
        if (_spaces.remove(d['id']) != null) _persist(spaces: true);
        break;
      case RealtimeEvent.activity:
        final a = d['activity'];
        if (a is Map) {
          _activity = [ActivityEntry.fromJson(Map<String, dynamic>.from(a)), ..._activity].take(80).toList();
          notifyListeners();
        }
        break;
      case RealtimeEvent.reminderDue:
        // The device schedule already covers this; mark the reminder as sent locally.
        final t = _threads[d['threadId']];
        if (t != null) {
          _threads[t.id] = t.copyWith(reminders: [
            for (final r in t.reminders) r.id == d['reminderId'] ? Reminder(id: r.id, at: r.at, sentAt: DateTime.now().toUtc()) : r
          ]);
          _persist(threads: true);
        }
        break;
    }
  }

  void _flashFor(String id) {
    _flash.add(id);
    Timer(const Duration(milliseconds: 2500), () {
      _flash.remove(id);
      notifyListeners();
    });
  }

  Future<List<ActivityEntry>> activityFor(String threadId) async {
    try {
      final a = await _api.call('GET', '/activity', query: {'limit': '30', 'threadId': threadId}) as Map<String, dynamic>;
      return [for (final e in a['activity'] as List) ActivityEntry.fromJson(Map<String, dynamic>.from(e as Map))];
    } catch (_) {
      return const [];
    }
  }

  // ------------------------------------------------------------ derived
  List<NextMove> nextMoves({int limit = 5}) => rankNextMoves(threads, degrees, DateTime.now(), limit: limit);
  Thread? get hub => findHub(threads, degrees);
  List<Thread> get looseEnds => findLooseEnds(threads, degrees);
  List<Thread> relatedTo(String id) => relatedThreads(id, threads, edges);

  // ------------------------------------------------------------ settings
  void updateSettings(AppSettings s) {
    _settings = s;
    _store.saveSettings(s);
    _schedulePlan();
    notifyListeners();
  }

  Future<void> setServerUrl(String url) async {
    var u = url.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    if (u.isEmpty) return;
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    // Render and remote cloud providers enforce HTTPS: upgrade http to https
    final isLocal = u.contains('localhost') || u.contains('10.0.2.2') || u.contains('127.0.0.1') || u.contains('192.168.');
    if (!isLocal && u.startsWith('http://')) {
      u = u.replaceFirst('http://', 'https://');
    }
    _serverUrl = u;
    _api.baseUrl = u;
    await _store.setServerUrl(u);
    if (_auth == AuthStatus.signedIn) {
      _connectRealtime();
      unawaited(refresh());
    }
    notifyListeners();
  }

  // ------------------------------------------------------------ notifications
  Future<void> requestNotificationPermission() async {
    await _notif.requestPermission();
    _schedulePlan();
    notifyListeners();
  }

  Future<void> openExactAlarmSettings() async {
    await _notif.openExactAlarmSettings();
    notifyListeners();
  }

  Future<void> sendTestNotification() async {
    await _notif.showNow('Reminders are working', 'This is how your thread reminders will look.');
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert({
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'spaces': [for (final s in spaces) s.toJson()],
        'threads': [for (final t in threads) t.toJson()],
      });

  void _onNotificationEvent(NotificationEvent e) {
    final payload = e.payload;
    if (payload == null || payload.isEmpty) return;
    if (e.actionId == 'action_done') {
      final t = _threads[payload];
      if (t != null) {
        setStatus(t.id, ThreadStatus.done);
      }
    } else if (e.actionId == 'action_snooze') {
      final t = _threads[payload];
      if (t != null) {
        final snoozeAt = DateTime.now().add(const Duration(hours: 1));
        final updatedReminders = [
          ...t.reminders,
          Reminder(id: 'snooze_${DateTime.now().millisecondsSinceEpoch}', at: snoozeAt),
        ];
        saveThread(t.copyWith(reminders: updatedReminders));
      }
    }
  }

  @visibleForTesting
  void handleNotificationEventForTest(NotificationEvent e) => _onNotificationEvent(e);

  @override
  void dispose() {
    _notifSub?.cancel();
    _rtSub?.cancel();
    _rt.disconnect();
    _retry?.cancel();
    _planTimer?.cancel();
    _tick?.cancel();
    super.dispose();
  }
}
