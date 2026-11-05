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

class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    final status = context.select<AppState, AuthStatus>((s) => s.authStatus);

    final isTest = WidgetsBinding.instance.runtimeType.toString().toLowerCase().contains('test');
    if ((!_splashDone && !isTest) || status == AuthStatus.unknown) {
      return SplashScreen(
        onComplete: () {
          if (mounted) {
            setState(() => _splashDone = true);
          }
        },
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: switch (status) {
        AuthStatus.unknown => const SizedBox(),
        AuthStatus.signedOut => const AuthScreen(),
        AuthStatus.signedIn => const HomeShell(),
      },
    );
  }
}

// ------------------------------------------------------------------ splash
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.onComplete});

  final VoidCallback? onComplete;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _loadCtrl;
  late AnimationController _pulseCtrl;
  late Animation<double> _progress;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.35, end: 0.75).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _loadCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
    _progress = CurvedAnimation(parent: _loadCtrl, curve: Curves.easeInOutCubic);

    _loadCtrl.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) widget.onComplete?.call();
      });
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _loadCtrl.dispose();
    super.dispose();
  }

  String _loadingMessage(double p) {
    if (p < 0.25) return 'Initializing SpiderMind engine...';
    if (p < 0.55) return 'Connecting to spider-mind.onrender.com...';
    if (p < 0.80) return 'Synchronizing 3D neural constellation...';
    if (p < 0.98) return 'Calibrating interactive web canvas...';
    return 'SpiderMind online.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF03040A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Full-bleed native SpiderMind splash artwork
          Image.asset(
            'assets/images/splash.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox(),
          ),

          // 2. Breathing radiant neon glow over the center spider emblem
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              return Center(
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: kCrimson.withValues(alpha: _pulse.value * 0.45),
                        blurRadius: 90,
                        spreadRadius: 15,
                      ),
                      BoxShadow(
                        color: kBlue.withValues(alpha: _pulse.value * 0.25),
                        blurRadius: 110,
                        spreadRadius: 20,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // 3. Bottom real-time loading status and glowing progress bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AnimatedBuilder(
                    animation: _loadCtrl,
                    builder: (context, child) {
                      final val = _progress.value.clamp(0.0, 1.0);
                      final pct = (val * 100).toInt();
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _loadingMessage(val),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.white.withValues(alpha: 0.85),
                                  letterSpacing: 0.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '$pct%',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: kBlue,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            height: 6,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    width: constraints.maxWidth * val,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(6),
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFFFF2A44), Color(0xFF32B4FF)],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: kCrimson.withValues(alpha: 0.8),
                                          blurRadius: 10,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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

  InputDecoration _inputDeco(String label, {Widget? suffix, String? helper}) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      helperStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 14),
      filled: true,
      fillColor: const Color(0xFF0C1022),
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kBlue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kCrimson, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kCrimson, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      backgroundColor: const Color(0xFF03040A),
      body: Stack(
        children: [
          // Background ambient cyber gradient
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF03040A),
                gradient: RadialGradient(
                  center: const Alignment(0, -0.45),
                  radius: 1.1,
                  colors: [
                    kCrimson.withValues(alpha: 0.20),
                    kBlue.withValues(alpha: 0.08),
                    const Color(0xFF03040A),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Form(
                    key: _form,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Center(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(color: kCrimson.withValues(alpha: 0.55), blurRadius: 36, spreadRadius: 3),
                              BoxShadow(color: kBlue.withValues(alpha: 0.35), blurRadius: 48, spreadRadius: 4),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Image.asset(
                              'assets/images/logo.png',
                              width: 96,
                              height: 96,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(Icons.hub_rounded, size: 56, color: kCrimson),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Color(0xFFFF2A44), Color(0xFFFFFFFF), Color(0xFF32B4FF)],
                        ).createShader(bounds),
                        child: const Text(
                          'SPIDERMIND',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 4.0,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Plan it. Track it. Own your day.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.75),
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 32),
                      if (_register) ...[
                        TextFormField(
                          controller: _name,
                          style: const TextStyle(color: Colors.white, fontSize: 15),
                          decoration: _inputDeco('Your name'),
                          textInputAction: TextInputAction.next,
                          validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your name' : null,
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextFormField(
                        controller: _email,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        decoration: _inputDeco('Email'),
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        validator: (v) => (v ?? '').contains('@') ? null : 'Enter a valid email',
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _pass,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        obscureText: _hide,
                        decoration: _inputDeco(
                          'Password',
                          helper: _register ? 'At least 8 characters' : null,
                          suffix: IconButton(
                            icon: Icon(
                              _hide ? Icons.visibility : Icons.visibility_off,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                            onPressed: () => setState(() => _hide = !_hide),
                            tooltip: 'Show or hide password',
                          ),
                        ),
                        autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                        onFieldSubmitted: (_) => _submit(),
                        validator: (v) => (v ?? '').length >= 8 ? null : 'Use at least 8 characters',
                      ),
                      if (s.authError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            s.authError!,
                            style: const TextStyle(color: Color(0xFFFF5252), fontSize: 13),
                          ),
                        ),
                      const SizedBox(height: 22),
                      Container(
                        height: 50,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF2A44), Color(0xFF007AFF)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: kCrimson.withValues(alpha: 0.45),
                              blurRadius: 18,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: s.busy ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: s.busy
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Text(
                                  _register ? 'Create account' : 'Sign in',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.15))),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Text(
                              'OR',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.45),
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                          Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.15))),
                        ],
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: s.busy ? null : () => s.signInWithGoogle(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.20)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          backgroundColor: const Color(0xFF0C1022),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.network(
                              'https://www.gstatic.com/images/branding/product/2x/googleg_48dp.png',
                              width: 22,
                              height: 22,
                              errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata, color: Colors.white, size: 26),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Continue with Google',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () => setState(() => _register = !_register),
                        child: Text(
                          _register ? 'I already have an account' : 'New here? Create an account',
                          style: const TextStyle(
                            color: kBlue,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
