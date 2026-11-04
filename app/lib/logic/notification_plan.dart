import '../models/misc.dart';
import '../models/space.dart';
import '../models/thread.dart';

class PlannedNotification {
  const PlannedNotification({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
    required this.payload,
    this.daily = false,
  });

  final int id;
  final DateTime at;
  final String title;
  final String body;

  /// A thread id, or 'digest'.
  final String payload;
  final bool daily;
}

/// Stable positive 31-bit id (FNV-1a) so the same reminder always maps to the
/// same OS notification and can be cancelled or replaced.
int notificationIdFor(String key) {
  var h = 0x811c9dc5;
  for (final c in key.codeUnits) {
    h ^= c & 0xff;
    h = (h * 0x01000193) & 0xffffffff;
  }
  final id = h & 0x7fffffff;
  return id == 0 ? 1 : id;
}

String _hm(DateTime local) {
  final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final m = local.minute.toString().padLeft(2, '0');
  return '$h:$m ${local.hour < 12 ? 'AM' : 'PM'}';
}

/// Decides which notifications the OS should hold. Pure: the scheduler only
/// cancels everything it planned before and schedules this list.
List<PlannedNotification> planNotifications(
  List<Thread> threads,
  List<Space> spaces,
  AppSettings settings,
  DateTime now, {
  int maxCount = 60,
}) {
  final clock = now.toUtc();
  final spaceName = <String, String>{for (final s in spaces) s.id: s.name};
  final items = <PlannedNotification>[];
  for (final t in threads) {
    if (t.status == ThreadStatus.done) continue;
    final where = spaceName[t.spaceId] ?? '';
    final dueText = t.dueAt == null ? '' : 'Due ${_hm(t.dueAt!.toLocal())}';
    final body = [where, dueText].where((s) => s.isNotEmpty).join(' - ');
    for (final r in t.reminders) {
      if (r.sentAt != null || !r.at.isAfter(clock)) continue;
      items.add(PlannedNotification(id: notificationIdFor('r:${r.id}'), at: r.at, title: t.title, body: body, payload: t.id));
    }
    final due = t.dueAt;
    if (t.reminders.isEmpty && due != null && due.isAfter(clock)) {
      items.add(PlannedNotification(id: notificationIdFor('d:${t.id}'), at: due, title: 'Due now: ${t.title}', body: where, payload: t.id));
    }
  }
  items.sort((a, b) => a.at.compareTo(b.at));
  final cap = settings.digestEnabled ? maxCount - 1 : maxCount;
  final out = items.length > cap ? items.sublist(0, cap < 0 ? 0 : cap) : items;
  if (!settings.digestEnabled) return out;

  final local = clock.toLocal();
  var next = DateTime(local.year, local.month, local.day, settings.digestMinutes ~/ 60, settings.digestMinutes % 60);
  if (!next.isAfter(local)) next = next.add(const Duration(days: 1));
  final dayStart = DateTime(local.year, local.month, local.day);
  final dayEnd = dayStart.add(const Duration(days: 1));
  final focus = <Thread>[];
  var overdue = 0;
  var today = 0;
  for (final t in threads) {
    final due = t.dueAt;
    if (t.status == ThreadStatus.done || due == null) continue;
    final d = due.toLocal();
    if (d.isBefore(dayStart)) {
      overdue++;
      focus.add(t);
    } else if (d.isBefore(dayEnd)) {
      today++;
      focus.add(t);
    }
  }
  final title = (today + overdue) == 0
      ? 'Your web is clear today'
      : 'Today: $today due${overdue > 0 ? ', $overdue overdue' : ''}';
  final top = focus.take(3).map((t) => t.title).join(' - ');
  out.add(PlannedNotification(
    id: notificationIdFor('digest'),
    at: next,
    title: title,
    body: top.isEmpty ? 'Nothing is due. Capture a new thread?' : top,
    payload: 'digest',
    daily: true,
  ));
  return out;
}
