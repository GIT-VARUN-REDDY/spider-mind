import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:spider_mind/features/web3d/web_camera.dart';

void main() {
  group('WebCamera Center Invariance & Two-Finger Movement Tests', () {
    test('center of the ring (0, 0, 0) remains pinned to center of viewport when rotating at origin', () {
      final cam = WebCamera(width: 400, height: 800, distance: 30);
      cam.fit(15, animate: false);

      // Initial center
      final p0 = cam.project(0, 0, 0);
      expect(p0.x, closeTo(200.0, 1e-4));
      expect(p0.y, closeTo(400.0, 1e-4));

      // Rotate horizontally (yaw)
      for (var deg = 0; deg <= 360; deg += 30) {
        cam.tYaw = deg * math.pi / 180.0;
        cam.snapNow();
        final p = cam.project(0, 0, 0);
        expect(p.x, closeTo(200.0, 1e-4), reason: 'X drift at yaw=$deg deg');
        expect(p.y, closeTo(400.0, 1e-4), reason: 'Y drift at yaw=$deg deg');
      }

      // Rotate vertically (pitch)
      for (var pDeg = 15; pDeg <= 80; pDeg += 15) {
        cam.tPitch = pDeg * math.pi / 180.0;
        cam.snapNow();
        final p = cam.project(0, 0, 0);
        expect(p.x, closeTo(200.0, 1e-4), reason: 'X drift at pitch=$pDeg deg');
        expect(p.y, closeTo(400.0, 1e-4), reason: 'Y drift at pitch=$pDeg deg');
      }

      // Zooming in and out keeps center at center
      cam.zoomBy(2.5);
      cam.snapNow();
      final pZoomIn = cam.project(0, 0, 0);
      expect(pZoomIn.x, closeTo(200.0, 1e-4));
      expect(pZoomIn.y, closeTo(400.0, 1e-4));
    });

    test('two fingers panBy translates the web so corner threads become visible', () {
      final cam = WebCamera(width: 400, height: 800, distance: 30);
      cam.fit(15, animate: false);

      // A thread located in a far corner
      const cornerX = 14.0;
      const cornerY = 14.0;
      final beforePan = cam.project(cornerX, cornerY, 0);

      // User drags two fingers across the screen by 120px left and 80px up
      cam.isDragging = true;
      cam.panBy(-120, -80);
      cam.isDragging = false;
      cam.snapNow();

      final afterPan = cam.project(cornerX, cornerY, 0);
      // The corner thread has moved closer to the view center
      expect(afterPan.x, lessThan(beforePan.x));
      expect(afterPan.y, lessThan(beforePan.y));

      // Reset view with fit() brings ring center back to exact viewport center
      cam.fit(15, animate: false);
      final pReset = cam.project(0, 0, 0);
      expect(pReset.x, closeTo(200.0, 1e-4));
      expect(pReset.y, closeTo(400.0, 1e-4));
    });

    test('single finger orbit never changes the center point even after two-finger pan', () {
      final cam = WebCamera(width: 400, height: 800, distance: 30);
      cam.fit(15, animate: false);

      // Pan with 2 fingers
      cam.isDragging = true;
      cam.panBy(100, 50);
      cam.isDragging = false;
      cam.snapNow();

      final pCenterBefore = cam.project(0, 0, 0);

      // Single finger orbit in various directions
      for (final delta in [const Offset(40, 20), const Offset(-50, 30), const Offset(0, -60)]) {
        cam.isDragging = true;
        cam.orbit(delta.dx, delta.dy, touchPos: const Offset(320, 350));
        cam.isDragging = false;
        cam.snapNow();

        final pCenterAfter = cam.project(0, 0, 0);
        expect(pCenterAfter.x, closeTo(pCenterBefore.x, 1e-4), reason: 'Center X shifted during single-finger orbit');
        expect(pCenterAfter.y, closeTo(pCenterBefore.y, 1e-4), reason: 'Center Y shifted during single-finger orbit');
      }
    });
  });
}
