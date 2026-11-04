import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:spider_mind/data/notifications.dart';
import 'package:spider_mind/data/push.dart';
import 'package:spider_mind/models/space.dart';
import 'package:spider_mind/models/thread.dart';
import 'package:spider_mind/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const space1 = Space(id: 's1', name: 'Work', colorHex: '#32B4FF', order: 0);
  const space2 = Space(id: 's2', name: 'Personal', colorHex: '#FF2A44', order: 1);

  Thread mkThread(String id, {String title = 'Test', String spaceId = 's1', ThreadType type = ThreadType.task, ThreadStatus status = ThreadStatus.todo, DateTime? dueAt, List<String> links = const []}) {
    return Thread(
      id: id,
      title: title,
      spaceId: spaceId,
      type: type,
      status: status,
      priority: Priority.medium,
      dueAt: dueAt,
      links: links,
      keywords: const ['test'],
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
  }

  group('AppState Core Unit Tests', () {
    test('creates, updates and toggles status of threads', () {
      final state = AppState.test(spaces: [space1], threads: []);

      final created = state.createThread(title: 'New spider task', spaceId: 's1', notes: 'Initial notes');
      expect(state.threads, hasLength(1));
      expect(state.threadById(created.id)?.title, 'New spider task');
      expect(state.threadById(created.id)?.notes, 'Initial notes');

      state.setStatus(created.id, ThreadStatus.done);
      expect(state.threadById(created.id)?.status, ThreadStatus.done);
      expect(state.threadById(created.id)?.completedAt, isNotNull);

      state.setStatus(created.id, ThreadStatus.todo);
      expect(state.threadById(created.id)?.status, ThreadStatus.todo);
      expect(state.threadById(created.id)?.completedAt, isNull);
    });

    test('toggles checklist items on a thread', () {
      final initial = mkThread('t1').copyWith(checklist: [
        const ChecklistItem(id: 'c1', text: 'Step 1', done: false),
        const ChecklistItem(id: 'c2', text: 'Step 2', done: true),
      ]);
      final state = AppState.test(spaces: [space1], threads: [initial]);

      state.toggleChecklist('t1', 'c1');
      expect(state.threadById('t1')!.checklist.first.done, isTrue);

      state.toggleChecklist('t1', 'c1');
      expect(state.threadById('t1')!.checklist.first.done, isFalse);
    });

    test('toggles links symmetrically and clears them on thread deletion', () {
      final t1 = mkThread('t1');
      final t2 = mkThread('t2');
      final state = AppState.test(spaces: [space1], threads: [t1, t2]);

      state.toggleLink('t1', 't2');
      expect(state.threadById('t1')!.links, contains('t2'));
      expect(state.threadById('t2')!.links, contains('t1'));

      state.deleteThread('t1');
      expect(state.threadById('t1'), isNull);
      expect(state.threadById('t2')!.links, isNot(contains('t1')));
    });

    test('handles notification action_done and action_snooze events', () {
      final t1 = mkThread('t1', status: ThreadStatus.todo);
      final state = AppState.test(spaces: [space1], threads: [t1]);

      // action_done marks thread done
      state.handleNotificationEventForTest(const NotificationEvent(actionId: 'action_done', payload: 't1'));
      expect(state.threadById('t1')!.status, ThreadStatus.done);

      // action_snooze adds 1h reminder
      state.handleNotificationEventForTest(const NotificationEvent(actionId: 'action_snooze', payload: 't1'));
      expect(state.threadById('t1')!.reminders, isNotEmpty);
      expect(state.threadById('t1')!.reminders.first.at.isAfter(DateTime.now()), isTrue);
    });

    test('space operations: create, reorder and delete', () async {
      final state = AppState.test(spaces: [space1, space2], threads: [mkThread('t1', spaceId: 's1')]);

      final s3 = state.createSpace('Study', '#3DDC97');
      expect(state.spaces, hasLength(3));
      expect(state.spaceById(s3.id)?.name, 'Study');

      state.reorderSpaces([s3.id, space2.id, space1.id]);
      expect(state.spaces.first.id, s3.id);

      // Cannot delete if only 1 space remaining or invalid target
      final deleteErr = await state.deleteSpace('s1', moveTo: null);
      expect(deleteErr, isNotNull);

      // Move threads to s2 and delete s1
      final ok = await state.deleteSpace('s1', moveTo: 's2');
      expect(ok, isNull);
      expect(state.spaceById('s1'), isNull);
      expect(state.threadById('t1')!.spaceId, 's2');
    });

    test('insights metrics and streak calculation', () {
      final now = DateTime.now();
      final tOpen = mkThread('t_open', status: ThreadStatus.todo);
      final tDone = mkThread('t_done', status: ThreadStatus.done).copyWith(completedAt: now);
      final tOverdue = mkThread('t_overdue', status: ThreadStatus.todo, dueAt: now.subtract(const Duration(days: 1)));

      final state = AppState.test(spaces: [space1], threads: [tOpen, tDone, tOverdue]);
      final ins = state.insights;

      expect(ins.counts.total, 3);
      expect(ins.counts.open, 2);
      expect(ins.counts.done, 1);
      expect(ins.counts.overdue, 1);
      expect(ins.streak, greaterThanOrEqualTo(1));
    });

    test('exportJson produces valid JSON payload', () {
      final state = AppState.test(spaces: [space1], threads: [mkThread('t1')]);
      final jsonStr = state.exportJson();
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(decoded.containsKey('exportedAt'), isTrue);
      expect(decoded['spaces'], hasLength(1));
      expect(decoded['threads'], hasLength(1));
    });

    test('graph queries: nextMoves, hub, looseEnds, and relatedTo', () {
      final t1 = mkThread('t1', title: 'Task 1', links: ['t2', 't3']).copyWith(keywords: const ['apple']);
      final t2 = mkThread('t2', title: 'Task 2', links: ['t1']).copyWith(keywords: const ['banana']);
      final t3 = mkThread('t3', title: 'Task 3', links: ['t1']).copyWith(keywords: const ['cherry']);
      final loose = mkThread('loose', title: 'Loose').copyWith(keywords: const ['zebra']);

      final state = AppState.test(spaces: [space1], threads: [t1, t2, t3, loose]);

      expect(state.nextMoves(), isNotEmpty);
      expect(state.hub?.id, 't1');
      expect(state.looseEnds.map((t) => t.id), contains('loose'));
      expect(state.relatedTo('t1').map((t) => t.id), containsAll(['t2', 't3']));
    });

    test('PushService stub works when disabled and records message', () async {
      final push = PushService();
      expect(push.isEnabled, isFalse);
      await push.init();
      expect(push.isInitialized, isFalse);
      await push.handleMessage({'type': 'ping'});
    });
  });
}
