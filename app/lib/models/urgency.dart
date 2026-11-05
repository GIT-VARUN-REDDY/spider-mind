import 'thread.dart';

/// Which ring of the web a thread sits on. Inner ring = most urgent.
enum UrgencyBand { now, tomorrow, week, month, nextMonth, year, later, done }

extension UrgencyBandLabel on UrgencyBand {
  String get label {
    switch (this) {
      case UrgencyBand.now:
        return 'NOW';
      case UrgencyBand.tomorrow:
        return 'TOMORROW';
      case UrgencyBand.week:
        return 'THIS WEEK';
      case UrgencyBand.month:
        return 'THIS MONTH';
      case UrgencyBand.nextMonth:
        return 'NEXT MONTH';
      case UrgencyBand.year:
        return 'THIS YEAR';
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

/// Rules:
/// - done -> done ring
/// - doing -> now ring
/// - overdue, due today (dayDiff <= 0), or due within 24h -> now ring
/// - due tomorrow (dayDiff == 1) -> tomorrow ring (shifts to now when today arrives)
/// - due within 7 days -> this week
/// - due in current calendar month -> this month
/// - due in next calendar month -> next month
/// - due later in current calendar year -> this year
/// - otherwise (future year or no due date) -> later
UrgencyBand bandOf(Thread t, DateTime now) {
  if (t.status == ThreadStatus.done) return UrgencyBand.done;
  if (t.status == ThreadStatus.doing) return UrgencyBand.now;
  final due = t.dueAt;
  if (due == null) return UrgencyBand.later;

  final nowLocal = now.toLocal();
  final dueLocal = due.toLocal();

  final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
  final dueDate = DateTime(dueLocal.year, dueLocal.month, dueLocal.day);
  final dayDiff = dueDate.difference(today).inDays;

  // If due is in the past (overdue), due today (dayDiff <= 0), or within 24 hours -> NOW
  if (dayDiff <= 0 || due.difference(now.toUtc()).inHours <= 24) {
    return UrgencyBand.now;
  }

  // Due tomorrow (calendar dayDiff == 1) -> TOMORROW (shifts into NOW when date rolls over)
  if (dayDiff == 1) {
    return UrgencyBand.tomorrow;
  }

  // Due within 7 days -> THIS WEEK
  if (dayDiff <= 7) {
    return UrgencyBand.week;
  }

  // Same calendar month and year -> THIS MONTH
  if (dueLocal.year == nowLocal.year && dueLocal.month == nowLocal.month) {
    return UrgencyBand.month;
  }

  // Next calendar month -> NEXT MONTH
  final nextMonthYear = nowLocal.month == 12 ? nowLocal.year + 1 : nowLocal.year;
  final nextMonth = nowLocal.month == 12 ? 1 : nowLocal.month + 1;
  if (dueLocal.year == nextMonthYear && dueLocal.month == nextMonth) {
    return UrgencyBand.nextMonth;
  }

  // Later in the current calendar year -> THIS YEAR
  if (dueLocal.year == nowLocal.year && dueLocal.isAfter(nowLocal)) {
    return UrgencyBand.year;
  }

  return UrgencyBand.later;
}
