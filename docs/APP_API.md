# App internal API (binding, in addition to CONTRACT.md section 5-7)

Ownership (nobody edits files they do not own; ask by leaving a `// TODO(owner): ...` comment if a change is needed):
* **infra** owns `lib/main.dart`, `lib/app.dart`, `lib/core/**`, `lib/data/**`, `lib/state/**`, `lib/logic/**`, `lib/models/{user,activity,insights,settings,next_move}.dart`, tests for those.
* **ui** owns `lib/ui/**` and `test/ui/**`.
* **web3d** owns `lib/features/web3d/**` and `test/web3d/**`.
* Already written, treat as read-only unless you are infra: `lib/models/{thread,space,urgency}.dart`, `lib/features/web3d/web_edges.dart`.

Pure-Dart rule (so logic can be verified without the Flutter SDK): everything in `lib/logic/**`, `lib/models/**`, and
`lib/features/web3d/{web_layout,web_camera,web_lod}.dart` imports only `dart:*` (plus `dart:ui show Color` where noted) and other pure files.
Their tests import only `package:flutter_test/flutter_test.dart` and use only: test, group, setUp, tearDown, expect, equals, isTrue,
isFalse, isNull, isNotNull, isEmpty, isNotEmpty, closeTo, greaterThan(OrEqualTo), lessThan(OrEqualTo), hasLength, contains, startsWith,
endsWith, isNot, anyOf, allOf, everyElement, orderedEquals, unorderedEquals, predicate, isA<T>().having, throwsA, throwsArgumentError, throwsStateError.
Verify with: `python3 /tmp/claude-0/dartsdk/verify_pure.py` (runs dart analyze + the pure tests; widget tests are skipped there).
Plugin-dependent code stays thin and obviously correct, no clever generics, explicit types, null-safe, `const` where possible.

## Models added by infra (all pure Dart, `fromJson`/`toJson`)
```dart
// lib/models/user.dart
class UserProfile { final String id, email, name, timezone; const UserProfile({...}); factory fromJson; toJson; copyWith({name,timezone}) }
// lib/models/activity.dart
enum ActivityKind { created, updated, status, reminder, linked, deleted }
class ActivityEntry { final String id; final ActivityKind kind; final String threadId; final String message; final DateTime at; }
// lib/models/insights.dart
class InsightCounts { final int total, open, done, overdue, dueToday, dueNext7; }
class DayCount { final String date; /* YYYY-MM-DD */ final int count; }
class Insights { final InsightCounts counts; final List<DayCount> completedByDay; final int streak; }
// lib/models/settings.dart
class AppSettings {
  final ThemeModeSetting theme;      // enum ThemeModeSetting { system, light, dark }   (no Flutter import here)
  final bool reduceMotion, lowGraphics, showDone, digestEnabled;
  final int digestMinutes;           // minutes after local midnight, default 540 (09:00)
  const AppSettings({this.theme = ThemeModeSetting.system, this.reduceMotion = false, this.lowGraphics = false,
    this.showDone = false, this.digestEnabled = true, this.digestMinutes = 540});
  AppSettings copyWith({...}); fromJson; toJson
}
// lib/models/next_move.dart
class NextMove { final Thread thread; final double score; final String reason; /* e.g. "Overdue by 2 days", "Due in 1 day", "Linked to 5 threads" */ }
```

## lib/logic (pure, owned by infra)
```dart
// next_move.dart
List<NextMove> rankNextMoves(List<Thread> threads, Map<String,int> degrees, DateTime now, {int limit = 5});
Thread? findHub(List<Thread> threads, Map<String,int> degrees);              // open thread, highest degree, degree >= 2
List<Thread> findLooseEnds(List<Thread> threads, Map<String,int> degrees);   // open threads with degree 0
Map<String,int> degreeMap(List<WebEdge> edges);
List<Thread> relatedThreads(String id, List<Thread> threads, List<WebEdge> edges); // strongest first
// notification_plan.dart
class PlannedNotification { final int id; final DateTime at; final String title, body, payload; /* payload = threadId or 'digest' */ final bool daily; }
int notificationIdFor(String key);   // positive 31-bit, stable (FNV-1a)
List<PlannedNotification> planNotifications(List<Thread> threads, List<Space> spaces, AppSettings s, DateTime now, {int maxCount = 60});
// one per unsent future reminder of a non-done thread; plus "Due now" at dueAt for threads without reminders; plus the daily digest (id for 'digest', daily:true, at = next occurrence)
// nearest first, capped at maxCount (the OS limits pending notifications; the digest is always kept)
// sync_merge.dart
class SyncState { Map<String,Thread> threads; ... }  // infra decides internals
Thread mergeThread(Thread? local, Thread incoming);                              // last-writer-wins by updatedAt (ties: incoming)
```

