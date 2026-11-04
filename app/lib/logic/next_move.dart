import '../features/web3d/web_edges.dart';
import '../models/misc.dart';
import '../models/thread.dart';

/// Thread id -> number of strands touching it.
Map<String, int> degreeMap(List<WebEdge> edges) {
  final d = <String, int>{};
  for (final e in edges) {
    d[e.a] = (d[e.a] ?? 0) + 1;
    d[e.b] = (d[e.b] ?? 0) + 1;
  }
  return d;
}

/// Ranks open tasks: overdue first, then soon due, then the most connected.
List<NextMove> rankNextMoves(
  List<Thread> threads,
  Map<String, int> degrees,
  DateTime now, {
  int limit = 5,
}) {
  final out = <NextMove>[];
  final clock = now.toUtc();
  for (final t in threads) {
    if (t.type != ThreadType.task || t.status == ThreadStatus.done) continue;
    final deg = degrees[t.id] ?? 0;
    var score = deg * 3.0;
    String? reason;
    final due = t.dueAt;
    if (due != null) {
      final hours = due.difference(clock).inMinutes / 60.0;
      final daysLeft = hours / 24.0;
      if (hours < 0) {
        final overdueDays = (-hours / 24.0).ceil().clamp(1, 100000).toInt();
        score += 100 + overdueDays;
        reason = overdueDays == 1 ? 'Overdue by 1 day' : 'Overdue by $overdueDays days';
      } else if (daysLeft <= 3) {
        score += 40 - 5 * daysLeft;
        reason = hours < 24 ? 'Due within a day' : 'Due in ${daysLeft.ceil()} days';
      } else {
        score += (10 - 0.5 * daysLeft).clamp(0.0, 10.0).toDouble();
      }
    }
    if (t.priority == Priority.high) score += 8;
    if (t.status == ThreadStatus.doing) score += 3;
    reason ??= deg >= 2
        ? 'Linked to $deg threads'
        : t.priority == Priority.high
            ? 'High priority'
            : t.status == ThreadStatus.doing
                ? 'Already in progress'
                : 'Open task';
    out.add(NextMove(thread: t, score: score, reason: reason));
  }
  out.sort((a, b) {
    final c = b.score.compareTo(a.score);
    return c != 0 ? c : a.thread.createdAt.compareTo(b.thread.createdAt);
  });
  return out.length > limit ? out.sublist(0, limit) : out;
}

/// The open thread with the most strands (at least two).
Thread? findHub(List<Thread> threads, Map<String, int> degrees) {
  Thread? best;
  var bestDeg = 1;
  for (final t in threads) {
    if (t.status == ThreadStatus.done) continue;
    final d = degrees[t.id] ?? 0;
    if (d > bestDeg) {
      best = t;
      bestDeg = d;
    }
  }
  return best;
}

/// Open threads that connect to nothing yet.
List<Thread> findLooseEnds(List<Thread> threads, Map<String, int> degrees) =>
    threads.where((t) => t.status != ThreadStatus.done && (degrees[t.id] ?? 0) == 0).toList();

/// Threads connected to [id], strongest strand first.
List<Thread> relatedThreads(String id, List<Thread> threads, List<WebEdge> edges) {
  final byId = <String, Thread>{for (final t in threads) t.id: t};
  final out = <Thread>[];
  for (final e in edges) {
    if (e.a != id && e.b != id) continue;
    final other = byId[e.a == id ? e.b : e.a];
    if (other != null) out.add(other);
  }
  return out;
}
