import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'web_layout.dart';

/// Result of projecting one world point to the screen.
class ProjectedPoint {
  const ProjectedPoint(this.x, this.y, this.scale, this.depth, this.visible);

  final double x;
  final double y;

  /// Pixels per world unit at this point (perspective: nearer = larger).
  final double scale;

  /// Distance from the eye along the view axis; larger = farther.
  final double depth;
  final bool visible;
}

/// Pure-Dart perspective camera for the web. World: x right, y up (in the
/// web plane), z = priority height. `pitch` is the tilt from a top-down view
/// (0 = straight down, ~pi/2 = edge on). The camera keeps a current and a
/// target state so gestures and `fit` can animate smoothly.
class WebCamera {
  WebCamera({
    this.width = 1,
    this.height = 1,
    double yaw = 0,
    double pitch = defaultPitch,
    double distance = 30,
    double panX = 0,
    double panY = 0,
  })  : yaw = yaw,
        pitch = pitch,
        distance = distance,
        panX = panX,
        panY = panY,
        tYaw = yaw,
        tPitch = pitch,
        tDistance = distance,
        tPanX = panX,
        tPanY = panY;

  /// About 50 degrees of tilt: the whole web reads as a structure.
  static const double defaultPitch = 0.87;
  static const double minPitch = 0.12;
  static const double maxPitch = 1.45;

  double width;
  double height;
  double yaw;
  double pitch;
  double distance;
  double panX;
  double panY;
  double tYaw;
  double tPitch;
  double tDistance;
  double tPanX;
  double tPanY;

  /// Inertial velocities applied upon fling release.
  double yawVelocity = 0;
  double pitchVelocity = 0;

  /// True during active touch gestures to ensure zero-lag 1:1 reaction.
  bool isDragging = false;

  /// Distance that frames the whole web (set by [fit]); zoom limits derive from it.
  double fitDistance = 30;

  double get focal => math.min(width, height) * 1.1;
  double get minDistance => fitDistance * 0.12;
  double get maxDistance => fitDistance * 2.2;

  /// 1 = framed to fit, >1 = zoomed in.
  double get zoomLevel => fitDistance / distance;

  ProjectedPoint project(double x, double y, double z) {
    final dx = x - panX;
    final dy = y - panY;
    final cy = math.cos(yaw);
    final sy = math.sin(yaw);
    final x1 = dx * cy - dy * sy;
    final y1 = dx * sy + dy * cy;
    final cp = math.cos(pitch);
    final sp = math.sin(pitch);
    final up = y1 * cp + z * sp;
    final toward = z * cp - y1 * sp;
    final zc = distance - toward;
    if (zc < 0.5) return ProjectedPoint(width / 2, height / 2, 0, zc, false);
    final s = focal / zc;
    return ProjectedPoint(width / 2 + x1 * s, height / 2 - up * s, s, zc, true);
  }

  /// Frames a disc of [radius] (world units) with margin, at the default tilt.
  void fit(double radius, {bool animate = true}) {
    final r = math.max(radius, 1.0) * 1.12;
    final cp = math.cos(defaultPitch);
    final sx = 0.47 * width / r;
    final sy = 0.47 * height / (r * math.max(cp, 0.35) + r * 0.25);
    final s = math.max(math.min(sx, sy), 1e-3);
    final d = math.max(focal / s, r * 1.8);
    fitDistance = d;
    tDistance = d;
    tPitch = defaultPitch;
    tPanX = 0;
    tPanY = 0;
    yawVelocity = 0;
    pitchVelocity = 0;
    if (!animate) _snap();
  }

  /// Orbit rotation with natural direction.
  /// When [touchPos] is provided, rotates based on the visual center of the web:
  /// - Right of center (rx > 0): slide down -> rotates clockwise (right side moves down with finger).
  /// - Left of center (rx < 0): slide down -> rotates counter-clockwise (left side moves down with finger).
  /// - Above center (ry < 0): slide left -> rotates counter-clockwise (top moves left with finger).
  /// - Down / below center (ry > 0): slide left -> rotates clockwise (bottom moves left with finger).
  /// Works consistently across all zoom levels and pans.
  void orbit(double dxPx, double dyPx, {Offset? touchPos}) {
    double dYaw;
    double dPitch;

    if (touchPos != null) {
      final center = project(0, 0, 0);
      final rx = touchPos.dx - center.x;
      final ry = touchPos.dy - center.y;
      final r = math.sqrt(rx * rx + ry * ry);
      final rEff = math.max(r, 40.0);

      // Direct angular rotation around the visual web center (invariant to zoom)
      dYaw = -(rx * dyPx - ry * dxPx) / (rEff * rEff);

      final centerFactor = (1.0 - (rx.abs() / math.max(width * 0.45, 80.0))).clamp(0.0, 1.0);
      dPitch = -dyPx * 0.0055 * centerFactor;
    } else {
      dYaw = -dxPx * 0.0075;
      dPitch = -dyPx * 0.0055;
    }

    tYaw += dYaw;
    tPitch = (tPitch + dPitch).clamp(minPitch, maxPitch).toDouble();
    if (isDragging) {
      // Instant reaction during touch drag - zero input latency
      yaw = tYaw;
      pitch = tPitch;
    }
  }

