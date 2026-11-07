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
  Map<String, double> shockwaveStart = {}; // thread id -> completion shockwave time
  double time = 0;
  DateTime now = DateTime.now();
  Map<String, Vec3> animatedPositions = {};
  Duration timeTravelOffset = Duration.zero;
  int bottleneckCount = 0;
  bool showMembranes = true;
  bool radarActive = false;
  double radarAngle = 0.0;
  double radarRadius = 0.0;
  String? radarTargetId;
  Set<String> focusThreadIds = {};
  // Feature 5: Slingshot Quick-Capture
  bool slingshotActive = false;
  bool slingshotDragging = false;
  Offset? slingshotAnchor;
  Offset? slingshotDrag;
  String slingshotSeedTitle = '';
  double slingshotTension = 0.0;
  bool slingshotFlying = false;
  double slingshotFlightProgress = 0.0;
  Offset? slingshotFlightStart;
  Offset? slingshotFlightEnd;
  String? slingshotTargetSpokeName;
  UrgencyBand? slingshotTargetBand;
  Color? slingshotTargetColor;
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

    // Spider Radar Sensory Sweep.
    if (scene.radarActive && !scene.lowGraphics) {
      _paintSpiderRadarSweep(canvas, size, scene, dark);
    }

    // Constellation Membranes (Project Sails).
    if (scene.showMembranes && !scene.lowGraphics) {
      _paintConstellationMembranes(canvas, layout, scene, dark, selected);
    }

    // Edges.
    for (final e in scene.edges) {
      final na = layout.nodes[e.a], nb = layout.nodes[e.b];
      if (na == null || nb == null) continue;
      final touches = selected != null && (e.a == selected || e.b == selected);
      final dim = selected != null && !touches;
      final radarActive = scene.radarActive;
      final isRadarLink = radarActive &&
          ((scene.radarTargetId != null && (e.a == scene.radarTargetId || e.b == scene.radarTargetId)) ||
           (scene.focusThreadIds.contains(e.a) && scene.focusThreadIds.contains(e.b)));
      var alpha = (touches ? 0.95 : (e.explicit ? 0.55 : 0.28)) * (dim ? 0.35 : 1.0);
      if (radarActive) {
        if (isRadarLink) {
          alpha = 0.95;
        } else {
          alpha = (alpha * 0.16).clamp(0.04, 0.10);
        }
      }
      final pa = scene.animatedPositions[e.a] ?? na.position;
      final pb = scene.animatedPositions[e.b] ?? nb.position;
      final oa = _p(pa.x, pa.y, pa.z), ob = _p(pb.x, pb.y, pb.z);
      final ca = layout.spokes[na.spokeIndex].color, cb = layout.spokes[nb.spokeIndex].color;
      final col = Color.lerp(ca, cb, 0.5)!;
      final ta = scene.byId[e.a], tb = scene.byId[e.b];
      final overdueA = ta != null && isOverdue(ta, scene.now);
      final overdueB = tb != null && isOverdue(tb, scene.now);
      final hasOverdue = overdueA || overdueB;
      final hasDoing = (ta?.status == ThreadStatus.doing) || (tb?.status == ThreadStatus.doing);
      final bothDone = (ta?.isDone ?? false) && (tb?.isDone ?? false);
      final anyDone = (ta?.isDone ?? false) || (tb?.isDone ?? false);

      if (e.explicit) {
        // Dynamic Tension & Catenary physics:
        // Overdue tasks pull silk taut (low sag + fast harmonic tremble).
        // Completed tasks relax into deep, calm drooping curves.
        final mx = (pa.x + pb.x) / 2, my = (pa.y + pb.y) / 2;
        final len = math.sqrt(math.pow(pa.x - pb.x, 2) + math.pow(pa.y - pb.y, 2)).toDouble();

        double arcRatio = 0.12;
        double vibZ = 0.0;
        if (hasOverdue) {
          arcRatio = 0.03; // Taut mechanical tension
          if (!scene.reduceMotion) vibZ = math.sin(scene.time * 24.0 + len * 3.0) * 0.03 * len;
        } else if (bothDone) {
          arcRatio = 0.23; // Relaxed catenary sag
          if (!scene.reduceMotion) vibZ = math.sin(scene.time * 1.8) * 0.014 * len;
        } else if (hasDoing) {
          arcRatio = 0.075; // Energized tension
          if (!scene.reduceMotion) vibZ = math.sin(scene.time * 11.0) * 0.015 * len;
        }

        final cz = (pa.z + pb.z) / 2 + len * arcRatio + vibZ;
        final pullFactor = hasOverdue ? 0.94 : (bothDone ? 0.72 : 0.82);
        final c = _p(mx * pullFactor, my * pullFactor, cz);
        final path = Path()
          ..moveTo(oa.dx, oa.dy)
          ..quadraticBezierTo(c.dx, c.dy, ob.dx, ob.dy);

        // Silk outer glow
        if (!low && (touches || hasOverdue || hasDoing)) {
          final glowCol = hasOverdue ? kCrimson : (hasDoing ? const Color(0xFF00E5FF) : col);
          canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = touches ? 5.5 : 3.5
              ..color = glowCol.withValues(alpha: touches ? 0.28 : 0.16)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
          );
        }

        // Silk core strand
        final strandWidth = touches ? 2.3 : (hasOverdue ? 1.9 : 1.4);
        final strandColor = hasOverdue
            ? Color.lerp(col, kCrimson, 0.65)!
            : (hasDoing ? Color.lerp(col, const Color(0xFF00E5FF), 0.5)! : col);
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = strandWidth
            ..color = strandColor.withValues(alpha: alpha),
        );

        // Bioluminescent Fiber-Optic Pulses:
        // Living energy packets flow from upstream to downstream nodes along the strand
        if (!scene.reduceMotion && !low) {
          final packetCount = touches ? 3 : (hasDoing || hasOverdue ? 2 : 1);
          final speed = hasOverdue ? 0.95 : (hasDoing ? 0.72 : (bothDone ? 0.25 : 0.42));
          final pulseColor = hasOverdue
              ? const Color(0xFFFF2A44)
              : (hasDoing ? const Color(0xFF00F5FF) : (anyDone ? const Color(0xFF50FA7B) : const Color(0xFF80D8FF)));

          for (var k = 0; k < packetCount; k++) {
            final tPulse = ((scene.time * speed) + k / packetCount) % 1.0;
            final u = 1 - tPulse;
            final x = u * u * oa.dx + 2 * u * tPulse * c.dx + tPulse * tPulse * ob.dx;
            final y = u * u * oa.dy + 2 * u * tPulse * c.dy + tPulse * tPulse * ob.dy;
            final pulseOffset = Offset(x, y);

            // Bioluminescent glow halo
            canvas.drawCircle(
              pulseOffset,
              touches ? 4.5 : 3.2,
              Paint()
                ..color = pulseColor.withValues(alpha: touches ? 0.8 : 0.45)
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.2),
            );
            // Crisp white energy particle
            canvas.drawCircle(
              pulseOffset,
              touches ? 2.2 : 1.5,
              Paint()..color = Colors.white.withValues(alpha: 0.95),
            );
          }
        }
      } else {
        // dotted keyword strand
        final dist = (ob - oa).distance;
        final n = (dist / 7).floor().clamp(0, 120);
        final paint = Paint()..color = col.withValues(alpha: alpha)..strokeWidth = 1.4..strokeCap = StrokeCap.round;
        final pts = <Offset>[for (var i = 0; i <= n; i++) Offset.lerp(oa, ob, n == 0 ? 0 : i / n)!];
        canvas.drawPoints(PointMode.points, pts, paint);

        if (touches && !scene.reduceMotion && !low) {
          final tPulse = (scene.time * 0.6) % 1.0;
          final pulsePt = Offset.lerp(oa, ob, tPulse)!;
          canvas.drawCircle(
            pulsePt,
            3.2,
            Paint()..color = const Color(0xFF00E5FF).withValues(alpha: 0.75)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
          );
          canvas.drawCircle(pulsePt, 1.6, Paint()..color = Colors.white);
        }
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
      final isRadarTarget = scene.radarActive && n.id == scene.radarTargetId;
      final isRadarFocused = scene.radarActive && scene.focusThreadIds.contains(n.id);
      if (scene.radarActive) {
        if (isRadarTarget) {
          alpha = 1.0;
        } else if (isRadarFocused) {
          alpha = 0.92;
        } else {
          alpha = (alpha * 0.16).clamp(0.06, 0.20);
        }
      }
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
      final shockAt = scene.shockwaveStart[n.id];
      if (shockAt != null) {
        final elapsed = scene.time - shockAt;
        if (elapsed >= 0 && elapsed <= 2.0) {
          final k = (elapsed / 2.0).clamp(0.0, 1.0);
          final waveR = r + 8 + 110 * k;
          final waveAlpha = (1.0 - k).clamp(0.0, 1.0);
          if (!low) {
            canvas.drawCircle(
              c,
              waveR,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = (1.0 - k) * 4.0 + 1.0
                ..color = const Color(0xFF00FFCC).withValues(alpha: waveAlpha * 0.72)
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0),
            );
          }
          canvas.drawCircle(
            c,
            waveR,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.8
              ..color = Colors.white.withValues(alpha: waveAlpha * 0.88),
          );
        }
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
      if (isRadarTarget) {
        final pulse = scene.reduceMotion ? 1.0 : (1.0 + math.sin(scene.time * 6.0) * 0.16);
        if (!low) {
          canvas.drawCircle(
            c,
            r * 2.8 * pulse,
            Paint()
              ..color = const Color(0xFF00F5FF).withValues(alpha: 0.32)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
          );
        }
        final boxSize = r + 8.0;
        final reticlePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = const Color(0xFF00F5FF).withValues(alpha: 0.92);
        final rot = scene.reduceMotion ? 0.0 : (scene.time * 0.7);
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(rot);
        for (var arm = 0; arm < 4; arm++) {
          canvas.drawLine(Offset(boxSize - 4, 0), Offset(boxSize + 4, 0), reticlePaint);
          canvas.rotate(math.pi / 2);
        }
        canvas.restore();
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
      if (isRadarTarget) {
        imp += 5000;
      } else if (isRadarFocused) {
        imp += 900;
      } else if (scene.radarActive) {
        imp -= 60;
      }
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

    if (scene.slingshotActive || scene.slingshotFlying) {
      _paintSlingshotQuickCapture(canvas, size, scene, dark);
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

  /// Calculates the 2D convex hull of a set of points (Monotone Chain).
  List<Offset> _convexHull(List<Offset> points) {
    if (points.length <= 2) return List<Offset>.from(points);
    final sorted = List<Offset>.from(points)
      ..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));

    double cross(Offset o, Offset a, Offset b) =>
        (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);

    final lower = <Offset>[];
    for (final p in sorted) {
      while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }

    final upper = <Offset>[];
    for (final p in sorted.reversed) {
      while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }

    if (lower.length > 1) lower.removeLast();
    if (upper.length > 1) upper.removeLast();
    return lower..addAll(upper);
  }

  /// Builds a softly rounded organic membrane path from convex hull vertices.
  Path _buildMembranePath(List<Offset> hull) {
    final path = Path();
    final n = hull.length;
    if (n < 3) return path;
    final midpoints = <Offset>[];
    for (var i = 0; i < n; i++) {
      final a = hull[i];
      final b = hull[(i + 1) % n];
      midpoints.add(Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2));
    }
    path.moveTo(midpoints[0].dx, midpoints[0].dy);
    for (var i = 0; i < n; i++) {
      final nextMid = midpoints[(i + 1) % n];
      final corner = hull[(i + 1) % n];
      path.quadraticBezierTo(corner.dx, corner.dy, nextMid.dx, nextMid.dy);
    }
    path.close();
    return path;
  }

  /// Renders translucent polymer/crystal sails spanning related task clusters.
  void _paintConstellationMembranes(
    Canvas canvas,
    WebLayout layout,
    WebScene scene,
    bool dark,
    String? selected,
  ) {
    // 1. Spoke / Space project sails (clusters of >= 3 nodes in the same space)
    for (final s in layout.spokes) {
      final clusterNodes = layout.nodes.values.where((n) => n.spokeIndex == s.index).toList();
      if (clusterNodes.length < 3) continue;

      final pts = <Offset>[];
      for (final n in clusterNodes) {
        final pos = scene.animatedPositions[n.id] ?? n.position;
        pts.add(_p(pos.x, pos.y, pos.z));
      }

      final hull = _convexHull(pts);
      if (hull.length < 3) continue;

      final path = _buildMembranePath(hull);
      final bounds = path.getBounds();
      if (bounds.width < 18 || bounds.height < 18) continue;

      final clusterThreads = [for (final n in clusterNodes) scene.byId[n.id]].whereType<Thread>().toList();
      final doneCount = clusterThreads.where((t) => t.isDone).length;
      final totalCount = clusterThreads.length;
      final ratio = totalCount > 0 ? (doneCount / totalCount).clamp(0.0, 1.0) : 0.0;
      final isClusterSelected = selected != null && clusterNodes.any((n) => n.id == selected);
      final shimmer = scene.reduceMotion ? 0.0 : math.sin(scene.time * 2.0 + s.index * 1.4) * 0.02;

      final baseAlpha = (0.05 + 0.16 * ratio + (isClusterSelected ? 0.10 : 0.0) + shimmer).clamp(0.02, 0.40);
      final sailColor = ratio >= 0.99 ? const Color(0xFF50FA7B) : s.color;

      // Translucent polymer / crystal gradient fill
      final fillPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            sailColor.withValues(alpha: (baseAlpha * 1.5).clamp(0.03, 0.50)),
            sailColor.withValues(alpha: (baseAlpha * 0.6).clamp(0.01, 0.30)),
            sailColor.withValues(alpha: 0.01),
          ],
          stops: const [0.0, 0.72, 1.0],
        ).createShader(bounds)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, fillPaint);

      // Internal gossamer ribs from centroid to hull vertices
      final center = bounds.center;
      final ribAlpha = (0.06 + 0.14 * ratio + (isClusterSelected ? 0.08 : 0.0)).clamp(0.03, 0.28);
      final ribPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.85
        ..color = sailColor.withValues(alpha: ribAlpha);
      for (final v in hull) {
        canvas.drawLine(center, v, ribPaint);
      }

      // Shimmering perimeter rim
      if (isClusterSelected || ratio >= 0.8) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4.0
            ..color = sailColor.withValues(alpha: (0.10 + 0.16 * ratio))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0),
        );
      }
      final rimPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isClusterSelected ? 2.0 : (1.0 + 0.6 * ratio)
        ..color = sailColor.withValues(alpha: (0.20 + 0.32 * ratio + (isClusterSelected ? 0.25 : 0.0)).clamp(0.12, 0.85));
      canvas.drawPath(path, rimPaint);

      // Subtle project progress watermark seal at center of larger sails
      if (bounds.width > 90 && bounds.height > 90) {
        final pctStr = '${(ratio * 100).toInt()}%';
        final pctTp = _text(pctStr, 10, sailColor.withValues(alpha: (0.50 + 0.35 * ratio).clamp(0.3, 0.9)), w: FontWeight.bold);
        final sealRect = Rect.fromCenter(center: center, width: pctTp.width + 12, height: pctTp.height + 6);
        canvas.drawRRect(
          RRect.fromRectAndRadius(sealRect, const Radius.circular(8)),
          Paint()..color = (dark ? const Color(0xFF060913) : Colors.white).withValues(alpha: 0.65),
        );
        pctTp.paint(canvas, center - Offset(pctTp.width / 2, pctTp.height / 2));
      }
    }

    // 2. Cross-Space explicit dependency bridge sails
    final explicitAdj = <String, Set<String>>{};
    for (final e in scene.edges) {
      if (!e.explicit) continue;
      explicitAdj.putIfAbsent(e.a, () => {}).add(e.b);
      explicitAdj.putIfAbsent(e.b, () => {}).add(e.a);
    }
    final visited = <String>{};
    for (final startId in explicitAdj.keys) {
      if (visited.contains(startId)) continue;
      final comp = <String>[];
      final queue = [startId];
      visited.add(startId);
      while (queue.isNotEmpty) {
        final curr = queue.removeLast();
        comp.add(curr);
        for (final neighbor in explicitAdj[curr] ?? const <String>{}) {
          if (!visited.contains(neighbor)) {
            visited.add(neighbor);
            queue.add(neighbor);
          }
        }
      }
      if (comp.length >= 3 && comp.length <= 12) {
        final spokeIndices = {for (final id in comp) layout.nodes[id]?.spokeIndex}.whereType<int>().toSet();
        if (spokeIndices.length > 1) {
          final pts = <Offset>[];
          for (final id in comp) {
            final n = layout.nodes[id];
            if (n == null) continue;
            final pos = scene.animatedPositions[id] ?? n.position;
            pts.add(_p(pos.x, pos.y, pos.z));
          }
          final hull = _convexHull(pts);
          if (hull.length >= 3) {
            final path = _buildMembranePath(hull);
            final bounds = path.getBounds();
            if (bounds.width >= 30 && bounds.height >= 30) {
              final isBridgeSelected = selected != null && comp.contains(selected);
              const bridgeColor = Color(0xFF9D4EDD); // Iridescent violet bridge
              final bridgeAlpha = (isBridgeSelected ? 0.18 : 0.08);

              canvas.drawPath(
                path,
                Paint()
                  ..shader = RadialGradient(
                    colors: [
                      bridgeColor.withValues(alpha: bridgeAlpha * 1.5),
                      const Color(0xFF00E5FF).withValues(alpha: bridgeAlpha * 0.8),
                      Colors.transparent,
                    ],
                  ).createShader(bounds)
                  ..style = PaintingStyle.fill,
              );
              canvas.drawPath(
                path,
                Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = isBridgeSelected ? 1.8 : 1.0
                  ..color = bridgeColor.withValues(alpha: isBridgeSelected ? 0.6 : 0.3),
              );
            }
          }
        }
      }
    }
  }

  /// Renders rotating sonar sweep and radial waves for Spider Radar Focus Mode.
  void _paintSpiderRadarSweep(Canvas canvas, Size size, WebScene scene, bool dark) {
    final center = _p(0, 0, 0);
    final outerR = (_p(scene.layout.outerRadius + 2.5, 0, 0) - center).distance;

    // 1. Expanding circular sonar pulse wave
    if (scene.radarRadius > 0.1) {
      final waveRPx = (_p(scene.radarRadius, 0, 0) - center).distance;
      final maxRad = scene.layout.outerRadius + 3.0;
      final waveProgress = (scene.radarRadius / maxRad).clamp(0.0, 1.0);
      final waveAlpha = (1.0 - waveProgress).clamp(0.0, 1.0);

      canvas.drawCircle(
        center,
        waveRPx,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = const Color(0xFF00F5FF).withValues(alpha: waveAlpha * 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0),
      );
      canvas.drawCircle(
        center,
        waveRPx,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = Colors.white.withValues(alpha: waveAlpha * 0.75),
      );
    }

    // 2. Rotating sweeping 360-degree radar beam cone
    const sweepAngle = 0.52; // ~30 degrees wide beam
    final beamPath = Path()..moveTo(center.dx, center.dy);
    beamPath.arcTo(
      Rect.fromCircle(center: center, radius: outerR),
      scene.radarAngle - sweepAngle,
      sweepAngle,
      false,
    );
    beamPath.close();

    final beamPaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        startAngle: scene.radarAngle - sweepAngle,
        endAngle: scene.radarAngle,
        colors: [
          Colors.transparent,
          const Color(0xFF00F5FF).withValues(alpha: 0.14),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: outerR))
      ..style = PaintingStyle.fill;
    canvas.drawPath(beamPath, beamPaint);

    // 3. Crisp leading radar laser scan ray
    final rayEnd = Offset(
      center.dx + outerR * math.cos(scene.radarAngle),
      center.dy + outerR * math.sin(scene.radarAngle),
    );
    canvas.drawLine(
      center,
      rayEnd,
      Paint()
        ..color = const Color(0xFF00F5FF).withValues(alpha: 0.70)
        ..strokeWidth = 1.6,
    );
  }

  /// Renders elastic silk slingshot, tension prediction trajectory, and seed flight.
  void _paintSlingshotQuickCapture(Canvas canvas, Size size, WebScene scene, bool dark) {
    const neonEmerald = Color(0xFF00FF88);

    // 1. When actively dragging the slingshot band
    if (scene.slingshotDragging && scene.slingshotAnchor != null && scene.slingshotDrag != null) {
      final anchor = scene.slingshotAnchor!;
      final drag = scene.slingshotDrag!;
      final delta = drag - anchor;
      final dist = delta.distance;
      final tension = scene.slingshotTension.clamp(0.0, 1.0);

      // Perpendicular prong offset (width ~54px between posts)
      final perp = dist > 0.001
          ? Offset(-delta.dy, delta.dx) / dist * 27.0
          : const Offset(27.0, 0.0);
      final leftProng = anchor + perp;
      final rightProng = anchor - perp;

      // Draw cybernetic sling anchor base
      canvas.drawCircle(
        anchor,
        14.0,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = neonEmerald.withValues(alpha: 0.35),
      );
      canvas.drawCircle(
        anchor,
        4.0,
        Paint()..color = neonEmerald.withValues(alpha: 0.6),
      );

      // Prong posts
      final postPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..color = neonEmerald;
      canvas.drawLine(anchor, leftProng, postPaint);
      canvas.drawLine(anchor, rightProng, postPaint);

      // Prong glowing tips
      canvas.drawCircle(leftProng, 4.0, Paint()..color = Colors.white);
      canvas.drawCircle(rightProng, 4.0, Paint()..color = Colors.white);

      // Elastic dual silk bands (thinner as tension increases)
      final bandWidth = (3.4 * (1.0 - 0.45 * tension)).clamp(1.4, 3.4);
      final bandGlow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bandWidth + 3.0
        ..strokeCap = StrokeCap.round
        ..color = neonEmerald.withValues(alpha: 0.35 + 0.35 * tension)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
      final bandCore = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bandWidth
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(neonEmerald, Colors.white, 0.4 + 0.4 * tension)!;

      canvas.drawLine(leftProng, drag, bandGlow);
      canvas.drawLine(leftProng, drag, bandCore);
      canvas.drawLine(rightProng, drag, bandGlow);
      canvas.drawLine(rightProng, drag, bandCore);

      // Trajectory Prediction Line & Landing Crosshair
      if (dist > 12.0) {
        final launchDir = -delta / dist;
        final launchPowerPx = math.min(size.width * 0.85, dist * 3.4);
        final targetPos = anchor + launchDir * launchPowerPx;

        // Dotted / dashed luminous laser trajectory path
        const dotCount = 14;
        for (var i = 1; i <= dotCount; i++) {
          final t = i / dotCount;
          final dotPos = Offset.lerp(anchor, targetPos, t)!;
          final dotR = 2.0 + 1.5 * (1.0 - t);
          final dotAlpha = (0.3 + 0.6 * tension * (1.0 - t * 0.5)).clamp(0.1, 0.95);
          canvas.drawCircle(
            dotPos,
            dotR,
            Paint()..color = neonEmerald.withValues(alpha: dotAlpha),
          );
        }

        // Target Landing Reticle & Sonar Ping
        final reticlePulse = scene.reduceMotion ? 0.0 : math.sin(scene.time * 8.0) * 2.5;
        final reticleR = 18.0 + reticlePulse;
        final targetColor = scene.slingshotTargetColor ?? neonEmerald;

        canvas.drawCircle(
          targetPos,
          reticleR,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..color = targetColor.withValues(alpha: 0.85),
        );
        canvas.drawCircle(
          targetPos,
          reticleR + 7.0,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.9
            ..color = targetColor.withValues(alpha: 0.45),
        );
        // Crosshairs
        canvas.drawLine(
          Offset(targetPos.dx - reticleR - 5, targetPos.dy),
          Offset(targetPos.dx + reticleR + 5, targetPos.dy),
          Paint()..color = targetColor.withValues(alpha: 0.7)..strokeWidth = 1.2,
        );
        canvas.drawLine(
          Offset(targetPos.dx, targetPos.dy - reticleR - 5),
          Offset(targetPos.dx, targetPos.dy + reticleR + 5),
          Paint()..color = targetColor.withValues(alpha: 0.7)..strokeWidth = 1.2,
        );

        // Landing target info badge
        final spokeName = scene.slingshotTargetSpokeName ?? 'Web';
        final bandLabel = scene.slingshotTargetBand?.label ?? 'NOW';
        final infoText = '$spokeName • $bandLabel';
        final tp = _text(infoText, 10.5, Colors.white, w: FontWeight.w700);
        final badgeRect = Rect.fromCenter(
          center: Offset(targetPos.dx, targetPos.dy - reticleR - 14),
          width: tp.width + 14,
          height: tp.height + 8,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(badgeRect, const Radius.circular(8)),
          Paint()..color = const Color(0xFF03040A).withValues(alpha: 0.85),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(badgeRect, const Radius.circular(8)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0
            ..color = targetColor.withValues(alpha: 0.8),
        );
        tp.paint(canvas, Offset(badgeRect.left + 7, badgeRect.top + 4));
      }

      // Thread Seed Capsule at drag position
      final seedPulse = scene.reduceMotion ? 1.0 : (1.0 + 0.12 * math.sin(scene.time * 6.0));
      final seedR = 11.0 * seedPulse;
      canvas.drawCircle(
        drag,
        seedR + 6.0,
        Paint()
          ..color = neonEmerald.withValues(alpha: 0.35 + 0.35 * tension)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0),
      );
      canvas.drawCircle(
        drag,
        seedR,
        Paint()..color = Color.lerp(neonEmerald, const Color(0xFF00F5FF), 0.35)!,
      );
      canvas.drawCircle(
        drag,
        seedR - 3.5,
        Paint()..color = Colors.white,
      );

      // Seed title preview pill above drag position
      if (scene.slingshotSeedTitle.trim().isNotEmpty) {
        final titleText = scene.slingshotSeedTitle.trim();
        final tp = _text(titleText, 11, Colors.white, w: FontWeight.w700);
        final pillRect = Rect.fromCenter(
          center: Offset(drag.dx, drag.dy - seedR - 16),
          width: tp.width + 16,
          height: tp.height + 8,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(pillRect, const Radius.circular(8)),
          Paint()..color = const Color(0xFF060914).withValues(alpha: 0.90),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(pillRect, const Radius.circular(8)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = neonEmerald.withValues(alpha: 0.85),
        );
        tp.paint(canvas, Offset(pillRect.left + 8, pillRect.top + 4));
      }
    }

    // 2. When seed is flying along trajectory
    if (scene.slingshotFlying && scene.slingshotFlightStart != null && scene.slingshotFlightEnd != null) {
      final start = scene.slingshotFlightStart!;
      final end = scene.slingshotFlightEnd!;
      final prog = scene.slingshotFlightProgress.clamp(0.0, 1.0);
      final currentPos = Offset.lerp(start, end, prog)!;

      // Comet tail trailing behind current position
      final tailProg = (prog - 0.22).clamp(0.0, 1.0);
      final tailStart = Offset.lerp(start, end, tailProg)!;

      final tailPaint = Paint()
        ..shader = LinearGradient(
          colors: [
            neonEmerald.withValues(alpha: 0.0),
            neonEmerald.withValues(alpha: 0.85),
            Colors.white,
          ],
        ).createShader(Rect.fromPoints(tailStart, currentPos))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.6
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(tailStart, currentPos, tailPaint);

      // Flying Seed Projectile Core
      canvas.drawCircle(
        currentPos,
        14.0,
        Paint()
          ..color = neonEmerald.withValues(alpha: 0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0),
      );
      canvas.drawCircle(
        currentPos,
        8.0,
        Paint()..color = Colors.white,
      );
    }
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

