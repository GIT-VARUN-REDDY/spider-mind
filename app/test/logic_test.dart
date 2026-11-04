import 'package:flutter_test/flutter_test.dart';
import 'package:spider_mind/features/web3d/web_edges.dart';
import 'package:spider_mind/logic/next_move.dart';
import 'package:spider_mind/logic/notification_plan.dart';
import 'package:spider_mind/logic/outbox.dart';
import 'package:spider_mind/models/misc.dart';
import 'package:spider_mind/models/space.dart';
import 'package:spider_mind/models/thread.dart';

final DateTime now = DateTime.utc(2026, 11, 4, 10);

Thread mk(String id, {String? title, DateTime? due, ThreadStatus status = ThreadStatus.todo, Priority p = Priority.medium, List<String> kw = const [], List<String> links = const [], List<Reminder> rem = const [], ThreadType type = ThreadType.task}) =>
    Thread(
        id: 'a'.padRight(24 - id.length, '0') + id,
        title: title ?? 'Thread $id',
        spaceId: 's1',
        createdAt: now.subtract(const Duration(days: 3)),
        updatedAt: now,
        dueAt: due,
        status: status,
        priority: p,
        keywords: kw,
        links: links,
        reminders: rem,
        type: type);

void main() {
  group('edges and degrees', () {
    test('shared keyword and explicit link', () {
      final a = mk('a', kw: ['portfolio']);
      final b = mk('b', kw: ['portfolio'], links: [mk('c').id]);
      final c = mk('c');
      final edges = buildWebEdges([a, b, c]);
      expect(edges, hasLength(2));
      final d = degreeMap(edges);
      expect(d[b.id], 2);
      expect(d[a.id], 1);
    });
  });

  group('next move', () {
    test('overdue beats connected beats plain', () {
      final overdue = mk('a', due: now.subtract(const Duration(days: 2)));
      final linked = mk('b');
      final plain = mk('c');
      final moves = rankNextMoves([plain, linked, overdue], {linked.id: 4}, now);
      expect(moves.first.thread.id, overdue.id);
      expect(moves.first.reason, 'Overdue by 2 days');
      expect(moves[1].thread.id, linked.id);
      expect(moves[1].reason, 'Linked to 4 threads');
    });
    test('ignores done threads and non tasks; honours limit', () {
      final ts = [mk('a', status: ThreadStatus.done), mk('b', type: ThreadType.idea), mk('c'), mk('d'), mk('e')];
      expect(rankNextMoves(ts, {}, now, limit: 2), hasLength(2));
      expect(rankNextMoves(ts.sublist(0, 2), {}, now), isEmpty);
    });
    test('hub needs at least two strands; loose ends have none', () {
      final a = mk('a'), b = mk('b'), c = mk('c');
      expect(findHub([a, b, c], {a.id: 1, b.id: 1}), isNull);
      expect(findHub([a, b, c], {a.id: 3, b.id: 2})!.id, a.id);
      expect(findLooseEnds([a, b, c], {a.id: 1}).map((t) => t.id), unorderedEquals([b.id, c.id]));
    });
  });

  group('notification plan', () {
    const settings = AppSettings(digestEnabled: false);
    test('id is stable and positive', () {
      expect(notificationIdFor('r:abc'), notificationIdFor('r:abc'));
      expect(notificationIdFor('r:abc'), isNot(notificationIdFor('r:abd')));
      expect(notificationIdFor('x'), greaterThan(0));
      expect(notificationIdFor('x'), lessThan(0x80000000));
    });
    test('plans future unsent reminders only, nearest first', () {
      final soon = Reminder(id: 'r1'.padRight(24, '0'), at: now.add(const Duration(hours: 1)));
      final later = Reminder(id: 'r2'.padRight(24, '0'), at: now.add(const Duration(days: 1)));
      final past = Reminder(id: 'r3'.padRight(24, '0'), at: now.subtract(const Duration(hours: 1)));
      final sent = Reminder(id: 'r4'.padRight(24, '0'), at: now.add(const Duration(hours: 2)), sentAt: now);
      final t = mk('a', rem: [later, soon, past, sent]);
      final plan = planNotifications([t], [], settings, now);
      expect(plan.map((p) => p.at), orderedEquals([soon.at, later.at]));
    });
    test('done threads are skipped; due-now only without reminders', () {
      final done = mk('a', status: ThreadStatus.done, due: now.add(const Duration(hours: 3)));
      final withDue = mk('b', due: now.add(const Duration(hours: 3)));
      final withRem = mk('c', due: now.add(const Duration(hours: 3)), rem: [Reminder(id: 'r9'.padRight(24, '0'), at: now.add(const Duration(hours: 2)))]);
      final plan = planNotifications([done, withDue, withRem], [], settings, now);
      expect(plan, hasLength(2));
      expect(plan.any((p) => p.title.startsWith('Due now')), isTrue);
    });
    test('digest is daily, in the future, and the cap keeps it', () {
      final many = [
        for (var i = 0; i < 100; i++) mk('t$i', due: now.add(Duration(hours: 2 + i)))
      ];
      final plan = planNotifications(many, [], const AppSettings(), now, maxCount: 10);
      expect(plan, hasLength(10));
      final digest = plan.last;
      expect(digest.daily, isTrue);
      expect(digest.payload, 'digest');
      expect(digest.at.isAfter(now.toLocal()), isTrue);
    });
  });

  group('outbox and merge', () {
    test('later PUT replaces earlier; DELETE cancels queued PUT', () {
      var q = <OutboxOp>[];
      q = compactOutbox(q, OutboxOp(kind: OutboxKind.putThread, id: 'a', body: {'v': 1}));
      q = compactOutbox(q, OutboxOp(kind: OutboxKind.putThread, id: 'b', body: {'v': 1}));
      q = compactOutbox(q, OutboxOp(kind: OutboxKind.putThread, id: 'a', body: {'v': 2}));
      expect(q.map((o) => o.id), orderedEquals(['b', 'a']));
      expect(q.last.body!['v'], 2);
      q = compactOutbox(q, OutboxOp(kind: OutboxKind.deleteThread, id: 'a'));
      expect(q.map((o) => '${o.kind.name}:${o.id}'), orderedEquals(['putThread:b', 'deleteThread:a']));

      var sq = <OutboxOp>[];
      sq = compactOutbox(sq, OutboxOp(kind: OutboxKind.putSpace, id: 's1', body: {'name': 'Old'}));
      sq = compactOutbox(sq, OutboxOp(kind: OutboxKind.putSpace, id: 's2', body: {'name': 'Keep'}));
      sq = compactOutbox(sq, OutboxOp(kind: OutboxKind.putSpace, id: 's1', body: {'name': 'New'}));
      expect(sq.map((o) => o.id), orderedEquals(['s2', 's1']));
      expect(sq.last.body!['name'], 'New');
      sq = compactOutbox(sq, OutboxOp(kind: OutboxKind.deleteSpace, id: 's1'));
      expect(sq.map((o) => '${o.kind.name}:${o.id}'), orderedEquals(['putSpace:s2', 'deleteSpace:s1']));
    });
    test('backoff grows and caps', () {
      expect(backoffFor(1).inSeconds, 2);
      expect(backoffFor(3).inSeconds, 8);
      expect(backoffFor(20).inSeconds, 60);
    });
    test('last writer wins, ties go to incoming', () {
      final older = mk('a', title: 'old').copyWith(updatedAt: now.subtract(const Duration(minutes: 5)));
      final newer = mk('a', title: 'new');
      expect(mergeThread(newer, older).title, 'new');
      expect(mergeThread(older, newer).title, 'new');
      expect(mergeThread(null, older).title, 'old');
    });
  });

  group('models', () {
    test('thread json round trip', () {
      final t = mk('a', due: now, rem: [Reminder(id: 'r1'.padRight(24, '0'), at: now)]);
      final back = Thread.fromJson(t.toCacheJson());
      expect(back.id, t.id);
      expect(back.reminders.single.at, now);
      expect(back.dueAt, now);
    });
    test('settings json round trip', () {
      const s = AppSettings(theme: ThemeModeSetting.dark, digestMinutes: 600, lowGraphics: true);
      final back = AppSettings.fromJson(s.toJson());
      expect(back.theme, ThemeModeSetting.dark);
      expect(back.digestMinutes, 600);
      expect(back.lowGraphics, isTrue);
    });
    test('space colour parses', () {
      expect(Space.create('Work', '#32B4FF', 0).color.toARGB32(), 0xFF32B4FF);
    });
  });
}
