import 'dart:math' as math;

/// A label the painter would like to draw, already measured in screen pixels.
class LabelCandidate {
  const LabelCandidate({
    required this.id,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.importance,
  });

  final String id;

  /// Top-left corner on screen.
  final double x;
  final double y;
  final double w;
  final double h;

  /// Higher wins when labels collide.
  final double importance;
}

/// How many thread labels may be visible. Fewer when zoomed out so the web
/// stays readable as a structure; more as the user zooms in.
int labelBudget(double zoomLevel) {
  final z = zoomLevel.isFinite ? zoomLevel : 1.0;
  return (4 + 22 * (z - 0.6)).round().clamp(4, 40);
}

/// Greedy, collision-free label selection. Returns ids in priority order.
List<String> pickLabels(
  List<LabelCandidate> candidates, {
  required int budget,
  required double viewWidth,
  required double viewHeight,
  double pad = 4,
}) {
  final sorted = List<LabelCandidate>.of(candidates)
    ..sort((a, b) => b.importance.compareTo(a.importance));
  final placed = <LabelCandidate>[];
  for (final c in sorted) {
    if (placed.length >= budget) break;
    if (c.x < 0 || c.y < 0 || c.x + c.w > viewWidth || c.y + c.h > viewHeight) continue;
    var clash = false;
    for (final p in placed) {
      if (c.x < p.x + p.w + pad && c.x + c.w + pad > p.x && c.y < p.y + p.h + pad && c.y + c.h + pad > p.y) {
        clash = true;
        break;
      }
    }
    if (!clash) placed.add(c);
  }
  return placed.map((c) => c.id).toList();
}

/// Node radius in logical pixels from perspective scale, priority and zoom.
double nodeRadiusPx({required double scale, required int priorityIndex, bool isGoal = false}) {
  final base = 0.46 * scale;
  final bump = 1.0 + 0.18 * (priorityIndex - 1);
  final r = base * bump * (isGoal ? 1.3 : 1.0);
  return math.max(3.5, math.min(r, 34));
}
