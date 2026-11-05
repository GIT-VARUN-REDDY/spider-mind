import 'dart:math' as math;
import 'dart:ui' show Color;

import '../../models/space.dart';
import '../../models/thread.dart';
import '../../models/urgency.dart';

/// Id of the synthetic spoke that collects threads whose space is unknown.
const String kUnsortedSpaceId = '__unsorted__';

/// A tiny immutable 3D vector. World axes: x to the right, y "up the page"
/// (towards the first spoke) and z towards the viewer (priority depth).
class Vec3 {
  const Vec3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  static const Vec3 zero = Vec3(0, 0, 0);

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 scaled(double k) => Vec3(x * k, y * k, z * k);

  double get length => math.sqrt(x * x + y * y + z * z);

  static Vec3 lerp(Vec3 a, Vec3 b, double t) =>
      Vec3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t);

  @override
  bool operator ==(Object other) =>
      other is Vec3 && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'Vec3($x, $y, $z)';
}

/// Spacing constants of the web (world units).
class WebMetrics {
  WebMetrics._();

  /// Distance between two neighbours in a row (and between rows).
  static const double slotGap = 1.25;
  static const double rowGap = 1.25;

  /// Free radial space between the last row of one ring and the next ring.
  static const double bandGap = 2.1;

  /// Radius of the innermost ring (at least).
  static const double minInnerRadius = 4.0;

  /// z distance per priority step: z = (priority.index - 1) * zStep.
  static const double zStep = 0.8;

  /// Threads per row of a cell.
  static const int rowSize = 3;
}

/// One spoke = one space.
class WebSpoke {
  const WebSpoke({
    required this.spaceId,
    required this.name,
    required this.color,
    required this.angle,
    required this.index,
    this.synthetic = false,
  });

  final String spaceId;
  final String name;
  final Color color;

  /// Contract angle: -pi/2 + 2*pi*i/S. Position on the web plane is
  /// (r*cos(angle), -r*sin(angle)) so that spoke 0 points up the screen and
  /// the order runs clockwise.
  final double angle;
  final int index;
  final bool synthetic;
}

/// One concentric ring = one urgency band.
class WebRing {
  const WebRing({
    required this.band,
    required this.radius,
    required this.extent,
    required this.rows,
  });

  final UrgencyBand band;

  /// Radius of the ring line (first row of nodes sits on it).
  final double radius;

  /// Radius of the outermost row of this band.
  final double extent;

  /// Number of node rows needed by the fullest cell (at least 1).
  final int rows;
}

/// Layout result for one thread.
class WebNode {
  const WebNode({
    required this.id,
    required this.position,
    required this.band,
    required this.spokeIndex,
    required this.row,
    required this.col,
  });

  final String id;
  final Vec3 position;
  final UrgencyBand band;
  final int spokeIndex;
  final int row;
  final int col;
}

/// Pure, deterministic layout of the structured web.
class WebLayout {
  const WebLayout({
    required this.nodes,
    required this.spokes,
    required this.rings,
    required this.outerRadius,
  });

  final Map<String, WebNode> nodes;
  final List<WebSpoke> spokes;
  final List<WebRing> rings;

  /// Radius of the spokes (the whole web fits inside this circle).
  final double outerRadius;

  int get nodeCount => nodes.length;

  Vec3? positionOf(String id) => nodes[id]?.position;

  Map<String, Vec3> get positions =>
      <String, Vec3>{for (final e in nodes.entries) e.key: e.value.position};

  /// Angle (contract convention) of the label gap used for ring labels.
  double get ringLabelAngle {
    final s = spokes.isEmpty ? 1 : spokes.length;
    return -math.pi / 2 - math.pi / s;
  }

  static const WebLayout empty = WebLayout(
    nodes: <String, WebNode>{},
    spokes: <WebSpoke>[],
    rings: <WebRing>[],
    outerRadius: 10,
  );

  /// World x for a polar position (angle in contract convention).
  static double worldX(double radius, double angle) => radius * math.cos(angle);

  /// World y for a polar position (angle in contract convention).
  static double worldY(double radius, double angle) => -radius * math.sin(angle);

  static int _cellCompare(Thread a, Thread b) {
    final p = b.priority.index.compareTo(a.priority.index);
    if (p != 0) return p;
    final ad = a.dueAt;
    final bd = b.dueAt;
    if (ad != null && bd != null) {
      final c = ad.compareTo(bd);
      if (c != 0) return c;
    } else if (ad != null) {
      return -1;
    } else if (bd != null) {
      return 1;
    }
    final c = a.createdAt.compareTo(b.createdAt);
    if (c != 0) return c;
    return a.id.compareTo(b.id);
  }

