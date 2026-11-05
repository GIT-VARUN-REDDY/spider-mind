import 'package:flutter_test/flutter_test.dart';
import 'package:spider_mind/features/web3d/web_camera.dart';

void main() {
  group('WebCamera Center-Relative Orbit and Fling Tests', () {
    test('RIGHT of center: slide down moves right side down with finger', () {
      final cam = WebCamera(width: 400, height: 800, distance: 30);
      cam.fit(15, animate: false);

      final initialRightPoint = cam.project(10, 0, 0);
      expect(initialRightPoint.x, greaterThan(200.0));

      // Touch right of center, slide DOWN (dy > 0)
      cam.isDragging = true;
      cam.orbit(0, 30, touchPos: const Offset(350, 400));
      cam.isDragging = false;
      cam.snapNow();

      final updatedRightPoint = cam.project(10, 0, 0);
      expect(updatedRightPoint.y, greaterThan(initialRightPoint.y));
    });

    test('RIGHT of center: slide up moves right side up with finger', () {
      final cam = WebCamera(width: 400, height: 800, distance: 30);
      cam.fit(15, animate: false);

      final initialRightPoint = cam.project(10, 0, 0);

      // Touch right of center, slide UP (dy < 0)
      cam.isDragging = true;
      cam.orbit(0, -30, touchPos: const Offset(350, 400));
      cam.isDragging = false;
      cam.snapNow();

      final updatedRightPoint = cam.project(10, 0, 0);
      expect(updatedRightPoint.y, lessThan(initialRightPoint.y));
    });

    test('LEFT of center: slide down moves left side down with finger', () {
      final cam = WebCamera(width: 400, height: 800, distance: 30);
      cam.fit(15, animate: false);

      final initialLeftPoint = cam.project(-10, 0, 0);
      expect(initialLeftPoint.x, lessThan(200.0));

      // Touch left of center, slide DOWN (dy > 0)
      cam.isDragging = true;
      cam.orbit(0, 30, touchPos: const Offset(50, 400));
      cam.isDragging = false;
      cam.snapNow();

      final updatedLeftPoint = cam.project(-10, 0, 0);
      expect(updatedLeftPoint.y, greaterThan(initialLeftPoint.y));
    });

    test('LEFT of center: slide up moves left side up with finger', () {
      final cam = WebCamera(width: 400, height: 800, distance: 30);
      cam.fit(15, animate: false);

      final initialLeftPoint = cam.project(-10, 0, 0);

      // Touch left of center, slide UP (dy < 0)
      cam.isDragging = true;
      cam.orbit(0, -30, touchPos: const Offset(50, 400));
      cam.isDragging = false;
      cam.snapNow();

      final updatedLeftPoint = cam.project(-10, 0, 0);
      expect(updatedLeftPoint.y, lessThan(initialLeftPoint.y));
    });

    test('ABOVE center: slide left moves top part to the left with finger', () {
      final cam = WebCamera(width: 400, height: 800, distance: 30);
      cam.fit(15, animate: false);

      final initialTopPoint = cam.project(0, 8, 0);

      // Touch above center, slide LEFT (dx < 0)
      cam.isDragging = true;
      cam.orbit(-30, 0, touchPos: const Offset(200, 200));
      cam.isDragging = false;
      cam.snapNow();

      final updatedTopPoint = cam.project(0, 8, 0);
      expect(updatedTopPoint.x, lessThan(initialTopPoint.x));
    });

    test('DOWN / BELOW center: slide left moves bottom part to the left with finger', () {
      final cam = WebCamera(width: 400, height: 800, distance: 30);
      cam.fit(15, animate: false);

      final initialBottomPoint = cam.project(0, -8, 0);

      // Touch below center, slide LEFT (dx < 0)
      cam.isDragging = true;
      cam.orbit(-30, 0, touchPos: const Offset(200, 600));
      cam.isDragging = false;
      cam.snapNow();

      final updatedBottomPoint = cam.project(0, -8, 0);
      expect(updatedBottomPoint.x, lessThan(initialBottomPoint.x));
    });

    test('DOWN / BELOW center: slide right moves bottom part to the right with finger', () {
      final cam = WebCamera(width: 400, height: 800, distance: 30);
      cam.fit(15, animate: false);

      final initialBottomPoint = cam.project(0, -8, 0);

      // Touch below center, slide RIGHT (dx > 0)
      cam.isDragging = true;
      cam.orbit(30, 0, touchPos: const Offset(200, 600));
      cam.isDragging = false;
      cam.snapNow();

      final updatedBottomPoint = cam.project(0, -8, 0);
      expect(updatedBottomPoint.x, greaterThan(initialBottomPoint.x));
    });

    test('All directions maintain identical sliding directions even after zooms', () {
      for (final zoomFactor in [0.5, 1.0, 2.5]) {
        final cam = WebCamera(width: 400, height: 800, distance: 30);
        cam.fit(15, animate: false);
        cam.zoomBy(zoomFactor);
        cam.snapNow();

        final center = cam.project(0, 0, 0);

        // Right side slide down
        final rightNodeBefore = cam.project(6, 0, 0);
        cam.orbit(0, 25, touchPos: Offset(center.x + 100, center.y));
        cam.snapNow();
        final rightNodeAfter = cam.project(6, 0, 0);
        expect(rightNodeAfter.y, greaterThan(rightNodeBefore.y), reason: 'Zoom $zoomFactor right slide down');

        // Above center slide left
        final topNodeBefore = cam.project(0, 6, 0);
        cam.orbit(-25, 0, touchPos: Offset(center.x, center.y - 100));
        cam.snapNow();
        final topNodeAfter = cam.project(0, 6, 0);
        expect(topNodeAfter.x, lessThan(topNodeBefore.x), reason: 'Zoom $zoomFactor top slide left');

        // Below center slide left
        final bottomNodeBefore = cam.project(0, -6, 0);
        cam.orbit(-25, 0, touchPos: Offset(center.x, center.y + 100));
        cam.snapNow();
        final bottomNodeAfter = cam.project(0, -6, 0);
        expect(bottomNodeAfter.x, lessThan(bottomNodeBefore.x), reason: 'Zoom $zoomFactor bottom slide left');
      }
    });

    test('fling coasts smoothly in matching direction', () {
      final cam = WebCamera(width: 400, height: 800, distance: 30);
      cam.fit(15, animate: false);

      // Fling down on right of center
      cam.fling(0, 1000, touchPos: const Offset(350, 400));
      expect(cam.yawVelocity, lessThan(0));

      // Fling left above center
      cam.fling(-1000, 0, touchPos: const Offset(200, 200));
      expect(cam.yawVelocity, greaterThan(0));

      // Fling left below center
      cam.fling(-1000, 0, touchPos: const Offset(200, 600));
      expect(cam.yawVelocity, lessThan(0));
    });

    test('two-finger rotation rotates web in natural direction', () {
      final cam = WebCamera(width: 400, height: 800, distance: 30);
      cam.fit(15, animate: false);

      final rightNodeBefore = cam.project(10, 0, 0);

      // Two-finger clockwise twist (deltaRad > 0)
      cam.isDragging = true;
      cam.twoFingerRotate(0.1);
      cam.isDragging = false;
      cam.snapNow();

      final rightNodeAfter = cam.project(10, 0, 0);

      // Right node moves DOWN in screen space when turning clockwise
      expect(
        rightNodeAfter.y,
        greaterThan(rightNodeBefore.y),
        reason: 'Clockwise two-finger twist must move right node down',
      );
    });
  });
}
