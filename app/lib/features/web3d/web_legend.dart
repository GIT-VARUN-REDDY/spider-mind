import 'package:flutter/material.dart';

import 'web_painter.dart';

Future<void> showWebLegend(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _Legend(),
  );
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget row(Widget icon, String title, String sub) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            SizedBox(width: 44, height: 32, child: Center(child: icon)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: t.titleSmall),
                Text(sub, style: t.bodySmall),
              ]),
            ),
          ]),
        );
    Widget shape(IconData i, {Color c = kBlue}) => Icon(i, color: c, size: 24);
    Widget head(String s) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 2),
          child: Text(s.toUpperCase(), style: t.labelSmall?.copyWith(letterSpacing: 1.4, fontWeight: FontWeight.w800)),
        );
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          shrinkWrap: true,
          children: [
            Text('How to read your web', style: t.titleLarge),
            head('Where a thread sits'),
            row(const Icon(Icons.donut_large, color: kBlue), 'Spoke = space', 'Each space is an arm of the web, in its own colour.'),
            row(const Icon(Icons.radar, color: kCrimson), 'Ring = urgency', 'Centre is NOW, then tomorrow, this week, this month, next month, this year, later. Done is outermost.'),
            row(const Icon(Icons.layers, color: kBlue), 'Depth = priority', 'High priority sits nearer to you, low is further away.'),
            head('Shape = type'),
            row(shape(Icons.circle_outlined), 'Task', 'Something to do.'),
            row(shape(Icons.diamond_outlined), 'Idea', 'A thought to keep.'),
            row(shape(Icons.hexagon_outlined), 'Question', 'Something to find out.'),
            row(shape(Icons.star_border), 'Goal', 'A bigger outcome. Drawn larger.'),
            head('Fill = status'),
            row(shape(Icons.radio_button_unchecked), 'Hollow', 'To do.'),
            row(shape(Icons.circle), 'Solid with spinning arc', 'In progress. The arc shows checklist progress.'),
            row(shape(Icons.check_circle, c: Colors.grey), 'Dim with a tick', 'Done.'),
            head('Signals & Living Physics'),
            row(const Icon(Icons.warning_amber_rounded, color: kCrimson), 'Pulsing red halo', 'Overdue.'),
            row(const Icon(Icons.wifi_tethering, color: kBlue), 'Blue ripple', 'Just changed on another device.'),
            row(const Icon(Icons.timeline, color: kBlue), 'Solid curved strand', 'You linked these two threads. Living fiber-optic pulses flow along the silk.'),
            row(const Icon(Icons.more_horiz, color: kBlue), 'Dotted strand', 'They share a keyword.'),
            row(const Icon(Icons.auto_awesome, color: kBlue), 'Constellation sails', 'Translucent geometric hulls span between tasks in the same space. They crystallize and solidify as project tasks are completed.'),
            row(const Icon(Icons.radar, color: Color(0xFF00F5FF)), 'Spider Radar Focus', 'Circular sensory sonar sweep that dims background distraction and locks your focus onto the highest priority Next Moves.'),
            row(const Icon(Icons.gps_fixed, color: Color(0xFF00FF88)), 'Slingshot Quick-Capture', 'Pull back an elastic silk sling on the web canvas and release to launch and inject new thread seeds directly into target orbits.'),
            row(const Icon(Icons.mic, color: Color(0xFFD946EF)), 'Cinematic Voice-to-Web', 'Dictate tasks with real-time acoustic spider waveforms. Extracts space, due date, priority, and automatically weaves silk links directly into the web.'),
            head('Moving around'),
            row(const Icon(Icons.touch_app, color: kBlue), 'Drag, pinch, two-finger twist', 'Rotate, zoom, tilt. Double tap to fit everything.'),
          ],
        ),
      ),
    );
  }
}