  /// Two-finger rotation.
  void twoFingerRotate(double deltaRad) {
    tYaw += deltaRad;
    if (isDragging) {
      yaw = tYaw;
    }
  }

  /// Fling momentum on touch release for buttery smooth inertial coasting.
  void fling(double vxPx, double vyPx, {Offset? touchPos}) {
    double vYaw;
    double vPitch;

    if (touchPos != null) {
      final center = project(0, 0, 0);
      final rx = touchPos.dx - center.x;
      final ry = touchPos.dy - center.y;
      final r = math.sqrt(rx * rx + ry * ry);
      final rEff = math.max(r, 40.0);

      vYaw = -(rx * vyPx - ry * vxPx) / (rEff * rEff);
      final centerFactor = (1.0 - (rx.abs() / math.max(width * 0.45, 80.0))).clamp(0.0, 1.0);
      vPitch = -vyPx * 0.0055 * centerFactor;
    } else {
      vYaw = -vxPx * 0.0075;
      vPitch = -vyPx * 0.0055;
    }

    yawVelocity = vYaw.clamp(-16.0, 16.0);
    pitchVelocity = vPitch.clamp(-6.0, 6.0);
  }

  void zoomBy(double factor) {
    if (factor <= 0) return;
    tDistance = (tDistance / factor).clamp(minDistance, maxDistance).toDouble();
    if (isDragging) {
      distance = tDistance;
    }
  }

  /// Drag the content by a screen delta (the point under the finger follows it).
  void panBy(double dxPx, double dyPx) {
    final s = focal / math.max(distance, 0.5);
    final vx = -dxPx / s;
    final vy = dyPx / (s * math.max(math.cos(pitch), 0.2));
    final cy = math.cos(yaw);
    final sy = math.sin(yaw);
    tPanX += vx * cy + vy * sy;
    tPanY += -vx * sy + vy * cy;
    if (isDragging) {
      panX = tPanX;
      panY = tPanY;
    }
  }

  void focusOn(Vec3 p, {double zoom = 2.4}) {
    yawVelocity = 0;
    pitchVelocity = 0;
    tPanX = 0;
    tPanY = 0;
    panX = 0;
    panY = 0;
    // Rotate web so target node faces front-and-center while ring center stays centered
    final angle = math.atan2(p.y, p.x);
    tYaw = -angle - math.pi / 2;
    tDistance = (fitDistance / zoom).clamp(minDistance, maxDistance).toDouble();
  }

  /// Advances the animation with responsive damping and smooth velocity coasting.
  bool step(double dt) {
    if (isDragging) {
      return true;
    }

    // Apply smooth inertial coasting on flick
    if (yawVelocity.abs() > 0.001 || pitchVelocity.abs() > 0.001) {
      tYaw += yawVelocity * dt;
      tPitch = (tPitch + pitchVelocity * dt).clamp(minPitch, maxPitch).toDouble();
      
      final friction = math.exp(-4.0 * dt);
      yawVelocity *= friction;
      pitchVelocity *= friction;
      
      if (yawVelocity.abs() < 0.001) yawVelocity = 0;
      if (pitchVelocity.abs() < 0.001) pitchVelocity = 0;
    }

    // High responsiveness smoothing (fast reaction without jitter)
    final k = 1 - math.exp(-22 * dt);
    yaw += (tYaw - yaw) * k;
    pitch += (tPitch - pitch) * k;
    distance += (tDistance - distance) * k;
    panX += (tPanX - panX) * k;
    panY += (tPanY - panY) * k;
    if (!isMoving) {
      _snap();
      return false;
    }
    return true;
  }

  bool get isMoving =>
      yawVelocity.abs() > 0.001 ||
      pitchVelocity.abs() > 0.001 ||
      (tYaw - yaw).abs() > 1e-3 ||
      (tPitch - pitch).abs() > 1e-3 ||
      (tDistance - distance).abs() > 1e-2 * math.max(1.0, distance * 0.05) ||
      (tPanX - panX).abs() > 1e-3 ||
      (tPanY - panY).abs() > 1e-3;

  void _snap() {
    yaw = tYaw;
    pitch = tPitch;
    distance = tDistance;
    panX = tPanX;
    panY = tPanY;
    yawVelocity = 0;
    pitchVelocity = 0;
  }

  void snapNow() => _snap();
}

