import 'dart:math' as math;

import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import '../../models/thread.dart';
import '../../models/urgency.dart';
import 'web_camera.dart';
import 'web_edges.dart';
import 'web_layout.dart';
import 'web_lod.dart';

/// Everything the painter needs for one frame. Mutated by the view.
class WebScene {
  WebLayout layout = WebLayout.empty;
  List<WebEdge> edges = const [];
  Map<String, Thread> byId = const {};
  String? selectedId;
  String? keyword;
  Map<String, double> flashStart = {}; // thread id -> scene time it started
  double time = 0;
  DateTime now = DateTime.now();
  Map<String, Vec3> animatedPositions = {};
  Duration timeTravelOffset = Duration.zero;
  int bottleneckCount = 0;
  bool dark = true;
  bool reduceMotion = false;
  bool lowGraphics = false;
}

const Color kCrimson = Color(0xFFFF2A44);
const Color kBlue = Color(0xFF32B4FF);

class WebPainter extends CustomPainter {
  WebPainter(this.scene, this.camera, {super.repaint});

  final WebScene scene;
  final WebCamera camera;
  final Map<String, TextPainter> _tp = {};
  final Map<String, Offset> _spokeLabelPos = {};
  final Map<int, Offset> _ringLabelPos = {};
  bool isAnimatingLabels = false;

