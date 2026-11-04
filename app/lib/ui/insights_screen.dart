import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/misc.dart';
import '../models/thread.dart';
import '../state/app_state.dart';
import 'editor.dart';
import 'theme.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final ins = s.insights;
    final c = ins.counts;
    final moves = s.nextMoves();
    final hub = s.hub;
    final loose = s.looseEnds;
    Widget stat(String label, int v, {Color? color}) => Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(children: [Text('$v', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: color)), Text(label, style: const TextStyle(fontSize: 12))]),
            ),
          ),
        );
    Widget head(String t) => Padding(padding: const EdgeInsets.fromLTRB(4, 22, 4, 8), child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)));
    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 100), children: [
        const Text('Insights', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        Row(children: [stat('Open', c.open), const SizedBox(width: 8), stat('Overdue', c.overdue, color: c.overdue > 0 ? kCrimson : null), const SizedBox(width: 8), stat('Today', c.dueToday), const SizedBox(width: 8), stat('Next 7 days', c.dueNext7)]),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.local_fire_department, color: kCrimson),
                const SizedBox(width: 8),
                Text(ins.streak == 0 ? 'Finish something today to start a streak' : '${ins.streak}-day streak', style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 14),
              SizedBox(height: 90, child: _Bars(ins.completedByDay)),
              const SizedBox(height: 4),
              const Text('Threads completed, last 14 days', style: TextStyle(fontSize: 11)),
            ]),
          ),
        ),
        head('Next move'),
        if (moves.isEmpty) const Text('No open tasks. Add one to get a suggestion.'),
        for (final m in moves)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              title: Text(m.thread.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(m.reason),
              trailing: IconButton(tooltip: 'Mark done', icon: const Icon(Icons.check_circle_outline), onPressed: () => s.setStatus(m.thread.id, ThreadStatus.done)),
              onTap: () => openThreadEditor(context, threadId: m.thread.id),
            ),
          ),
        head('Hub'),
        if (hub == null) const Text('Link or tag threads with shared keywords and your most connected one shows up here.') else Card(
          child: ListTile(
            leading: const Icon(Icons.hub, color: kBlue),
            title: Text(hub.title, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Connected to ${s.degrees[hub.id]} threads'),
            onTap: () => openThreadEditor(context, threadId: hub.id),
          ),
        ),
        head('Loose ends  ·  ${loose.length}'),
        if (loose.isEmpty) const Text('Every open thread is connected.'),
        for (final t in loose.take(6))
          ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.link_off, size: 18), title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis), onTap: () => openThreadEditor(context, threadId: t.id)),
        head('Live activity'),
        if (s.activity.isEmpty) const Text('Changes from all your devices appear here.'),
        for (final a in s.activity.take(15)) ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.bolt, size: 18, color: kBlue), title: Text(a.message, maxLines: 2, overflow: TextOverflow.ellipsis), subtitle: Text(fmtDue(a.at))),
      ]),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars(this.days);
  final List<DayCount> days;
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _BarsPainter(days, Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.onSurface), size: Size.infinite);
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.days, this.color, this.ink);
  final List<DayCount> days;
  final Color color, ink;
  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    final maxV = days.map((d) => d.count).fold<int>(1, (a, b) => b > a ? b : a);
    final w = size.width / days.length;
    for (var i = 0; i < days.length; i++) {
      final h = days[i].count == 0 ? 3.0 : (size.height - 4) * days[i].count / maxV;
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(i * w + w * 0.18, size.height - h, w * 0.64, h), const Radius.circular(4));
      canvas.drawRRect(r, Paint()..color = days[i].count == 0 ? ink.withValues(alpha: 0.12) : color);
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter o) => o.days != days;
}
