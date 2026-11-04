import 'dart:math';

/// What kind of thought a thread is. Drives the node SHAPE in the 3D web.
enum ThreadType { idea, task, question, goal }

/// Progress state. Drives the node FILL in the 3D web.
enum ThreadStatus { todo, doing, done }

/// Importance. Drives node SIZE and DEPTH in the 3D web.
enum Priority { low, medium, high }

T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

final Random _rng = Random();

/// Generates a 24-hex-character id that MongoDB accepts as an ObjectId.
/// Clients create ids themselves so creating threads works offline and the
/// server upsert (PUT) is idempotent.
String newObjectId() {
  final secs = (DateTime.now().millisecondsSinceEpoch ~/ 1000)
      .toRadixString(16)
      .padLeft(8, '0');
  final sb = StringBuffer(secs);
  for (var i = 0; i < 16; i++) {
    sb.write(_rng.nextInt(16).toRadixString(16));
  }
  return sb.toString();
}

DateTime? _parseDate(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toUtc() : null;

class Reminder {
  const Reminder({required this.id, required this.at, this.sentAt});

  final String id;

  /// Absolute instant (UTC) when the reminder fires.
  final DateTime at;

  /// Set by the server once the reminder was delivered.
  final DateTime? sentAt;

  factory Reminder.create(DateTime at) =>
      Reminder(id: newObjectId(), at: at.toUtc());

  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
        id: j['id'] as String,
        at: DateTime.parse(j['at'] as String).toUtc(),
        sentAt: _parseDate(j['sentAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': at.toUtc().toIso8601String(),
      };

  Reminder copyWith({DateTime? at}) =>
      Reminder(id: id, at: at?.toUtc() ?? this.at, sentAt: at == null ? sentAt : null);
}

class ChecklistItem {
  const ChecklistItem({required this.id, required this.text, this.done = false});

  final String id;
  final String text;
  final bool done;

  factory ChecklistItem.create(String text) =>
      ChecklistItem(id: newObjectId(), text: text);

  factory ChecklistItem.fromJson(Map<String, dynamic> j) => ChecklistItem(
        id: j['id'] as String,
        text: (j['text'] as String?) ?? '',
        done: j['done'] == true,
      );

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'done': done};

  ChecklistItem copyWith({String? text, bool? done}) =>
      ChecklistItem(id: id, text: text ?? this.text, done: done ?? this.done);
}

class Thread {
  const Thread({
    required this.id,
    required this.title,
    required this.spaceId,
    required this.createdAt,
    required this.updatedAt,
    this.notes = '',
    this.type = ThreadType.task,
    this.status = ThreadStatus.todo,
    this.priority = Priority.medium,
    this.dueAt,
    this.reminders = const [],
    this.tags = const [],
    this.keywords = const [],
    this.links = const [],
    this.checklist = const [],
    this.completedAt,
  });

  final String id;
  final String title;
  final String notes;
  final ThreadType type;
  final ThreadStatus status;
  final Priority priority;
  final String spaceId;
  final DateTime? dueAt;
  final List<Reminder> reminders;

  /// Tags typed by the user.
  final List<String> tags;

  /// Key words derived by the server from title, notes and tags. Two threads
  /// that share a keyword get an automatic (weak) link in the web.
  final List<String> keywords;

  /// Explicit links to other thread ids, chosen by the user (strong links).
  final List<String> links;
  final List<ChecklistItem> checklist;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  bool get isDone => status == ThreadStatus.done;

  /// 0..1. Uses the checklist when there is one, otherwise done/not done.
  double get progress {
    if (checklist.isEmpty) return isDone ? 1 : 0;
    final done = checklist.where((c) => c.done).length;
    return done / checklist.length;
  }

  factory Thread.draft({
    required String title,
    required String spaceId,
    ThreadType type = ThreadType.task,
    Priority priority = Priority.medium,
    DateTime? dueAt,
    List<Reminder> reminders = const [],
  }) {
    final now = DateTime.now().toUtc();
    return Thread(
      id: newObjectId(),
      title: title,
      spaceId: spaceId,
      type: type,
      priority: priority,
      dueAt: dueAt?.toUtc(),
      reminders: reminders,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory Thread.fromJson(Map<String, dynamic> j) {
    List<T> list<T>(Object? v, T Function(Map<String, dynamic>) f) => v is List
        ? v.whereType<Map>().map((e) => f(Map<String, dynamic>.from(e))).toList()
        : <T>[];
    List<String> strings(Object? v) =>
        v is List ? v.whereType<String>().toList() : <String>[];
    return Thread(
      id: j['id'] as String,
      title: (j['title'] as String?) ?? '',
      notes: (j['notes'] as String?) ?? '',
      type: enumByName(ThreadType.values, j['type'], ThreadType.task),
      status: enumByName(ThreadStatus.values, j['status'], ThreadStatus.todo),
      priority: enumByName(Priority.values, j['priority'], Priority.medium),
      spaceId: (j['spaceId'] as String?) ?? '',
      dueAt: _parseDate(j['dueAt']),
      reminders: list(j['reminders'], Reminder.fromJson),
      tags: strings(j['tags']),
      keywords: strings(j['keywords']),
      links: strings(j['links']),
      checklist: list(j['checklist'], ChecklistItem.fromJson),
      createdAt: _parseDate(j['createdAt']) ?? DateTime.now().toUtc(),
      updatedAt: _parseDate(j['updatedAt']) ?? DateTime.now().toUtc(),
      completedAt: _parseDate(j['completedAt']),
    );
  }

  /// Body for PUT /threads/:id (keywords and sentAt are server-owned).
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'notes': notes,
        'type': type.name,
        'status': status.name,
        'priority': priority.name,
        'spaceId': spaceId,
        'dueAt': dueAt?.toUtc().toIso8601String(),
        'reminders': reminders.map((r) => r.toJson()).toList(),
        'tags': tags,
        'links': links,
        'checklist': checklist.map((c) => c.toJson()).toList(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  /// Full local-cache form (includes server-owned fields).
  Map<String, dynamic> toCacheJson() => {
        ...toJson(),
        'keywords': keywords,
        'completedAt': completedAt?.toUtc().toIso8601String(),
        'reminders': reminders
            .map((r) => {...r.toJson(), 'sentAt': r.sentAt?.toUtc().toIso8601String()})
            .toList(),
      };

  Thread copyWith({
    String? title,
    String? notes,
    ThreadType? type,
    ThreadStatus? status,
    Priority? priority,
    String? spaceId,
    DateTime? dueAt,
    bool clearDueAt = false,
    List<Reminder>? reminders,
    List<String>? tags,
    List<String>? keywords,
    List<String>? links,
    List<ChecklistItem>? checklist,
    DateTime? updatedAt,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) {
    final nextStatus = status ?? this.status;
    return Thread(
      id: id,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      type: type ?? this.type,
      status: nextStatus,
      priority: priority ?? this.priority,
      spaceId: spaceId ?? this.spaceId,
      dueAt: clearDueAt ? null : (dueAt?.toUtc() ?? this.dueAt),
      reminders: reminders ?? this.reminders,
      tags: tags ?? this.tags,
      keywords: keywords ?? this.keywords,
      links: links ?? this.links,
      checklist: checklist ?? this.checklist,
      createdAt: createdAt,
      updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
      completedAt: clearCompletedAt
          ? null
          : (completedAt?.toUtc() ??
              (nextStatus == ThreadStatus.done && this.status != ThreadStatus.done
                  ? DateTime.now().toUtc()
                  : (nextStatus == ThreadStatus.done ? this.completedAt : null))),
    );
  }
}
