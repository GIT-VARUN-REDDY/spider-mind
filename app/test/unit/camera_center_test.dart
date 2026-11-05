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
  });
}
