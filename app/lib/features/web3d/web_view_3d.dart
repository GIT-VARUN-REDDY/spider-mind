import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../models/space.dart';
import '../../models/thread.dart';
import '../../models/urgency.dart';
import 'web_camera.dart';
import 'web_edges.dart';
import 'web_layout.dart';
import 'web_painter.dart';

class WebController extends ChangeNotifier {
  _WebView3DState? _s;
  void _attach(_WebView3DState s) => _s = s;
  void _detach(_WebView3DState s) {
    if (_s == s) _s = null;
  }

  void fit() => _s?._fit();
  void resetView() => _s?._fit(resetTilt: true);
  void focusOn(String threadId) => _s?._focus(threadId);
  void zoomBy(double factor) => _s?._zoom(factor);
}

class WebView3D extends StatefulWidget {
  const WebView3D({
    super.key,
    required this.threads,
    required this.spaces,
    required this.controller,
    required this.onSelect,
    this.selectedId,
    this.flashIds = const <String>{},
    this.showDone = false,
    this.showMembranes = true,
    this.radarActive = false,
    this.radarTargetId,
    this.focusThreadIds = const <String>{},
    this.slingshotActive = false,
    this.slingshotSeedTitle = '',
    this.onSlingshotFired,
    this.onSlingshotAimChanged,
    this.hiddenSpaceIds = const <String>{},
    this.highlightKeyword,
    this.reduceMotion = false,
    this.lowGraphics = false,
    this.timeTravelOffset = Duration.zero,
  });

  final List<Thread> threads;
  final List<Space> spaces;
  final WebController controller;
  final void Function(String? threadId) onSelect;
  final String? selectedId;
  final Set<String> flashIds;
  final bool showDone;
  final bool showMembranes;
  final bool radarActive;
  final String? radarTargetId;
  final Set<String> focusThreadIds;
  final bool slingshotActive;
  final String slingshotSeedTitle;
  final void Function(Vec3 worldPos, String? spaceId, UrgencyBand band)? onSlingshotFired;
  final void Function(double tension, String? spaceName, UrgencyBand band)? onSlingshotAimChanged;
  final Set<String> hiddenSpaceIds;
  final String? highlightKeyword;
  final bool reduceMotion;
  final bool lowGraphics;
  final Duration timeTravelOffset;

  @override
  State<WebView3D> createState() => _WebView3DState();
}

