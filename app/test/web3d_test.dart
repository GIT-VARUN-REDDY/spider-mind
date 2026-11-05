import 'dart:ui' show Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:spider_mind/features/web3d/web_camera.dart';
import 'package:spider_mind/features/web3d/web_layout.dart';
import 'package:spider_mind/features/web3d/web_lod.dart';
import 'package:spider_mind/models/space.dart';
import 'package:spider_mind/models/thread.dart';

final DateTime now = DateTime.utc(2026, 11, 4, 10);

List<Space> spaces(int n) => [for (var i = 0; i < n; i++) Space(id: '${'s'.padRight(23, '0')}$i', name: 'S$i', colorHex: '#32B4FF', order: i)];

List<Thread> threads(int n, List<Space> sp) => [
      for (var i = 0; i < n; i++)
        Thread(
            id: '${'t'.padRight(24 - '$i'.length, '0')}$i',
            title: 'Thread $i',
            spaceId: sp[i % sp.length].id,
            createdAt: now.subtract(Duration(minutes: i)),
            updatedAt: now,
            priority: Priority.values[i % 3],
            dueAt: i % 4 == 0 ? null : now.add(Duration(days: i % 40, hours: 1)))
    ];

void main() {
  group('layout', () {
    test('deterministic and complete', () {
      final sp = spaces(3);
      final ts = threads(40, sp);
      final a = WebLayout.compute(threads: ts, spaces: sp, now: now);
      final b = WebLayout.compute(threads: ts, spaces: sp, now: now);
      expect(a.nodeCount, 40);
      for (final id in a.nodes.keys) {
        expect(a.nodes[id]!.position, b.nodes[id]!.position);
      }
    });
    test('no two nodes overlap and 500 threads stay fast', () {
      final sp = spaces(5);
      final ts = threads(500, sp);
      final sw = Stopwatch()..start();
      final l = WebLayout.compute(threads: ts, spaces: sp, now: now);
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(200));
      final pts = l.nodes.values.map((n) => n.position).toList();
      var minD = 1e9;
      for (var i = 0; i < pts.length; i++) {
        for (var j = i + 1; j < pts.length; j++) {
          final dx = pts[i].x - pts[j].x, dy = pts[i].y - pts[j].y;
          final d = dx * dx + dy * dy;
          if (d < minD) minD = d;
        }
      }
      expect(minD, greaterThan(0.5));
    });
    test('empty and single', () {
      expect(WebLayout.compute(threads: const [], spaces: const [], now: now).nodeCount, 0);
      final sp = spaces(1);
      expect(WebLayout.compute(threads: threads(1, sp), spaces: sp, now: now).nodeCount, 1);
    });
  });

  group('camera', () {
    test('fit keeps the whole web on screen at several aspect ratios', () {
      final sp = spaces(4);
      final l = WebLayout.compute(threads: threads(120, sp), spaces: sp, now: now);
      for (final size in const [[390.0, 700.0], [1200.0, 700.0], [700.0, 700.0]]) {
        final cam = WebCamera(width: size[0], height: size[1]);
        cam.fit(l.outerRadius, animate: false);
        for (final n in l.nodes.values) {
          final p = cam.project(n.position.x, n.position.y, n.position.z);
          expect(p.visible, isTrue);
          expect(p.x, greaterThan(0));
          expect(p.x, lessThan(size[0]));
          expect(p.y, greaterThan(0));
          expect(p.y, lessThan(size[1]));
        }
      }
    });
    test('nearer points project larger; pan follows the finger', () {
      final cam = WebCamera(width: 400, height: 600, distance: 30);
      final near = cam.project(0, -5, 0).scale;
      final far = cam.project(0, 5, 0).scale;
      expect(near, greaterThan(far));
      final before = cam.project(2, 1, 0);
      cam.panBy(30, 0);
      cam.snapNow();
      final after = cam.project(2, 1, 0);
      expect(after.x - before.x, closeTo(0, 40));
      cam.tPanX = cam.panX;
    });
    test('animation converges and zoom is clamped', () {
      final cam = WebCamera(width: 400, height: 600);
      cam.fit(10, animate: false);
      cam.zoomBy(1000);
      var steps = 0;
      while (cam.step(1 / 60) && steps < 600) {
        steps++;
      }
      expect(steps, lessThan(600));
      expect(cam.distance, closeTo(cam.minDistance, 1e-6));
      cam.zoomBy(1e-6);
      cam.step(10);
      expect(cam.distance, closeTo(cam.maxDistance, 1e-6));
    });
  });

  group('label LOD', () {
    test('budget shrinks when zoomed out', () {
      expect(labelBudget(0.8), lessThan(labelBudget(2.5)));
      expect(labelBudget(0.1), greaterThanOrEqualTo(4));
    });
    test('picks by importance without overlap and respects the budget', () {
      const a = LabelCandidate(id: 'a', x: 10, y: 10, w: 80, h: 14, importance: 1);
      const b = LabelCandidate(id: 'b', x: 20, y: 12, w: 80, h: 14, importance: 5);
      const c = LabelCandidate(id: 'c', x: 10, y: 100, w: 80, h: 14, importance: 3);
      const off = LabelCandidate(id: 'off', x: 390, y: 10, w: 80, h: 14, importance: 9);
      final ids = pickLabels([a, b, c, off], budget: 5, viewWidth: 400, viewHeight: 300);
      expect(ids, orderedEquals(['b', 'c']));
      expect(pickLabels([a, c], budget: 1, viewWidth: 400, viewHeight: 300), hasLength(1));
    });
    test('pickLabels respects obstacles', () {
      const b = LabelCandidate(id: 'b', x: 20, y: 12, w: 80, h: 14, importance: 5);
      final ids = pickLabels([b], budget: 5, viewWidth: 400, viewHeight: 300, obstacles: const [Rect.fromLTWH(10, 10, 100, 20)]);
      expect(ids, isEmpty);
    });
  });
}

