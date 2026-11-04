import 'thread.dart';

/// Which ring of the web a thread sits on. Inner ring = most urgent.
enum UrgencyBand { now, week, month, later, done }

extension UrgencyBandLabel on UrgencyBand {
  String get label {
    switch (this) {
      case UrgencyBand.now:
        return 'NOW';
      case UrgencyBand.week:
        return 'THIS WEEK';
      case UrgencyBand.month:
        return 'THIS MONTH';
      case UrgencyBand.later:
        return 'LATER';
      case UrgencyBand.done:
        return 'DONE';
    }
  }
}

bool isOverdue(Thread t, DateTime now) =>
    t.status != ThreadStatus.done &&
    t.dueAt != null &&
    t.dueAt!.isBefore(now.toUtc());

/// Rules: done -> done ring; in progress -> now; due within 24h (or overdue)
/// -> now; within 7 days -> week; within 30 days -> month; otherwise later.
UrgencyBand bandOf(Thread t, DateTime now) {
  if (t.status == ThreadStatus.done) return UrgencyBand.done;
  if (t.status == ThreadStatus.doing) return UrgencyBand.now;
  final due = t.dueAt;
  if (due == null) return UrgencyBand.later;
  final hours = due.difference(now.toUtc()).inHours;
  if (hours <= 24) return UrgencyBand.now;
  if (hours <= 24 * 7) return UrgencyBand.week;
  if (hours <= 24 * 30) return UrgencyBand.month;
  return UrgencyBand.later;
}
