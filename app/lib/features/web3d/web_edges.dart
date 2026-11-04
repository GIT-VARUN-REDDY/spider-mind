import '../../models/thread.dart';

/// A connection between two threads, drawn as a silk strand in the web.
class WebEdge {
  const WebEdge({
    required this.a,
    required this.b,
    required this.weight,
    required this.explicit,
    this.via = const [],
  });

  /// Thread ids, always ordered so that a.compareTo(b) < 0.
  final String a;
  final String b;

  /// 1 for a single shared keyword, +1 per extra keyword; explicit links
  /// count as 3 (plus shared keywords).
  final double weight;

  /// True when the user linked the two threads by hand.
  final bool explicit;

  /// Shared keywords (empty for a purely manual link).
  final List<String> via;

  String get key => '$a|$b';
}

/// Builds the undirected edge list from explicit links and shared keywords.
/// Unknown ids are ignored. O(n^2) in the worst case; n is capped at 1000.
List<WebEdge> buildWebEdges(List<Thread> threads) {
  final byId = <String, Thread>{for (final t in threads) t.id: t};
  final explicit = <String>{};
  for (final t in threads) {
    for (final l in t.links) {
      if (l == t.id || !byId.containsKey(l)) continue;
      explicit.add(t.id.compareTo(l) < 0 ? '${t.id}|$l' : '$l|${t.id}');
    }
  }

  // Inverted index keyword -> thread ids keeps this fast for big webs.
  final index = <String, List<String>>{};
  for (final t in threads) {
    for (final k in t.keywords.toSet()) {
      index.putIfAbsent(k, () => []).add(t.id);
    }
  }
  final shared = <String, List<String>>{};
  index.forEach((kw, ids) {
    if (ids.length < 2 || ids.length > 60) return; // ignore ultra-common words
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        final x = ids[i], y = ids[j];
        final key = x.compareTo(y) < 0 ? '$x|$y' : '$y|$x';
        shared.putIfAbsent(key, () => []).add(kw);
      }
    }
  });

  final keys = <String>{...explicit, ...shared.keys};
  final edges = <WebEdge>[];
  for (final key in keys) {
    final parts = key.split('|');
    final via = shared[key] ?? const <String>[];
    final isExplicit = explicit.contains(key);
    edges.add(WebEdge(
      a: parts[0],
      b: parts[1],
      weight: via.length + (isExplicit ? 3 : 0).toDouble(),
      explicit: isExplicit,
      via: via,
    ));
  }
  edges.sort((p, q) => q.weight.compareTo(p.weight));
  return edges;
}