## lib/state/app_state.dart (infra) the ONLY thing screens talk to
```dart
enum AuthStatus { unknown, signedOut, signedIn }
enum LinkStatus { live, connecting, offline, syncing }
class NotificationHealth { final bool supported, permissionGranted, exactAlarmAllowed; }

class AppState extends ChangeNotifier {
  Future<void> init();                       // called once by main.dart
  // session
  AuthStatus get authStatus;  UserProfile? get user;  String? get authError;  bool get busy;
  Future<bool> login(String email, String password);
  Future<bool> register({required String email, required String password, required String name});
  Future<void> signOut();   Future<bool> deleteAccount(String password);   Future<void> updateProfile({String? name, String? timezone});
  // data (unmodifiable, threads newest-updated first, spaces by order)
  List<Thread> get threads;  List<Space> get spaces;  Thread? threadById(String id);  Space? spaceById(String id);
  List<WebEdge> get edges;   Map<String,int> get degrees;   Set<String> get flashIds;
  List<ActivityEntry> get activity;   Insights? get insights;
  LinkStatus get link;  int get pendingWrites;  DateTime? get lastSyncAt;
  // mutations: optimistic, persisted, queued for the server
  Thread createThread({required String title, ThreadType type = ThreadType.task, Priority priority = Priority.medium,
      String? spaceId, DateTime? dueAt, List<Reminder> reminders = const [], String notes = ''});
  void saveThread(Thread t);                 // replaces by id and touches updatedAt
  void setStatus(String id, ThreadStatus s);
  Thread? deleteThread(String id);           // returns the removed thread (for Undo)
  void restoreThread(Thread t);
  void toggleChecklist(String id, String itemId);
  void toggleLink(String a, String b);       // explicit link both ways
  Space createSpace(String name, String colorHex);   void saveSpace(Space s);
  Future<String?> deleteSpace(String id, {String? moveTo});   // null = ok, else message
  void reorderSpaces(List<String> orderedIds);
  Future<void> refresh();                    // pull sync + insights + activity
  Future<List<ActivityEntry>> activityFor(String threadId);
  // local derived
  List<NextMove> nextMoves({int limit = 5});  Thread? get hub;  List<Thread> get looseEnds;  List<Thread> relatedTo(String id);
  // settings / server
  AppSettings get settings;  void updateSettings(AppSettings s);  String get serverUrl;  Future<void> setServerUrl(String url);
  // notifications
  NotificationHealth get notificationHealth;  Future<void> requestNotificationPermission();  Future<void> openExactAlarmSettings();
  Future<void> sendTestNotification();  Stream<String> get notificationTaps;   // thread ids to open
  String exportJson();
}
```
`AppState` is provided at the top with `ChangeNotifierProvider<AppState>`; screens use `context.watch<AppState>()` / `context.read<AppState>()` / `Selector`.

## UI entry points (ui)
```dart
// lib/ui/theme.dart
ThemeData buildTheme(Brightness brightness);               // Material 3, brand colours from CONTRACT section 7
// lib/ui/root.dart
class RootGate extends StatelessWidget { const RootGate({super.key}); }   // splash while unknown, AuthScreen when signed out, HomeShell when signed in
Future<void> openThreadEditor(BuildContext context, {String? threadId, String? initialTitle, ThreadType? initialType});
```
`lib/app.dart` (infra): `final GlobalKey<NavigatorState> rootNavigatorKey`; `class SpiderApp` = MaterialApp(navigatorKey: rootNavigatorKey, theme: buildTheme(light),
darkTheme: buildTheme(dark), themeMode from settings, home: RootGate()). `HomeShell` subscribes to `AppState.notificationTaps` and opens the thread editor.
