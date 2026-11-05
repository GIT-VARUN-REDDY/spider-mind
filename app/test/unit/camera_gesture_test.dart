import 'package:flutter_test/flutter_test.dart';
import 'package:spider_mind/features/web3d/web_camera.dart';

void main() {
  group('WebCamera Touch-Direction Orbit and Fling Tests', () {
    test('sliding from UP to DOWN on the RIGHT side rotates web clockwise so right rim moves DOWN with finger', () {
      final cam = WebCamera(width: 400, height: 800, distance: 30);
      cam.fit(15, animate: false);

      // Node on the right side of the web in world space (x=10, y=0, z=0)
      final initialRightPoint = cam.project(10, 0, 0);
      expect(initialRightPoint.x, greaterThan(200.0)); // to the right of center

      // User touches the right side of the screen and drags DOWN (dy > 0)
      cam.isDragging = true;
      cam.orbit(0, 30, touchPos: const Offset(350, 400));
      cam.isDragging = false;
      cam.snapNow();

      final updatedRightPoint = cam.project(10, 0, 0);

      // The right rim point on screen MUST move DOWN (y increases in screen coordinates)
      expect(
        updatedRightPoint.y,
        greaterThan(initialRightPoint.y),
        reason: 'Right rim must move down when sliding down on right side, not oppositely',
      );
    });

    test('sliding from DOWN to UP on the RIGHT side rotates web counter-clockwise so right rim moves UP with finger', () {
      final cam = WebCamera(width: 400, height: 800, distance: 30);
      cam.fit(15, animate: false);

      final initialRightPoint = cam.project(10, 0, 0);

      // User touches the right side of the screen and drags UP (dy < 0)
      cam.isDragging = true;
      cam.orbit(0, -30, touchPos: const Offset(350, 400));
      cam.isDragging = false;
      cam.snapNow();

      final updatedRightPoint = cam.project(10, 0, 0);

      // The right rim point on screen MUST move UP (y decreases in screen coordinates)
      expect(
        updatedRightPoint.y,
        lessThan(initialRightPoint.y),
        reason: 'Right rim must move up when sliding up on right side',
      );
    });

    test('sliding from RIGHT to LEFT in UPPER RIGHT moves upper right nodes to the LEFT with finger', () {
      final cam = WebCamera(width: 400, height: 800, distance: 30);
      cam.fit(15, animate: false);

      // Node in upper right of the web (x=7, y=7, z=0)
      final initialUpperRightPoint = cam.project(7, 7, 0);

      // User touches upper right of the screen and slides to the LEFT (dx < 0)
      cam.isDragging = true;
      cam.orbit(-30, 0, touchPos: const Offset(320, 250));
      cam.isDragging = false;
      cam.snapNow();

      final updatedUpperRightPoint = cam.project(7, 7, 0);

      // The upper right point on screen MUST move LEFT (x decreases in screen coordinates)
      expect(
        updatedUpperRightPoint.x,
        lessThan(initialUpperRightPoint.x),
        reason: 'Upper right nodes must move left when sliding right-to-left, not oppositely',
      );
    });

    test('sliding from RIGHT to LEFT generally moves web nodes to the LEFT with finger', () {
      final cam = WebCamera(width: 400, height: 800, distance: 30);
      cam.fit(15, animate: false);

      final initialTopPoint = cam.project(0, 8, 0);

      // Slide right to left (dx < 0)
      cam.isDragging = true;
      cam.orbit(-30, 0, touchPos: const Offset(200, 400));
      cam.isDragging = false;
      cam.snapNow();

      final updatedTopPoint = cam.project(0, 8, 0);
      expect(
        updatedTopPoint.x,
        lessThan(initialTopPoint.x),
        reason: 'Nodes must move left when sliding right-to-left',
      );
    });

    test('sliding from LEFT to RIGHT generally moves web nodes to the RIGHT with finger', () {
      final cam = WebCamera(width: 400, height: 800, distance: 30);
      cam.fit(15, animate: false);

      final initialTopPoint = cam.project(0, 8, 0);

      // Slide left to right (dx > 0)
      cam.isDragging = true;
      cam.orbit(30, 0, touchPos: const Offset(200, 400));
      cam.isDragging = false;
      cam.snapNow();

      final updatedTopPoint = cam.project(0, 8, 0);
      expect(
        updatedTopPoint.x,
        greaterThan(initialTopPoint.x),
        reason: 'Nodes must move right when sliding left-to-right',
      );
    });

    test('sliding from UP to DOWN on the LEFT side moves left rim DOWN with finger', () {
      final cam = WebCamera(width: 400, height: 800, distance: 30);
      cam.fit(15, animate: false);

      final initialLeftPoint = cam.project(-10, 0, 0);
      expect(initialLeftPoint.x, lessThan(200.0)); // to the left of center

      // User touches the left side of the screen and drags DOWN (dy > 0)
      cam.isDragging = true;
      cam.orbit(0, 30, touchPos: const Offset(50, 400));
      cam.isDragging = false;
      cam.snapNow();

      final updatedLeftPoint = cam.project(-10, 0, 0);

      // The left rim point on screen MUST move DOWN (y increases in screen coordinates)
      expect(
        updatedLeftPoint.y,
        greaterThan(initialLeftPoint.y),
        reason: 'Left rim must move down when sliding down on left side',
      );
    });

    test('fling on the right side coasts smoothly with clockwise angular velocity', () {
      final cam = WebCamera(width: 400, height: 800, distance: 30);
      cam.fit(15, animate: false);

      // Fling down on the right side
      cam.fling(0, 1000, touchPos: const Offset(350, 400));

      // Clockwise rotation means negative yawVelocity so right side moves down
      expect(cam.yawVelocity, lessThan(0));
    });

    test('fling on upper right from right to left coasts with counter-clockwise angular velocity', () {
      final cam = WebCamera(width: 400, height: 800, distance: 30);
      cam.fit(15, animate: false);

      // Fling left on the upper right side
      cam.fling(-1000, 0, touchPos: const Offset(320, 250));

      // Counter-clockwise rotation means positive yawVelocity so upper nodes continue moving left
      expect(cam.yawVelocity, greaterThan(0));
    });
  });
}
