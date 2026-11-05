import 'package:flutter_test/flutter_test.dart';
import 'package:spider_mind/models/thread.dart';
import 'package:spider_mind/models/urgency.dart';

void main() {
  group('UrgencyBand Calendar Tests', () {
    test('Labels are correct', () {
      expect(UrgencyBand.now.label, 'NOW');
      expect(UrgencyBand.tomorrow.label, 'TOMORROW');
      expect(UrgencyBand.week.label, 'THIS WEEK');
      expect(UrgencyBand.month.label, 'THIS MONTH');
      expect(UrgencyBand.nextMonth.label, 'NEXT MONTH');
      expect(UrgencyBand.year.label, 'THIS YEAR');
      expect(UrgencyBand.later.label, 'LATER');
      expect(UrgencyBand.done.label, 'DONE');
    });

    test('bandOf maps correctly according to the calendar', () {
      final now = DateTime.utc(2026, 3, 10, 12, 0); // March 10, 2026

      Thread makeThread(DateTime? dueAt, {ThreadStatus status = ThreadStatus.todo}) {
        return Thread(
          id: 'test-1',
          title: 'Test Thread',
          spaceId: 's1',
          type: ThreadType.task,
          priority: Priority.medium,
          status: status,
          dueAt: dueAt,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        );
      }

      // Done status -> done ring
      expect(bandOf(makeThread(null, status: ThreadStatus.done), now), UrgencyBand.done);

      // Doing status -> now ring
      expect(bandOf(makeThread(null, status: ThreadStatus.doing), now), UrgencyBand.now);

      // No due date -> later ring
      expect(bandOf(makeThread(null), now), UrgencyBand.later);

      // Due in 12 hours (same calendar day or <24h) -> now
      expect(bandOf(makeThread(now.add(const Duration(hours: 12))), now), UrgencyBand.now);

      // Due tomorrow (March 11) -> tomorrow
      expect(bandOf(makeThread(DateTime.utc(2026, 3, 11, 15, 0)), now), UrgencyBand.tomorrow);

      // Due in 4 days (March 14) -> this week
      expect(bandOf(makeThread(now.add(const Duration(days: 4))), now), UrgencyBand.week);

      // Due in 15 days (March 25, same month) -> this month
      expect(bandOf(makeThread(DateTime.utc(2026, 3, 25)), now), UrgencyBand.month);

      // Due next month (April 15, 2026) -> next month
      expect(bandOf(makeThread(DateTime.utc(2026, 4, 15)), now), UrgencyBand.nextMonth);

      // Due later this year (August 20, 2026) -> this year
      expect(bandOf(makeThread(DateTime.utc(2026, 8, 20)), now), UrgencyBand.year);

      // Due next year (January 10, 2027) -> later
      expect(bandOf(makeThread(DateTime.utc(2027, 1, 10)), now), UrgencyBand.later);
    });

    test('Shifts thread from tomorrow to now as day advances', () {
      final taskDueNov5 = Thread(
        id: 'shift-task',
        title: 'Task due Nov 5',
        spaceId: 's1',
        type: ThreadType.task,
        priority: Priority.medium,
        status: ThreadStatus.todo,
        dueAt: DateTime.utc(2026, 11, 5, 17, 0),
        createdAt: DateTime.utc(2026, 11, 1),
        updatedAt: DateTime.utc(2026, 11, 1),
      );

      // Yesterday: Nov 4 -> The task is scheduled for TOMORROW
      final yesterday = DateTime.utc(2026, 11, 4, 14, 0);
      expect(bandOf(taskDueNov5, yesterday), UrgencyBand.tomorrow);

      // Today: Nov 5 -> The task is now scheduled for TODAY / NOW
      final today = DateTime.utc(2026, 11, 5, 9, 0);
      expect(bandOf(taskDueNov5, today), UrgencyBand.now);

      // Tomorrow: Nov 6 -> The task is now overdue -> still stays in NOW
      final tomorrow = DateTime.utc(2026, 11, 6, 9, 0);
      expect(bandOf(taskDueNov5, tomorrow), UrgencyBand.now);
    });

    test('December boundary transitions to next year correctly for nextMonth', () {
      final now = DateTime.utc(2026, 12, 1, 12, 0); // December 1, 2026

      Thread makeThread(DateTime dueAt) {
        return Thread(
          id: 'test-2',
          title: 'Year end task',
          spaceId: 's1',
          type: ThreadType.task,
          priority: Priority.medium,
          status: ThreadStatus.todo,
          dueAt: dueAt,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        );
      }

      // Due in December (e.g. Dec 25) -> this month
      expect(bandOf(makeThread(DateTime.utc(2026, 12, 25)), now), UrgencyBand.month);

      // Due in January 2027 -> next month
      expect(bandOf(makeThread(DateTime.utc(2027, 1, 15)), now), UrgencyBand.nextMonth);

      // Due in March 2027 -> later
      expect(bandOf(makeThread(DateTime.utc(2027, 3, 10)), now), UrgencyBand.later);
    });
  });
}