  static WebLayout compute({
    required List<Thread> threads,
    required List<Space> spaces,
    DateTime? now,
    bool showDone = false,
    Set<String> hiddenSpaceIds = const <String>{},
  }) {
    final clock = (now ?? DateTime.now()).toUtc();

    // Spokes: spaces ordered by `order`, hidden ones removed.
    final ordered = List<Space>.of(spaces)
      ..sort((a, b) {
        final c = a.order.compareTo(b.order);
        if (c != 0) return c;
        final n = a.name.compareTo(b.name);
        if (n != 0) return n;
        return a.id.compareTo(b.id);
      });
    final knownIds = <String>{for (final s in spaces) s.id};
    final shown = <Space>[
      for (final s in ordered)
        if (!hiddenSpaceIds.contains(s.id)) s
    ];
    final spokeOfSpace = <String, int>{};
    for (var i = 0; i < shown.length; i++) {
      spokeOfSpace.putIfAbsent(shown[i].id, () => i);
    }

    // Decide which threads are visible, in which spoke and band.
    final unsortedIndex = shown.length;
    var hasUnsorted = false;
    final visible = <Thread>[];
    final visSpoke = <int>[];
    final visBand = <UrgencyBand>[];
    for (final t in threads) {
      int spoke;
      if (knownIds.contains(t.spaceId)) {
        final s = spokeOfSpace[t.spaceId];
        if (s == null) continue; // hidden space
        spoke = s;
      } else {
        if (hiddenSpaceIds.contains(kUnsortedSpaceId)) continue;
        spoke = unsortedIndex;
        hasUnsorted = true;
      }
      final band = bandOf(t, clock);
      if (band == UrgencyBand.done && !showDone) continue;
      visible.add(t);
      visSpoke.add(spoke);
      visBand.add(band);
    }

    final spokeCount = shown.length + (hasUnsorted ? 1 : 0);
    final s = math.max(1, spokeCount);

    final spokes = <WebSpoke>[];
    for (var i = 0; i < spokeCount; i++) {
      final angle = -math.pi / 2 + 2 * math.pi * i / s;
      if (i < shown.length) {
        spokes.add(WebSpoke(
          spaceId: shown[i].id,
          name: shown[i].name,
          color: shown[i].color,
          angle: angle,
          index: i,
        ));
      } else {
        spokes.add(WebSpoke(
          spaceId: kUnsortedSpaceId,
          name: 'Unsorted',
          color: const Color(0xFF8A94A6),
          angle: angle,
          index: i,
          synthetic: true,
        ));
      }
    }

    // Bucket threads into cells (spoke, band).
    final bandList = <UrgencyBand>[
      UrgencyBand.now,
      UrgencyBand.week,
      UrgencyBand.month,
      UrgencyBand.nextMonth,
      UrgencyBand.year,
      UrgencyBand.later,
      if (showDone) UrgencyBand.done,
    ];
    final cells = <int, List<Thread>>{};
    for (var i = 0; i < visible.length; i++) {
      final key = visSpoke[i] * 16 + visBand[i].index;
      cells.putIfAbsent(key, () => <Thread>[]).add(visible[i]);
    }
    final maxRows = <int, int>{}; // band index -> rows
    for (final e in cells.entries) {
      e.value.sort(_cellCompare);
      final band = e.key % 16;
      final rows = (e.value.length + WebMetrics.rowSize - 1) ~/ WebMetrics.rowSize;
      final cur = maxRows[band] ?? 0;
      if (rows > cur) maxRows[band] = rows;
    }

    // Dynamic ring radii.
    final rings = <WebRing>[];
    var radius = math.max(
      WebMetrics.minInnerRadius,
      0.62 * s * WebMetrics.slotGap,
    );
    for (final band in bandList) {
      final rows = math.max(1, maxRows[band.index] ?? 0);
      final extent = radius + (rows - 1) * WebMetrics.rowGap;
      rings.add(WebRing(band: band, radius: radius, extent: extent, rows: rows));
      radius = extent + WebMetrics.bandGap;
    }
    final outer = rings.last.extent + 2.4;

    final ringOfBand = <int, WebRing>{for (final r in rings) r.band.index: r};

    // Node positions.
    final nodes = <String, WebNode>{};
    final cellKeys = cells.keys.toList()..sort();
    for (final key in cellKeys) {
      final list = cells[key]!;
      final spokeIdx = key ~/ 16;
      final bandIdx = key % 16;
      final ring = ringOfBand[bandIdx];
      if (ring == null || spokeIdx >= spokes.length) continue;
      final spokeAngle = spokes[spokeIdx].angle;
      for (var i = 0; i < list.length; i++) {
        final t = list[i];
        final row = i ~/ WebMetrics.rowSize;
        final col = i % WebMetrics.rowSize;
        final inRow = math.min(
          WebMetrics.rowSize,
          list.length - row * WebMetrics.rowSize,
        );
        final lateral = col - (inRow - 1) / 2.0;
        final r = ring.radius + row * WebMetrics.rowGap;
        final maxOff = 0.7 * math.pi / s;
        final off = math.min(WebMetrics.slotGap / r, maxOff);
        final angle = spokeAngle + lateral * off;
        final z = (t.priority.index - 1) * WebMetrics.zStep;
        nodes[t.id] = WebNode(
          id: t.id,
          position: Vec3(worldX(r, angle), worldY(r, angle), z),
          band: ring.band,
          spokeIndex: spokeIdx,
          row: row,
          col: col,
        );
      }
    }

    return WebLayout(
      nodes: nodes,
      spokes: spokes,
      rings: rings,
      outerRadius: outer,
    );
  }
}