class _WebView3DState extends State<WebView3D> with SingleTickerProviderStateMixin {
  final WebCamera _cam = WebCamera();
  final WebScene _scene = WebScene();
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  late final Ticker _ticker;
  late WebPainter _painter;
  Duration _last = Duration.zero;
  bool _hasFit = false;
  bool _isAnimatingNodes = false;
  double _lastScale = 1;
  double _lastRotation = 0;
  Offset? _lastTouchPos;
  Size _size = Size.zero;
  int _lastTensionStep = 0;
  Offset? _slingshotScreenTarget;
  Vec3? _slingshotTargetWorld;
  String? _slingshotTargetSpaceId;
  UrgencyBand? _slingshotTargetBand;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    _painter = WebPainter(_scene, _cam, repaint: _frame);
    widget.controller._attach(this);
    _rebuildLayout();
  }

  @override
  void didUpdateWidget(WebView3D old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller._detach(this);
      widget.controller._attach(this);
    }
    final timeShifted = old.timeTravelOffset != widget.timeTravelOffset;
    final structural = !identical(old.threads, widget.threads) ||
        !identical(old.spaces, widget.spaces) ||
        old.showDone != widget.showDone ||
        old.hiddenSpaceIds != widget.hiddenSpaceIds ||
        timeShifted;
    if (structural) _rebuildLayout();
    for (final id in widget.flashIds) {
      if (!old.flashIds.contains(id)) {
        _scene.flashStart[id] = _scene.time;
        _scene.shockwaveStart[id] = _scene.time;
      }
    }
    if (widget.selectedId != old.selectedId && widget.selectedId != null && old.selectedId == null) {
      // keep the camera where the user left it; selection only highlights
    }
    _syncScene();
    _kick();
  }

  @override
  void dispose() {
    widget.controller._detach(this);
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _syncScene() {
    _scene
      ..selectedId = widget.selectedId
      ..keyword = widget.highlightKeyword
      ..showMembranes = widget.showMembranes
      ..radarActive = widget.radarActive
      ..radarTargetId = widget.radarTargetId
      ..focusThreadIds = widget.focusThreadIds
      ..slingshotActive = widget.slingshotActive
      ..slingshotSeedTitle = widget.slingshotSeedTitle
      ..reduceMotion = widget.reduceMotion
      ..lowGraphics = widget.lowGraphics;
  }

  void _rebuildLayout() {
    final simulatedNow = DateTime.now().add(widget.timeTravelOffset);
    final layout = WebLayout.compute(
      threads: widget.threads,
      spaces: widget.spaces,
      now: simulatedNow,
      showDone: widget.showDone,
      hiddenSpaceIds: widget.hiddenSpaceIds,
    );
    final bottleneckCount = widget.threads.where((t) {
      if (t.isDone) return false;
      final node = layout.nodes[t.id];
      return node != null && node.band == UrgencyBand.now;
    }).length;

    _scene
      ..layout = layout
      ..now = simulatedNow
      ..timeTravelOffset = widget.timeTravelOffset
      ..bottleneckCount = bottleneckCount
      ..byId = {for (final t in widget.threads) t.id: t}
      ..edges = buildWebEdges(widget.threads.where((t) => layout.nodes.containsKey(t.id)).toList());
    _syncScene();
    if (!_hasFit && layout.nodeCount > 0 && _size != Size.zero) {
      _fit(resetTilt: true, animate: false);
    }
    _kick();
  }

  void _fit({bool resetTilt = false, bool animate = true}) {
    _cam.width = _size.width;
    _cam.height = _size.height;
    if (resetTilt) {
      _cam.tYaw = 0;
      _cam.tPitch = WebCamera.defaultPitch;
    }
    _cam.fit(_scene.layout.outerRadius + 2, animate: animate && !widget.reduceMotion);
    _hasFit = true;
    _kick();
  }

  void _focus(String id) {
    final p = _scene.layout.positionOf(id);
    if (p == null) return;
    _cam.focusOn(p);
    if (widget.reduceMotion) _cam.snapNow();
    _kick();
  }

  void _zoom(double f) {
    _cam.zoomBy(f);
    if (widget.reduceMotion) _cam.snapNow();
    _kick();
  }

  bool _stepNodePositions(double dt) {
    var stillMoving = false;
    final k = widget.reduceMotion ? 1.0 : (dt * 10.0).clamp(0.04, 1.0);
    final targetNodes = _scene.layout.nodes;
    for (final entry in targetNodes.entries) {
      final id = entry.key;
      final target = entry.value.position;
      final current = _scene.animatedPositions[id];
      if (current == null) {
        _scene.animatedPositions[id] = target;
      } else {
        final dist = (target - current).length;
        if (dist > 0.005) {
          _scene.animatedPositions[id] = Vec3.lerp(current, target, k);
          stillMoving = true;
        } else {
          _scene.animatedPositions[id] = target;
        }
      }
    }
    _scene.animatedPositions.removeWhere((id, _) => !targetNodes.containsKey(id));
    return stillMoving;
  }

  bool get _needsAnimation {
    if (_cam.isMoving) return true;
    if (_painter.isAnimatingLabels) return true;
    if (_isAnimatingNodes) return true;
    if (_scene.slingshotFlying || _scene.slingshotDragging) return true;
    if (widget.reduceMotion) {
      return _scene.flashStart.isNotEmpty || _scene.shockwaveStart.isNotEmpty || _scene.radarActive;
    }
    return true;
  }

  void _kick() {
    if (!mounted) return;
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
    _frame.value++;
  }

  void _tick(Duration t) {
    final dt = _last == Duration.zero ? 1 / 60 : ((t - _last).inMicroseconds / 1e6).clamp(0.0, 0.1).toDouble();
    _last = t;
    _scene.time += dt;
    _cam.step(dt);
    _isAnimatingNodes = _stepNodePositions(dt);
    _scene.flashStart.removeWhere((_, s) => _scene.time - s > 2.6);
    _scene.shockwaveStart.removeWhere((_, s) => _scene.time - s > 2.2);
    if (_scene.radarActive && !widget.reduceMotion) {
      _scene.radarAngle = (_scene.radarAngle + dt * 1.6) % 6.283185307179586;
      _scene.radarRadius += dt * 3.5;
      if (_scene.radarRadius > _scene.layout.outerRadius + 3) {
        _scene.radarRadius = 0.0;
      }
    }
    if (_scene.slingshotFlying) {
      _scene.slingshotFlightProgress += dt * 2.8;
      if (_scene.slingshotFlightProgress >= 1.0) {
        _scene.slingshotFlying = false;
        _scene.slingshotFlightProgress = 1.0;
        final targetWorld = _slingshotTargetWorld ?? Vec3.zero;
        final targetSpaceId = _slingshotTargetSpaceId;
        final targetBand = _slingshotTargetBand ?? UrgencyBand.now;
        _scene.shockwaveStart['__slingshot__'] = _scene.time;
        widget.onSlingshotFired?.call(targetWorld, targetSpaceId, targetBand);
      }
    }
    _frame.value++;
    if (!_needsAnimation) _ticker.stop();
  }

  void _tap(Offset pos) {
    widget.onSelect(_painter.hitTestNode(pos));
  }

  @override
  Widget build(BuildContext context) {
    _scene.dark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      if (size != _size) {
        _size = size;
        _cam.width = size.width;
        _cam.height = size.height;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_scene.layout.nodeCount > 0) _fit(resetTilt: !_hasFit, animate: false);
        });
      }
      return Semantics(
        label: 'Web view of your threads. Drag to rotate, pinch to zoom, tap a node to select.',
        child: Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) _zoom(e.scrollDelta.dy < 0 ? 1.12 : 1 / 1.12);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _tap(d.localPosition),
            onDoubleTap: () => _fit(),
            onScaleStart: (d) {
              if (widget.slingshotActive) {
                _lastTensionStep = 0;
                _scene.slingshotDragging = true;
                _scene.slingshotAnchor = d.localFocalPoint;
                _scene.slingshotDrag = d.localFocalPoint;
                _scene.slingshotTension = 0.0;
                _kick();
                return;
              }
              _cam.isDragging = true;
              _cam.yawVelocity = 0;
              _cam.pitchVelocity = 0;
              _lastScale = 1;
              _lastRotation = 0;
              _lastTouchPos = d.localFocalPoint;
              _kick();
            },
            onScaleUpdate: (d) {
              if (widget.slingshotActive && _scene.slingshotDragging) {
                final anchor = _scene.slingshotAnchor ?? d.localFocalPoint;
                final drag = d.localFocalPoint;
                _scene.slingshotDrag = drag;
                final delta = drag - anchor;
                final dist = delta.distance;
                final tension = (dist / 160.0).clamp(0.0, 1.0);
                _scene.slingshotTension = tension;

                // Tactile feedback on tension steps (25%, 50%, 75%, 90%)
                final step = (tension * 4).floor();
                if (step != _lastTensionStep && step > 0) {
                  _lastTensionStep = step;
                  HapticFeedback.selectionClick();
                }

                // Calculate trajectory and landing point
                if (dist > 12.0) {
                  final launchDir = -delta / dist;
                  final launchPowerPx = math.min(_size.width * 0.85, dist * 3.4);
                  final screenTarget = anchor + launchDir * launchPowerPx;
                  _slingshotScreenTarget = screenTarget;

                  // Unproject to web plane
                  final world = _cam.unprojectToWebPlane(screenTarget);
                  _slingshotTargetWorld = world;

                  // Determine nearest ring & spoke
                  final r = math.sqrt(world.x * world.x + world.y * world.y);
                  WebRing? bestRing;
                  double bestRingDiff = double.infinity;
                  for (final ring in _scene.layout.rings) {
                    final diff = (ring.radius - r).abs();
                    if (diff < bestRingDiff) {
                      bestRingDiff = diff;
                      bestRing = ring;
                    }
                  }

                  // Angle in web plane: clockwise from -pi/2
                  final worldAngle = math.atan2(-world.y, world.x);
                  WebSpoke? bestSpoke;
                  double bestSpokeDiff = double.infinity;
                  for (final spoke in _scene.layout.spokes) {
                    var diff = (spoke.angle - worldAngle).abs();
                    if (diff > math.pi) diff = 2 * math.pi - diff;
                    if (diff < bestSpokeDiff) {
                      bestSpokeDiff = diff;
                      bestSpoke = spoke;
                    }
                  }

                  _slingshotTargetSpaceId = bestSpoke?.spaceId;
                  _slingshotTargetBand = bestRing?.band ?? UrgencyBand.now;
                  _scene.slingshotTargetSpokeName = bestSpoke?.name ?? 'Web';
                  _scene.slingshotTargetBand = _slingshotTargetBand;
                  _scene.slingshotTargetColor = bestSpoke?.color;

                  widget.onSlingshotAimChanged?.call(tension, bestSpoke?.name, _slingshotTargetBand!);
                }
                _kick();
                return;
              }
              _lastTouchPos = d.localFocalPoint;
              if (d.pointerCount >= 2) {
                _cam.panBy(d.focalPointDelta.dx, d.focalPointDelta.dy);
                if (_lastScale > 0) _cam.zoomBy(d.scale / _lastScale);
                _lastScale = d.scale;
                final dRot = d.rotation - _lastRotation;
                _lastRotation = d.rotation;
                if (dRot.abs() > 0.001) {
                  _cam.twoFingerRotate(dRot);
                }
              } else {
                _cam.orbit(d.focalPointDelta.dx, d.focalPointDelta.dy, touchPos: d.localFocalPoint);
              }
              if (widget.reduceMotion) _cam.snapNow();
              _kick();
            },
            onScaleEnd: (d) {
              if (widget.slingshotActive && _scene.slingshotDragging) {
                _scene.slingshotDragging = false;
                if (_scene.slingshotTension > 0.12 && _slingshotScreenTarget != null) {
                  HapticFeedback.heavyImpact();
                  _scene.slingshotFlying = true;
                  _scene.slingshotFlightProgress = 0.0;
                  _scene.slingshotFlightStart = _scene.slingshotDrag;
                  _scene.slingshotFlightEnd = _slingshotScreenTarget;
                }
                _kick();
                return;
              }
              _cam.isDragging = false;
              if (!widget.reduceMotion) {
                _cam.fling(
                  d.velocity.pixelsPerSecond.dx,
                  d.velocity.pixelsPerSecond.dy,
                  touchPos: _lastTouchPos,
                );
              }
              _kick();
            },
            child: CustomPaint(size: Size.infinite, painter: _painter, isComplex: true, willChange: true),
          ),
        ),
      );
    });
  }
}
