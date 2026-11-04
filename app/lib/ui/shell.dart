import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/web3d/web_legend.dart';
import '../features/web3d/web_view_3d.dart';
import '../models/thread.dart';
import '../state/app_state.dart';
import 'editor.dart';
import 'insights_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'threads_screen.dart';

class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final status = context.select<AppState, AuthStatus>((s) => s.authStatus);
    switch (status) {
      case AuthStatus.unknown:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case AuthStatus.signedOut:
        return const AuthScreen();
      case AuthStatus.signedIn:
        return const HomeShell();
    }
  }
}

// ------------------------------------------------------------------ auth
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController(), _pass = TextEditingController(), _name = TextEditingController();
  bool _register = false, _hide = true;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final s = context.read<AppState>();
    _register
        ? await s.register(email: _email.text, password: _pass.text, name: _name.text)
        : await s.login(_email.text, _pass.text);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Icon(Icons.hub_rounded, size: 56, color: kCrimson),
                  const SizedBox(height: 12),
                  Text('Project Spider', textAlign: TextAlign.center, style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text('Your tasks, ideas and goals as one living web.', textAlign: TextAlign.center, style: t.bodyMedium),
                  const SizedBox(height: 28),
                  if (_register) ...[
                    TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Your name'), textInputAction: TextInputAction.next, validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your name' : null),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    validator: (v) => (v ?? '').contains('@') ? null : 'Enter a valid email',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _pass,
                    obscureText: _hide,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      helperText: _register ? 'At least 8 characters' : null,
                      suffixIcon: IconButton(icon: Icon(_hide ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _hide = !_hide), tooltip: 'Show or hide password'),
                    ),
                    autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                    onFieldSubmitted: (_) => _submit(),
                    validator: (v) => (v ?? '').length >= 8 ? null : 'Use at least 8 characters',
                  ),
                  if (s.authError != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(s.authError!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                  const SizedBox(height: 20),
                  FilledButton(onPressed: s.busy ? null : _submit, child: s.busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_register ? 'Create account' : 'Sign in')),
                  TextButton(onPressed: () => setState(() => _register = !_register), child: Text(_register ? 'I already have an account' : 'New here? Create an account')),
                  TextButton(onPressed: () => _serverDialog(context), child: const Text('Server settings')),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _serverDialog(BuildContext context) async {
  final s = context.read<AppState>();
  final c = TextEditingController(text: s.serverUrl);
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Server address'),
      content: TextField(controller: c, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'https://api.example.com')),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save'))],
    ),
  );
  if (ok == true) await s.setServerUrl(c.text);
}

