import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/misc.dart';
import '../models/thread.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'threads_screen.dart' show typeIcon;

Future<void> openThreadEditor(BuildContext context, {String? threadId, String? initialTitle, ThreadType? initialType}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => ThreadEditor(threadId: threadId, initialTitle: initialTitle, initialType: initialType),
  ));
}

class ThreadEditor extends StatefulWidget {
  const ThreadEditor({super.key, this.threadId, this.initialTitle, this.initialType});
  final String? threadId, initialTitle;
  final ThreadType? initialType;
  @override
  State<ThreadEditor> createState() => _ThreadEditorState();
}

class _ThreadEditorState extends State<ThreadEditor> {
  late final TextEditingController _title, _notes, _tag, _item;
  late ThreadType _type;
  late ThreadStatus _status;
  late Priority _prio;
  String? _space;
  DateTime? _due;
  List<Reminder> _reminders = [];
  List<ChecklistItem> _check = [];
  List<String> _tags = [], _links = [];
  Thread? _orig;
  List<ActivityEntry> _acts = [];

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _orig = widget.threadId == null ? null : s.threadById(widget.threadId!);
    final o = _orig;
    _title = TextEditingController(text: o?.title ?? widget.initialTitle ?? '');
    _notes = TextEditingController(text: o?.notes ?? '');
    _tag = TextEditingController();
    _item = TextEditingController();
    _type = o?.type ?? widget.initialType ?? ThreadType.task;
    _status = o?.status ?? ThreadStatus.todo;
    _prio = o?.priority ?? Priority.medium;
    _space = o?.spaceId ?? (s.spaces.isNotEmpty ? s.spaces.first.id : null);
    _due = o?.dueAt?.toLocal();
    _reminders = [...?o?.reminders];
    _check = [...?o?.checklist];
    _tags = [...?o?.tags];
    _links = [...?o?.links];
    if (o != null) s.activityFor(o.id).then((a) { if (mounted) setState(() => _acts = a); });
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _tag.dispose();
    _item.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final base = _due ?? DateTime.now().add(const Duration(hours: 1));
    final d = await showDatePicker(context: context, initialDate: base, firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now().add(const Duration(days: 3650)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (t == null) return;
    setState(() => _due = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _addCustomReminder() async {
    final base = _due ?? DateTime.now().add(const Duration(hours: 1));
    final d = await showDatePicker(context: context, initialDate: base, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 3650)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (t == null) return;
    _addReminder(DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  void _addReminder(DateTime at) {
    if (!at.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That time has already passed.')));
      return;
    }
    setState(() => _reminders = [..._reminders, Reminder.create(at.toUtc())]..sort((a, b) => a.at.compareTo(b.at)));
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Give the thread a title.')));
      return;
    }
    final s = context.read<AppState>();
    final o = _orig;
    if (o == null) {
      final t = s.createThread(title: title, type: _type, priority: _prio, spaceId: _space, dueAt: _due, reminders: _reminders, notes: _notes.text);
      final extra = t.copyWith(status: _status, tags: _tags, links: _links, checklist: _check);
      if (_status != ThreadStatus.todo || _tags.isNotEmpty || _links.isNotEmpty || _check.isNotEmpty) s.saveThread(extra);
      for (final l in _links) {
        final other = s.threadById(l);
        if (other != null && !other.links.contains(t.id)) s.saveThread(other.copyWith(links: [...other.links, t.id]));
      }
    } else {
      final removed = o.links.where((l) => !_links.contains(l));
      final added = _links.where((l) => !o.links.contains(l));
      s.saveThread(o.copyWith(
        title: title, notes: _notes.text, type: _type, status: _status, priority: _prio, spaceId: _space,
        dueAt: _due?.toUtc(), clearDueAt: _due == null, reminders: _reminders, tags: _tags, links: _links, checklist: _check,
      ));
      for (final l in removed) {
        final t = s.threadById(l);
        if (t != null) s.saveThread(t.copyWith(links: t.links.where((x) => x != o.id).toList()));
      }
      for (final l in added) {
        final t = s.threadById(l);
        if (t != null && !t.links.contains(o.id)) s.saveThread(t.copyWith(links: [...t.links, o.id]));
      }
    }
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final s = context.read<AppState>();
    final m = ScaffoldMessenger.of(context);
    final removed = s.deleteThread(_orig!.id);
    Navigator.pop(context);
    m.showSnackBar(SnackBar(content: const Text('Thread deleted'), action: SnackBarAction(label: 'Undo', onPressed: () { if (removed != null) s.restoreThread(removed); })));
  }

  Future<void> _pickLinks() async {
    final s = context.read<AppState>();
    final chosen = {..._links};
    final candidates = s.threads.where((t) => t.id != _orig?.id).toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(builder: (ctx, set) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.7,
          child: Column(children: [
            const Padding(padding: EdgeInsets.all(8), child: Text('Link to other threads', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            Expanded(
              child: candidates.isEmpty
                  ? const Center(child: Text('No other threads yet.'))
                  : ListView(children: [for (final t in candidates) CheckboxListTile(value: chosen.contains(t.id), title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis), secondary: Icon(typeIcon(t.type)), onChanged: (v) => set(() => v == true ? chosen.add(t.id) : chosen.remove(t.id)))]),
            ),
            Padding(padding: const EdgeInsets.all(12), child: SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')))),
          ]),
        ),
      )),
    );
    setState(() => _links = chosen.toList());
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    Widget label(String t) => Padding(padding: const EdgeInsets.only(top: 20, bottom: 8), child: Text(t.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)));
    final linked = [for (final id in _links) if (s.threadById(id) != null) s.threadById(id)!];
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Discard', onPressed: () => Navigator.pop(context)),
        title: Text(_orig == null ? 'New thread' : 'Edit thread'),
        actions: [
          if (_orig != null) IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _delete),
          Padding(padding: const EdgeInsets.only(right: 8), child: FilledButton(onPressed: _save, child: const Text('Save'))),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 40), children: [
        TextField(controller: _title, autofocus: _orig == null, textCapitalization: TextCapitalization.sentences, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700), decoration: const InputDecoration(hintText: 'What is this thread?')),
        label('Type'),
        SegmentedButton<ThreadType>(
          showSelectedIcon: false,
          segments: [for (final t in ThreadType.values) ButtonSegment(value: t, icon: Icon(typeIcon(t), size: 18), label: Text(t.name))],
          selected: {_type},
          onSelectionChanged: (v) => setState(() => _type = v.first),
        ),
        label('Status'),
        SegmentedButton<ThreadStatus>(
          showSelectedIcon: false,
          segments: const [ButtonSegment(value: ThreadStatus.todo, label: Text('To do')), ButtonSegment(value: ThreadStatus.doing, label: Text('Doing')), ButtonSegment(value: ThreadStatus.done, label: Text('Done'))],
          selected: {_status},
          onSelectionChanged: (v) => setState(() => _status = v.first),
        ),
        label('Priority'),
        SegmentedButton<Priority>(
          showSelectedIcon: false,
          segments: const [ButtonSegment(value: Priority.low, label: Text('Low')), ButtonSegment(value: Priority.medium, label: Text('Medium')), ButtonSegment(value: Priority.high, label: Text('High'))],
          selected: {_prio},
          onSelectionChanged: (v) => setState(() => _prio = v.first),
        ),
        label('Space'),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final sp in s.spaces) ChoiceChip(avatar: CircleAvatar(radius: 6, backgroundColor: sp.color), label: Text(sp.name), selected: _space == sp.id, onSelected: (_) => setState(() => _space = sp.id)),
        ]),
        label('Due'),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: _pickDue, icon: const Icon(Icons.event), label: Align(alignment: Alignment.centerLeft, child: Text(_due == null ? 'Set date and time' : fmtDue(_due))))),
          if (_due != null) IconButton(tooltip: 'Clear date', icon: const Icon(Icons.clear), onPressed: () => setState(() => _due = null)),
        ]),
        label('Reminders'),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final r in _reminders)
            InputChip(
              avatar: Icon(r.sentAt != null ? Icons.check : Icons.notifications_active_outlined, size: 16),
              label: Text(fmtDue(r.at)),
              onDeleted: () => setState(() => _reminders = _reminders.where((x) => x.id != r.id).toList()),
            ),
          if (_due != null) ...[
            ActionChip(label: const Text('+ At due time'), onPressed: () => _addReminder(_due!)),
            ActionChip(label: const Text('+ 1 hour before'), onPressed: () => _addReminder(_due!.subtract(const Duration(hours: 1)))),
            ActionChip(label: const Text('+ 1 day before'), onPressed: () => _addReminder(_due!.subtract(const Duration(days: 1)))),
          ],
          ActionChip(avatar: const Icon(Icons.add_alarm, size: 16), label: const Text('Custom'), onPressed: _addCustomReminder),
        ]),
        if (_due == null && _reminders.isEmpty) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Set a due date to get quick reminder presets.', style: TextStyle(fontSize: 12))),
        label('Notes'),
        TextField(controller: _notes, minLines: 3, maxLines: 8, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Details, context, links')),
        label('Checklist'),
        for (final c in _check)
          Row(children: [
            Checkbox(value: c.done, onChanged: (v) => setState(() => _check = [for (final x in _check) x.id == c.id ? ChecklistItem(id: x.id, text: x.text, done: v == true) : x])),
            Expanded(child: Text(c.text, style: TextStyle(decoration: c.done ? TextDecoration.lineThrough : null))),
            IconButton(tooltip: 'Remove', icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _check = _check.where((x) => x.id != c.id).toList())),
          ]),
        TextField(
          controller: _item,
          decoration: const InputDecoration(hintText: 'Add a step', prefixIcon: Icon(Icons.add)),
          onSubmitted: (v) {
            if (v.trim().isEmpty) return;
            setState(() => _check = [..._check, ChecklistItem.create(v.trim())]);
            _item.clear();
          },
        ),
        label('Tags'),
        Wrap(spacing: 8, children: [for (final t in _tags) InputChip(label: Text(t), onDeleted: () => setState(() => _tags = _tags.where((x) => x != t).toList()))]),
        const SizedBox(height: 6),
        TextField(
          controller: _tag,
          decoration: const InputDecoration(hintText: 'Add a tag', prefixIcon: Icon(Icons.sell_outlined)),
          onSubmitted: (v) {
            final t = v.trim().toLowerCase();
            if (t.isEmpty || _tags.contains(t)) return;
            setState(() => _tags = [..._tags, t]);
            _tag.clear();
          },
        ),
        if (_orig != null && _orig!.keywords.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Auto keywords: ${_orig!.keywords.join(', ')}', style: const TextStyle(fontSize: 12))),
        label('Linked threads'),
        for (final t in linked) ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(typeIcon(t.type), size: 18), title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis), trailing: IconButton(tooltip: 'Unlink', icon: const Icon(Icons.link_off, size: 18), onPressed: () => setState(() => _links = _links.where((x) => x != t.id).toList()))),
        TextButton.icon(onPressed: _pickLinks, icon: const Icon(Icons.add_link), label: const Text('Link a thread')),
        if (_orig != null) ...[
          label('Related by keyword'),
          for (final t in s.relatedTo(_orig!.id).where((t) => !_links.contains(t.id)).take(5)) ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.more_horiz, size: 18), title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis), onTap: () => openThreadEditor(context, threadId: t.id)),
          if (_acts.isNotEmpty) ...[
            label('History'),
            for (final a in _acts.take(8)) ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.history, size: 18), title: Text(a.message), subtitle: Text(fmtDue(a.at))),
          ],
        ],
      ]),
    );
  }
}