  TextPainter _text(String s, double size, Color c, {FontWeight w = FontWeight.w600, double spacing = 0}) {
    final key = '$s|$size|${c.toARGB32()}|${w.value}|$spacing';
    return _tp.putIfAbsent(key, () {
      if (_tp.length > 400) _tp.clear();
      return TextPainter(
        text: TextSpan(text: s, style: TextStyle(fontSize: size, color: c, fontWeight: w, letterSpacing: spacing)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 150);
    });
  }

  Offset _p(double x, double y, double z) {
    final p = camera.project(x, y, z);
    return Offset(p.x, p.y);
  }

  double _fog(double depth) {
    final d = camera.distance;
    return ((1.35 - (depth - d * 0.55) / (d * 1.6))).clamp(0.38, 1.0).toDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    camera.width = size.width;
    camera.height = size.height;
    final dark = scene.dark;
    final ink = dark ? Colors.white : const Color(0xFF0B0F1E);
    final layout = scene.layout;
    final low = scene.lowGraphics;
    final selected = scene.selectedId;
    final kw = scene.keyword?.toLowerCase();

    // Background.
    final bg = Paint()
      ..shader = RadialGradient(
        colors: dark ? const [Color(0xFF111833), Color(0xFF03040A)] : const [Color(0xFFF4F7FF), Color(0xFFDDE5F5)],
        radius: 0.95,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    if (layout.spokes.isEmpty) return;
    isAnimatingLabels = false;
    final zoom = camera.zoomLevel;
    final placedLabelRects = <Rect>[];

    // Spokes (spaces): lines and collision-free labels.
    for (final s in layout.spokes) {
      final a = s.angle;
      final p0 = _p(WebLayout.worldX(1.5, a), WebLayout.worldY(1.5, a), 0);
      final rEnd = layout.outerRadius + 0.5;
      final p1 = _p(WebLayout.worldX(rEnd, a), WebLayout.worldY(rEnd, a), 0);
      canvas.drawLine(p0, p1, Paint()..color = s.color.withValues(alpha: 0.28)..strokeWidth = 1.2);

      final pl = _p(WebLayout.worldX(rEnd + 1.6, a), WebLayout.worldY(rEnd + 1.6, a), 0);
      final tp = _text(s.name.toUpperCase(), 11, s.color, w: FontWeight.w800, spacing: 1.2);

      // Determine screen direction of this spoke.
      final pCenter = _p(0, 0, 0);
      final dir = pl - pCenter;
      final dist = dir.distance;
      final unit = dist > 0.001 ? dir / dist : const Offset(1, 0);
      final norm = Offset(-unit.dy, unit.dx);

      // Candidate offsets to avoid overlap with other spoke labels.
      final candidates = <Offset>[
        pl,
        pl + norm * (tp.height + 4),
        pl - norm * (tp.height + 4),
        pl + unit * 24,
        pl + unit * 24 + norm * (tp.height + 4),
        pl + unit * 24 - norm * (tp.height + 4),
        pl + norm * (tp.height * 2 + 8),
        pl - norm * (tp.height * 2 + 8),
        pl + unit * 48,
        pl + unit * 48 + norm * (tp.height + 4),
        pl + unit * 48 - norm * (tp.height + 4),
        pl + unit * 72,
        pl + unit * 72 + norm * (tp.height + 4),
        pl + unit * 72 - norm * (tp.height + 4),
        pl + unit * 96,
      ];

      Offset chosenPos = pl;
      var placed = false;

      for (final cand in candidates) {
        final rect = Rect.fromCenter(center: cand, width: tp.width + 10, height: tp.height + 6);
        final inBounds = rect.right > 0 && rect.left < size.width && rect.bottom > 0 && rect.top < size.height;
        if (inBounds && !_rectOverlapsAny(rect, placedLabelRects, pad: 4.0)) {
          chosenPos = cand;
          placed = true;
          break;
        }
      }

      if (!placed) {
        // Fallback: pick the candidate that has minimal overlap
        double minOverlap = double.infinity;
        for (final cand in candidates) {
          final rect = Rect.fromCenter(center: cand, width: tp.width + 10, height: tp.height + 6);
          double overlapArea = 0;
          for (final o in placedLabelRects) {
            final inter = rect.intersect(o);
            if (inter.width > 0 && inter.height > 0) {
              overlapArea += inter.width * inter.height;
            }
          }
          if (overlapArea < minOverlap) {
            minOverlap = overlapArea;
            chosenPos = cand;
          }
        }
      }

      // Ultra-smooth animated transition for spoke labels on collision.
      Offset renderPos = chosenPos;
      final prev = _spokeLabelPos[s.spaceId];
      if (prev != null && !scene.reduceMotion && (prev - chosenPos).distance < 250) {
        final d = (prev - chosenPos).distance;
        if (d > 0.4) isAnimatingLabels = true;
        renderPos = Offset.lerp(prev, chosenPos, 0.20)!;
      }
      _spokeLabelPos[s.spaceId] = renderPos;
      final renderRect = Rect.fromCenter(center: renderPos, width: tp.width + 10, height: tp.height + 6);

      // If shifted away from the spoke tip, draw a subtle connector line.
      if ((renderPos - pl).distanceSquared > 16) {
        canvas.drawLine(p1, renderPos, Paint()..color = s.color.withValues(alpha: 0.22)..strokeWidth = 1.0);
      }

      tp.paint(canvas, renderPos - Offset(tp.width / 2, tp.height / 2));
      placedLabelRects.add(renderRect);
    }

    // Rings (urgency bands): paths.
    for (final ring in layout.rings) {
      final r = ring.radius - 0.7;
      final path = Path();
      const seg = 72;
      for (var i = 0; i <= seg; i++) {
        final a = 2 * math.pi * i / seg;
        final o = _p(WebLayout.worldX(r, a), WebLayout.worldY(r, a), 0);
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      final isNow = ring.band == UrgencyBand.now;
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isNow ? 1.4 : 1
          ..color = (isNow ? kCrimson : ink).withValues(alpha: isNow ? 0.35 : 0.10),
      );
      if (isNow && scene.bottleneckCount >= 3) {
        final pulse = scene.reduceMotion ? 0.5 : (0.5 + 0.5 * math.sin(scene.time * 5.0));
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.5 + 2.5 * pulse
            ..color = kCrimson.withValues(alpha: (0.35 + 0.30 * pulse))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
      }
    }

    // Ring labels: side-by-side across different orbits without coincidence.
    final nRings = layout.rings.length;
    final sCount = math.max(1, layout.spokes.length);
    final spokeGap = 2 * math.pi / sCount;
    final la = layout.ringLabelAngle;
    final span = math.min(spokeGap * 0.70, 1.25);
    const nudges = <double>[0.0, 0.06, -0.06, 0.12, -0.12, 0.18, -0.18, 0.25, -0.25, 0.35, -0.35];

    for (var i = 0; i < nRings; i++) {
      final ring = layout.rings[i];
      final r = ring.radius - 0.7;
      final isNow = ring.band == UrgencyBand.now;
      final tp = _text(
        ring.band.label,
        10,
        (isNow ? kCrimson : ink).withValues(alpha: isNow ? 0.90 : 0.65),
        spacing: 1.3,
        w: isNow ? FontWeight.w700 : FontWeight.w500,
      );

      // Stagger each orbit side by side across the angular span.
      final baseDelta = nRings > 1 ? -span / 2 + span * (i / (nRings - 1)) : 0.0;
      final nominalAngle = la + baseDelta;

      Offset chosenPos = _p(WebLayout.worldX(r, nominalAngle), WebLayout.worldY(r, nominalAngle), 0);
      var placed = false;

      for (final nudge in nudges) {
        final candAngle = nominalAngle + nudge;
        final rawPos = _p(WebLayout.worldX(r, candAngle), WebLayout.worldY(r, candAngle), 0);
        final safeX = rawPos.dx.clamp(tp.width / 2 + 6, size.width - tp.width / 2 - 6);
        final safeY = rawPos.dy.clamp(tp.height / 2 + 6, size.height - tp.height / 2 - 6);
        final candPos = Offset(safeX, safeY);
        final candRect = Rect.fromCenter(center: candPos, width: tp.width + 10, height: tp.height + 6);

        if (!_rectOverlapsAny(candRect, placedLabelRects, pad: 2.0)) {
          chosenPos = candPos;
          placed = true;
          break;
        }
      }

      if (!placed) {
        // Fallback: pick candidate with minimum overlap so no label is ever invisible.
        double minOverlap = double.infinity;
        for (final nudge in nudges) {
          final candAngle = nominalAngle + nudge;
          final rawPos = _p(WebLayout.worldX(r, candAngle), WebLayout.worldY(r, candAngle), 0);
          final safeX = rawPos.dx.clamp(tp.width / 2 + 6, size.width - tp.width / 2 - 6);
          final safeY = rawPos.dy.clamp(tp.height / 2 + 6, size.height - tp.height / 2 - 6);
          final candPos = Offset(safeX, safeY);
          final candRect = Rect.fromCenter(center: candPos, width: tp.width + 10, height: tp.height + 6);

          double overlap = 0;
          for (final o in placedLabelRects) {
            final inter = candRect.intersect(o);
            if (inter.width > 0 && inter.height > 0) {
              overlap += inter.width * inter.height;
            }
          }
          if (overlap < minOverlap) {
            minOverlap = overlap;
            chosenPos = candPos;
          }
        }
      }

      // Ultra-smooth animated transition for ring labels on collision.
      Offset renderPos = chosenPos;
      final prev = _ringLabelPos[ring.band.index];
      if (prev != null && !scene.reduceMotion && (prev - chosenPos).distance < 250) {
        final d = (prev - chosenPos).distance;
        if (d > 0.4) isAnimatingLabels = true;
        renderPos = Offset.lerp(prev, chosenPos, 0.20)!;
      }
      _ringLabelPos[ring.band.index] = renderPos;
      final renderRect = Rect.fromCenter(center: renderPos, width: tp.width + 10, height: tp.height + 6);

      // Draw subtle backing pill for readability over orbit lines.
      final pillRect = Rect.fromCenter(center: renderPos, width: tp.width + 8, height: tp.height + 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(pillRect, const Radius.circular(5)),
        Paint()..color = (dark ? const Color(0xFF060913) : Colors.white).withValues(alpha: 0.72),
      );

      tp.paint(canvas, renderPos - Offset(tp.width / 2, tp.height / 2));
      placedLabelRects.add(renderRect);
    }

    // Edges.
    for (final e in scene.edges) {
      final na = layout.nodes[e.a], nb = layout.nodes[e.b];
      if (na == null || nb == null) continue;
      final touches = selected != null && (e.a == selected || e.b == selected);
      final dim = selected != null && !touches;
      final pa = scene.animatedPositions[e.a] ?? na.position;
      final pb = scene.animatedPositions[e.b] ?? nb.position;
      final oa = _p(pa.x, pa.y, pa.z), ob = _p(pb.x, pb.y, pb.z);
      final ca = layout.spokes[na.spokeIndex].color, cb = layout.spokes[nb.spokeIndex].color;
      final col = Color.lerp(ca, cb, 0.5)!;
      final alpha = (touches ? 0.95 : (e.explicit ? 0.55 : 0.28)) * (dim ? 0.35 : 1.0);
      if (e.explicit) {
        // silk: curve lifted towards the camera in z
        final mx = (pa.x + pb.x) / 2, my = (pa.y + pb.y) / 2;
        final len = math.sqrt(math.pow(pa.x - pb.x, 2) + math.pow(pa.y - pb.y, 2)).toDouble();
        final c = _p(mx * 0.82, my * 0.82, (pa.z + pb.z) / 2 + len * 0.12);
        final path = Path()
          ..moveTo(oa.dx, oa.dy)
          ..quadraticBezierTo(c.dx, c.dy, ob.dx, ob.dy);
        if (touches && !low) {
          canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 5..color = col.withValues(alpha: 0.18)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
        }
        canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = touches ? 2.2 : 1.5..color = col.withValues(alpha: alpha));
        if (touches && !scene.reduceMotion && !low) {
          for (var k = 0; k < 3; k++) {
            final t = ((scene.time * 0.5) + k / 3) % 1.0;
            final u = 1 - t;
            final x = u * u * oa.dx + 2 * u * t * c.dx + t * t * ob.dx;
            final y = u * u * oa.dy + 2 * u * t * c.dy + t * t * ob.dy;
            canvas.drawCircle(Offset(x, y), 2.4, Paint()..color = Colors.white.withValues(alpha: 0.9));
          }
        }
      } else {
        // dotted keyword strand
        final dist = (ob - oa).distance;
        final n = (dist / 7).floor().clamp(0, 120);
        final paint = Paint()..color = col.withValues(alpha: alpha)..strokeWidth = 1.4..strokeCap = StrokeCap.round;
        final pts = <Offset>[for (var i = 0; i <= n; i++) Offset.lerp(oa, ob, n == 0 ? 0 : i / n)!];
        canvas.drawPoints(PointMode.points, pts, paint);
      }
    }

    // Nodes far -> near.
    final order = layout.nodes.values.toList();
    final projected = <String, ProjectedPoint>{};
    for (final n in order) {
      final pos = scene.animatedPositions[n.id] ?? n.position;
      projected[n.id] = camera.project(pos.x, pos.y, pos.z);
    }
    order.sort((a, b) => projected[b.id]!.depth.compareTo(projected[a.id]!.depth));

    final related = <String>{};
    if (selected != null) {
      for (final e in scene.edges) {
        if (e.a == selected) related.add(e.b);
        if (e.b == selected) related.add(e.a);
      }
    }
    final labels = <LabelCandidate>[];
    final labelText = <String, TextPainter>{};
    final labelNode = <String, Offset>{};

    for (final n in order) {
      final t = scene.byId[n.id];
      final p = projected[n.id]!;
      if (t == null || !p.visible) continue;
      final color = layout.spokes[n.spokeIndex].color;
      final isSel = n.id == selected;
      var alpha = _fog(p.depth);
      if (selected != null && !isSel && !related.contains(n.id)) alpha *= 0.35;
      if (kw != null && kw.isNotEmpty && !t.keywords.any((k) => k.toLowerCase().contains(kw)) && !t.title.toLowerCase().contains(kw)) alpha *= 0.2;
      final r = nodeRadiusPx(scale: p.scale, priorityIndex: t.priority.index, isGoal: t.type == ThreadType.goal);
      final c = Offset(p.x, p.y);
      final overdue = isOverdue(t, scene.now);

      if (overdue) {
        final pulse = scene.reduceMotion ? 0.5 : (0.5 + 0.5 * math.sin(scene.time * 4));
        canvas.drawCircle(c, r + 5 + 4 * pulse, Paint()..color = kCrimson.withValues(alpha: (0.18 + 0.2 * pulse) * alpha));
        canvas.drawCircle(c, r + 3, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.6..color = kCrimson.withValues(alpha: 0.9 * alpha));
      }
      final flashAt = scene.flashStart[n.id];
      if (flashAt != null) {
        final k = ((scene.time - flashAt) / 2.5).clamp(0.0, 1.0).toDouble();
        if (k < 1) canvas.drawCircle(c, r + 6 + 40 * k, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = kBlue.withValues(alpha: (1 - k) * 0.9));
      }
      if (!low && (isSel || t.status == ThreadStatus.doing)) {
        canvas.drawCircle(c, r * 2.2, Paint()..color = color.withValues(alpha: 0.22 * alpha)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      }

      final path = _shape(t.type, c, r);
      final done = t.status == ThreadStatus.done;
      final fill = Paint()
        ..color = done
            ? color.withValues(alpha: 0.45 * alpha)
            : t.status == ThreadStatus.doing
                ? color.withValues(alpha: alpha)
                : color.withValues(alpha: 0.16 * alpha);
      canvas.drawPath(path, fill);
      canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = r > 9 ? 2.2 : 1.6..color = color.withValues(alpha: alpha));
      if (done && r > 6) {
        final tick = Path()
          ..moveTo(c.dx - r * 0.4, c.dy)
          ..lineTo(c.dx - r * 0.1, c.dy + r * 0.32)
          ..lineTo(c.dx + r * 0.45, c.dy - r * 0.3);
        canvas.drawPath(tick, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..strokeCap = StrokeCap.round..color = Colors.white.withValues(alpha: 0.9 * alpha));
      }
      if (t.status == ThreadStatus.doing) {
        final prog = t.checklist.isEmpty ? 0.25 : t.progress;
        final start = scene.reduceMotion ? -math.pi / 2 : scene.time * 1.6;
        canvas.drawArc(Rect.fromCircle(center: c, radius: r + 3), start, 2 * math.pi * prog.clamp(0.05, 1.0), false,
            Paint()..style = PaintingStyle.stroke..strokeWidth = 2.4..strokeCap = StrokeCap.round..color = Colors.white.withValues(alpha: 0.85 * alpha));
      }
      if (isSel) {
        canvas.drawCircle(c, r + 5, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = Colors.white);
        canvas.drawCircle(c, r + 9, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = Colors.white.withValues(alpha: 0.5));
      }

      // Label candidate.
      final tp = _text(t.title, 11, ink.withValues(alpha: 0.92));
      final w = tp.width, h = tp.height;
      final lx = c.dx - w / 2, ly = c.dy + r + 4;
      var imp = 1.0 + p.scale * 0.05 + t.priority.index * 2;
      if (isSel) {
        imp += 1000;
      } else if (related.contains(n.id)) {
        imp += 200;
      }
      if (overdue) imp += 50;
      if (kw != null && kw.isNotEmpty && alpha > 0.5) imp += 100;
      if (done) imp -= 3;
      labels.add(LabelCandidate(id: n.id, x: lx, y: ly, w: w, h: h, importance: imp));
      labelText[n.id] = tp;
      labelNode[n.id] = Offset(lx, ly);
    }

    final chosen = pickLabels(
      labels,
      budget: labelBudget(zoom) + (selected != null ? 6 : 0),
      viewWidth: size.width,
      viewHeight: size.height,
      obstacles: placedLabelRects,
    );
    for (final id in chosen) {
      final tp = labelText[id]!;
      final o = labelNode[id]!;
      final pill = RRect.fromRectAndRadius(Rect.fromLTWH(o.dx - 4, o.dy - 1, tp.width + 8, tp.height + 2), const Radius.circular(6));
      canvas.drawRRect(pill, Paint()..color = (dark ? const Color(0xFF03040A) : Colors.white).withValues(alpha: 0.72));
      tp.paint(canvas, o);
    }
  }

  Path _shape(ThreadType type, Offset c, double r) {
    final path = Path();
    switch (type) {
      case ThreadType.task:
        path.addOval(Rect.fromCircle(center: c, radius: r));
        break;
      case ThreadType.idea:
        path
          ..moveTo(c.dx, c.dy - r * 1.15)
          ..lineTo(c.dx + r * 1.15, c.dy)
          ..lineTo(c.dx, c.dy + r * 1.15)
          ..lineTo(c.dx - r * 1.15, c.dy)
          ..close();
        break;
      case ThreadType.question:
        for (var i = 0; i < 6; i++) {
          final a = math.pi / 3 * i + math.pi / 6;
          final o = Offset(c.dx + r * 1.08 * math.cos(a), c.dy + r * 1.08 * math.sin(a));
          i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
        }
        path.close();
        break;
      case ThreadType.goal:
        for (var i = 0; i < 10; i++) {
          final a = -math.pi / 2 + math.pi / 5 * i;
          final rr = i.isEven ? r * 1.25 : r * 0.55;
          final o = Offset(c.dx + rr * math.cos(a), c.dy + rr * math.sin(a));
          i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
        }
        path.close();
        break;
    }
    return path;
  }

  /// Nearest node within [maxDist] px of the tap, or null.
  String? hitTestNode(Offset pos, {double maxDist = 28}) {
    String? best;
    var bestD = maxDist;
    var bestDepth = double.infinity;
    for (final n in scene.layout.nodes.values) {
      final worldPos = scene.animatedPositions[n.id] ?? n.position;
      final p = camera.project(worldPos.x, worldPos.y, worldPos.z);
      if (!p.visible) continue;
      final d = (Offset(p.x, p.y) - pos).distance;
      if (d < bestD - 1 || (d <= bestD + 1 && p.depth < bestDepth && best != null)) {
        best = n.id;
        bestD = d;
        bestDepth = p.depth;
      }
    }
    return best;
  }

  @override
  bool shouldRepaint(covariant WebPainter old) => true;
}


bool _rectOverlapsAny(Rect r, List<Rect> others, {double pad = 4.0}) {
  final padded = r.inflate(pad);
  for (final o in others) {
    if (padded.overlaps(o)) return true;
  }
  return false;
}

