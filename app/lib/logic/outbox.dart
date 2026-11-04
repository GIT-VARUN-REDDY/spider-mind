import 'dart:math' as math;

import '../models/thread.dart';

enum OutboxKind { putThread, deleteThread, putSpace, deleteSpace }

/// One queued write waiting for the server.
class OutboxOp {
  OutboxOp({required this.kind, required this.id, this.body, this.moveTo, this.attempts = 0});

  final OutboxKind kind;
  final String id;
  final Map<String, dynamic>? body;
  final String? moveTo;
  int attempts;

  factory OutboxOp.fromJson(Map<String, dynamic> j) => OutboxOp(
        kind: enumByName(OutboxKind.values, j['kind'], OutboxKind.putThread),
        id: (j['id'] as String?) ?? '',
        body: j['body'] is Map ? Map<String, dynamic>.from(j['body'] as Map) : null,
        moveTo: j['moveTo'] as String?,
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {'kind': kind.name, 'id': id, 'body': body, 'moveTo': moveTo, 'attempts': attempts};
}

/// Appends [next], dropping queued writes it makes pointless: a newer PUT of
/// the same entity replaces the older one, and a DELETE of a thread cancels
/// its queued PUTs (the DELETE itself is kept so the server learns of it).
List<OutboxOp> compactOutbox(List<OutboxOp> queue, OutboxOp next) {
  final out = <OutboxOp>[];
  for (final op in queue) {
    final sameThread = op.id == next.id && (op.kind == OutboxKind.putThread) &&
        (next.kind == OutboxKind.putThread || next.kind == OutboxKind.deleteThread);
    final sameSpace = op.id == next.id && (op.kind == OutboxKind.putSpace) &&
        (next.kind == OutboxKind.putSpace || next.kind == OutboxKind.deleteSpace);
    if (sameThread || sameSpace) continue;
    out.add(op);
  }
  out.add(next);
  return out;
}

/// Retry delay: 2, 4, 8 ... capped at 60 seconds.
Duration backoffFor(int attempts) => Duration(seconds: math.min(60, math.pow(2, attempts.clamp(1, 6)).toInt()));

/// Last-writer-wins by `updatedAt`; ties go to the incoming copy.
Thread mergeThread(Thread? local, Thread incoming) {
  if (local == null) return incoming;
  return incoming.updatedAt.isBefore(local.updatedAt) ? local : incoming;
}