// ------------------------------------------------------------------ shell
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _sub = s.notificationTaps.listen(_open);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = s.takeLaunchPayload();
      if (p != null) _open(p);
    });
  }

  void _open(String payload) {
    if (!mounted) return;
    if (payload == 'digest') {
      setState(() => _tab = 1);
    } else if (context.read<AppState>().threadById(payload) != null) {
      openThreadEditor(context, threadId: payload);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const pages = [WebTab(), ThreadsScreen(), InsightsScreen(), SettingsScreen()];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openThreadEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('New thread'),
        backgroundColor: kCrimson,
        foregroundColor: Colors.white,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.hub_outlined), selectedIcon: Icon(Icons.hub), label: 'Web'),
          NavigationDestination(icon: Icon(Icons.checklist_outlined), selectedIcon: Icon(Icons.checklist), label: 'Threads'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Insights'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ web tab
class WebTab extends StatefulWidget {
  const WebTab({super.key});
  @override
  State<WebTab> createState() => _WebTabState();
}

class _WebTabState extends State<WebTab> {
  final WebController _ctl = WebController();
  String? _selected;
  final Set<String> _hidden = {};
  bool _search = false;
  String _kw = '';

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final selected = _selected == null ? null : s.threadById(_selected!);
    return Stack(children: [
      Positioned.fill(
        child: WebView3D(
          threads: s.threads,
          spaces: s.spaces,
          controller: _ctl,
          selectedId: selected?.id,
          flashIds: s.flashIds,
          showDone: s.settings.showDone,
          hiddenSpaceIds: Set.of(_hidden),
          highlightKeyword: _search && _kw.trim().isNotEmpty ? _kw.trim() : null,
          reduceMotion: s.settings.reduceMotion,
          lowGraphics: s.settings.lowGraphics,
          onSelect: (id) => setState(() => _selected = id),
        ),
      ),
      SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(children: [
              const Text('Your web', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(width: 10),
              _LinkPill(s),
              const Spacer(),
              IconButton(tooltip: 'Search by keyword', icon: Icon(_search ? Icons.search_off : Icons.search), onPressed: () => setState(() { _search = !_search; _kw = ''; })),
              IconButton(tooltip: 'What do the shapes mean?', icon: const Icon(Icons.info_outline), onPressed: () => showWebLegend(context)),
              IconButton(tooltip: 'Fit everything', icon: const Icon(Icons.center_focus_strong_outlined), onPressed: _ctl.resetView),
            ]),
          ),
          if (_search)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: TextField(autofocus: true, decoration: const InputDecoration(hintText: 'Highlight a keyword', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => _kw = v)),
            ),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final sp in s.spaces)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: FilterChip(
                      avatar: CircleAvatar(backgroundColor: sp.color, radius: 6),
                      label: Text(sp.name),
                      selected: !_hidden.contains(sp.id),
                      onSelected: (on) => setState(() => on ? _hidden.remove(sp.id) : _hidden.add(sp.id)),
                    ),
                  ),
              ],
            ),
          ),
        ]),
      ),
      if (s.threads.isEmpty)
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.hub_outlined, size: 48),
              const SizedBox(height: 12),
              const Text('Your web is empty', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('Add your first thread and it appears here.', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: () => openThreadEditor(context), icon: const Icon(Icons.add), label: const Text('Add a thread')),
            ]),
          ),
        ),
      Positioned(
        right: 12,
        bottom: selected == null ? 90 : 190,
        child: Column(children: [
          IconButton.filledTonal(tooltip: 'Zoom in', icon: const Icon(Icons.add), onPressed: () => _ctl.zoomBy(1.4)),
          const SizedBox(height: 6),
          IconButton.filledTonal(tooltip: 'Zoom out', icon: const Icon(Icons.remove), onPressed: () => _ctl.zoomBy(1 / 1.4)),
        ]),
      ),
      if (selected != null)
        Positioned(left: 12, right: 12, bottom: 84, child: _SelectedCard(thread: selected, onFocus: () => _ctl.focusOn(selected.id), onClose: () => setState(() => _selected = null))),
    ]);
  }
}

class _LinkPill extends StatelessWidget {
  const _LinkPill(this.s);
  final AppState s;
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (s.link) {
      LinkStatus.live => ('LIVE', const Color(0xFF2ECC71)),
      LinkStatus.syncing => ('SYNCING', kBlue),
      LinkStatus.connecting => ('CONNECTING', Colors.amber),
      LinkStatus.offline => (s.pendingWrites > 0 ? 'OFFLINE · ${s.pendingWrites}' : 'OFFLINE', Colors.grey),
    };
    return Semantics(
      label: 'Connection: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: color)),
        ]),
      ),
    );
  }
}

class _SelectedCard extends StatelessWidget {
  const _SelectedCard({required this.thread, required this.onFocus, required this.onClose});
  final Thread thread;
  final VoidCallback onFocus, onClose;
  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final sp = s.spaceById(thread.spaceId);
    final overdue = thread.status != ThreadStatus.done && thread.dueAt != null && thread.dueAt!.isBefore(DateTime.now());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(radius: 6, backgroundColor: sp?.color ?? kBlue),
            const SizedBox(width: 8),
            Expanded(child: Text(thread.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: onClose),
          ]),
          Text('${sp?.name ?? 'No space'} · ${thread.type.name} · ${thread.dueAt == null ? 'no date' : fmtDue(thread.dueAt)}${overdue ? ' · overdue' : ''}',
              style: TextStyle(color: overdue ? kCrimson : null)),
          const SizedBox(height: 10),
          Row(children: [
            if (thread.status == ThreadStatus.todo) FilledButton.tonal(onPressed: () => s.setStatus(thread.id, ThreadStatus.doing), child: const Text('Start')),
            if (thread.status != ThreadStatus.done) ...[const SizedBox(width: 8), FilledButton(onPressed: () => s.setStatus(thread.id, ThreadStatus.done), child: const Text('Done'))],
            if (thread.status == ThreadStatus.done) FilledButton.tonal(onPressed: () => s.setStatus(thread.id, ThreadStatus.todo), child: const Text('Reopen')),
            const Spacer(),
            IconButton(tooltip: 'Zoom to it', icon: const Icon(Icons.zoom_in_map), onPressed: onFocus),
            TextButton(onPressed: () => openThreadEditor(context, threadId: thread.id), child: const Text('Open')),
          ]),
        ]),
      ),
    );
  }
}
