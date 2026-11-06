import 'thread.dart';

class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.name,
    required this.timezone,
    this.isVerified = false,
  });

  final String id;
  final String email;
  final String name;
  final String timezone;
  final bool isVerified;

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        id: (j['id'] as String?) ?? '',
        email: (j['email'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        timezone: (j['timezone'] as String?) ?? 'UTC',
        isVerified: j['isVerified'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'timezone': timezone,
        'isVerified': isVerified,
      };

  UserProfile copyWith({String? name, String? timezone, bool? isVerified}) =>
      UserProfile(
        id: id,
        email: email,
        name: name ?? this.name,
        timezone: timezone ?? this.timezone,
        isVerified: isVerified ?? this.isVerified,
      );
}

enum ActivityKind { created, updated, status, reminder, linked, deleted }

class ActivityEntry {
  const ActivityEntry({required this.id, required this.kind, required this.threadId, required this.message, required this.at});

  final String id;
  final ActivityKind kind;
  final String threadId;
  final String message;
  final DateTime at;

  factory ActivityEntry.fromJson(Map<String, dynamic> j) => ActivityEntry(
        id: (j['id'] as String?) ?? '',
        kind: enumByName(ActivityKind.values, j['kind'], ActivityKind.updated),
        threadId: (j['threadId'] as String?) ?? '',
        message: (j['message'] as String?) ?? '',
        at: DateTime.tryParse((j['at'] as String?) ?? '')?.toUtc() ?? DateTime.now().toUtc(),
      );
}

class InsightCounts {
  const InsightCounts({this.total = 0, this.open = 0, this.done = 0, this.overdue = 0, this.dueToday = 0, this.dueNext7 = 0});

  final int total;
  final int open;
  final int done;
  final int overdue;
  final int dueToday;
  final int dueNext7;

  factory InsightCounts.fromJson(Map<String, dynamic> j) {
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return InsightCounts(
        total: n('total'), open: n('open'), done: n('done'), overdue: n('overdue'), dueToday: n('dueToday'), dueNext7: n('dueNext7'));
  }
}

class DayCount {
  const DayCount(this.date, this.count);

  /// YYYY-MM-DD in the user's timezone.
  final String date;
  final int count;
}

class Insights {
  const Insights({required this.counts, required this.completedByDay, required this.streak});

  final InsightCounts counts;
  final List<DayCount> completedByDay;
  final int streak;

  factory Insights.fromJson(Map<String, dynamic> j) {
    final days = j['completedByDay'];
    return Insights(
      counts: InsightCounts.fromJson(Map<String, dynamic>.from((j['counts'] as Map?) ?? const {})),
      completedByDay: days is List
          ? days
              .whereType<Map>()
              .map((e) => DayCount((e['date'] as String?) ?? '', (e['count'] as num?)?.toInt() ?? 0))
              .toList()
          : const <DayCount>[],
      streak: (j['streak'] as num?)?.toInt() ?? 0,
    );
  }
}

enum ThemeModeSetting { system, light, dark }

class AppSettings {
  const AppSettings({
    this.theme = ThemeModeSetting.system,
    this.reduceMotion = false,
    this.lowGraphics = false,
    this.showDone = false,
    this.digestEnabled = true,
    this.digestMinutes = 540,
  });

  final ThemeModeSetting theme;
  final bool reduceMotion;
  final bool lowGraphics;
  final bool showDone;
  final bool digestEnabled;

  /// Minutes after local midnight (540 = 09:00).
  final int digestMinutes;

  AppSettings copyWith({
    ThemeModeSetting? theme,
    bool? reduceMotion,
    bool? lowGraphics,
    bool? showDone,
    bool? digestEnabled,
    int? digestMinutes,
  }) =>
      AppSettings(
        theme: theme ?? this.theme,
        reduceMotion: reduceMotion ?? this.reduceMotion,
        lowGraphics: lowGraphics ?? this.lowGraphics,
        showDone: showDone ?? this.showDone,
        digestEnabled: digestEnabled ?? this.digestEnabled,
        digestMinutes: digestMinutes ?? this.digestMinutes,
      );

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        theme: enumByName(ThemeModeSetting.values, j['theme'], ThemeModeSetting.system),
        reduceMotion: j['reduceMotion'] == true,
        lowGraphics: j['lowGraphics'] == true,
        showDone: j['showDone'] == true,
        digestEnabled: j['digestEnabled'] != false,
        digestMinutes: ((j['digestMinutes'] as num?)?.toInt() ?? 540).clamp(0, 1439).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'theme': theme.name,
        'reduceMotion': reduceMotion,
        'lowGraphics': lowGraphics,
        'showDone': showDone,
        'digestEnabled': digestEnabled,
        'digestMinutes': digestMinutes,
      };
}

class NextMove {
  const NextMove({required this.thread, required this.score, required this.reason});

  final Thread thread;
  final double score;
  final String reason;
}
