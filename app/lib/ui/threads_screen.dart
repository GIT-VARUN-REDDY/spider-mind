import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/thread.dart';
import '../state/app_state.dart';
import 'editor.dart';
import 'theme.dart';

IconData typeIcon(ThreadType t) => switch (t) {
      ThreadType.task => Icons.circle_outlined,
      ThreadType.idea => Icons.diamond_outlined,
      ThreadType.question => Icons.hexagon_outlined,
      ThreadType.goal => Icons.star_border,
    };

class ThreadsScreen extends StatefulWidget {
  const ThreadsScreen({super.key});
  @override
  State<ThreadsScreen> createState() => _ThreadsScreenState();
}

class _ThreadsScreenState extends State<ThreadsScreen> {
  String _q = '';
  ThreadType? _type;
  bool _openOnly = false;

  List<(String, List<Thread>)> _groups(List<Thread> all) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final g = <String, List<Thread>>{for (final k in ['Overdue', 'Today', 'This week', 'This month', 'Next month', 'This year', 'Later', 'No date', 'Done']) k: []};
    for (final t in all) {
      if (t.isDone) {
        g['Done']!.add(t);
        continue;
      }
      final d = t.dueAt?.toLocal();
      if (d == null) {
        g['No date']!.add(t);
      } else if (d.isBefore(now)) {
        g['Overdue']!.add(t);
      } else {
        final days = DateTime(d.year, d.month, d.day).difference(today).inDays;
        final nextMonthYear = today.month == 12 ? today.year + 1 : today.year;
        final nextMonth = today.month == 12 ? 1 : today.month + 1;
        if (days == 0) {
          g['Today']!.add(t);
        } else if (days <= 7) {
          g['This week']!.add(t);
        } else if (d.year == today.year && d.month == today.month) {
          g['This month']!.add(t);
        } else if (d.year == nextMonthYear && d.month == nextMonth) {
          g['Next month']!.add(t);
        } else if (d.year == today.year) {
          g['This year']!.add(t);
        } else {
          g['Later']!.add(t);
        }
      }
    }
    for (final l in g.values) {
      l.sort((a, b) => (a.dueAt ?? DateTime(2100)).compareTo(b.dueAt ?? DateTime(2100)));
    }
    return [for (final e in g.entries) if (e.value.isNotEmpty) (e.key, e.value)];
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final q = _q.trim().toLowerCase();
    final list = s.threads.where((t) {
      if (_type != null && t.type != _type) return false;
      if (_openOnly && t.isDone) return false;
      return q.isEmpty || t.title.toLowerCase().contains(q) || t.tags.any((x) => x.toLowerCase().contains(q)) || t.notes.toLowerCase().contains(q);
    }).toList();
    final groups = _groups(list);
    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Threads', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            TextField(decoration: const InputDecoration(hintText: 'Search threads', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => _q = v)),
          ]),
        ),
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            Padding(padding: const EdgeInsets.all(4), child: FilterChip(label: const Text('Open only'), selected: _openOnly, onSelected: (v) => setState(() => _openOnly = v))),
            for (final t in ThreadType.values)
              Padding(padding: const EdgeInsets.all(4), child: FilterChip(avatar: Icon(typeIcon(t), size: 16), label: Text(t.name), selected: _type == t, onSelected: (v) => setState(() => _type = v ? t : null))),
          ]),
        ),
        Expanded(
          child: groups.isEmpty
              ? Center(child: Text(s.threads.isEmpty ? 'No threads yet. Tap New thread.' : 'Nothing matches.'))
              : RefreshIndicator(
                  onRefresh: s.refresh,
                  child: ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 100), children: [
                    for (final (name, items) in groups) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
                        child: Text('${name.toUpperCase()}  ·  ${items.length}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: name == 'Overdue' ? kCrimson : null)),
                      ),
                      for (final t in items) _Row(t),
                    ]
                  ]),
                ),
        ),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.t);
  final Thread t;
  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final sp = s.spaceById(t.spaceId);
    final overdue = !t.isDone && t.dueAt != null && t.dueAt!.isBefore(DateTime.now());
    return Dismissible(
      key: ValueKey(t.id),
      background: Container(color: const Color(0xFF2ECC71), alignment: Alignment.centerLeft, padding: const EdgeInsets.only(left: 20), child: const Icon(Icons.check, color: Colors.white)),
      secondaryBackground: Container(color: kCrimson, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
      confirmDismiss: (dir) async {
        final m = ScaffoldMessenger.of(context);
        if (dir == DismissDirection.startToEnd) {
          s.setStatus(t.id, t.isDone ? ThreadStatus.todo : ThreadStatus.done);
          return false;
        }
        final removed = s.deleteThread(t.id);
        m.showSnackBar(SnackBar(content: const Text('Thread deleted'), action: SnackBarAction(label: 'Undo', onPressed: () { if (removed != null) s.restoreThread(removed); })));
        return true;
      },
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 3),
        child: ListTile(
          minVerticalPadding: 10,
          leading: Icon(typeIcon(t.type), color: sp?.color ?? kBlue),
          title: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, decoration: t.isDone ? TextDecoration.lineThrough : null)),
          subtitle: Text('${sp?.name ?? ''}${t.dueAt == null ? '' : ' · ${fmtDue(t.dueAt)}'}${t.status == ThreadStatus.doing ? ' · in progress' : ''}', style: TextStyle(color: overdue ? kCrimson : null)),
          trailing: t.reminders.any((r) => r.sentAt == null && r.at.isAfter(DateTime.now())) ? const Icon(Icons.notifications_active_outlined, size: 18) : null,
          onTap: () => openThreadEditor(context, threadId: t.id),
        ),
      ),
    );
  }
}
