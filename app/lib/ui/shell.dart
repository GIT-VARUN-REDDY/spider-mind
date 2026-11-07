import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/misc.dart';

import '../features/voice/voice_hud.dart';
import '../features/web3d/web_layout.dart';
import '../features/web3d/web_legend.dart';
import '../features/web3d/web_view_3d.dart';
import '../models/space.dart';
import '../models/thread.dart';
import '../models/urgency.dart';
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
                            key: const ValueKey('password_toggle_btn'),
                            icon: Icon(
                              _hide ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              color: _hide ? Colors.white.withValues(alpha: 0.6) : kBlue,
                            ),
                            onPressed: () => setState(() => _hide = !_hide),
                            tooltip: _hide ? 'Show password' : 'Hide password',
                          ),
                        ),
                        autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                        onFieldSubmitted: (_) => _submit(),
                        validator: (v) => (v ?? '').length >= 8 ? null : 'Use at least 8 characters',
                      ),
                      if (!_register) ...[
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            key: const ValueKey('forgot_password_btn'),
                            onPressed: () => showForgotPasswordDialog(context, initialEmail: _email.text),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              visualDensity: VisualDensity.compact,
                            ),
                            child: const Text(
                              'Forgot password?',
                              style: TextStyle(
                                color: kBlue,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
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

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // Re-evaluate calendar shifts immediately when user unlocks phone or returns next day
      context.read<AppState>().refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppState>().user;
    final isUnverified = user != null && !user.isVerified;
    const pages = [WebTab(), ThreadsScreen(), InsightsScreen(), SettingsScreen()];
    return Scaffold(
      body: Column(
        children: [
          if (isUnverified)
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF160D1E),
                border: Border(bottom: BorderSide(color: kCrimson.withValues(alpha: 0.4))),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.mark_email_unread_outlined, size: 20, color: kCrimson),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Verify your email to secure your Mind Web.',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
                        ),
                      ),
                      TextButton(
                        onPressed: () => showEmailVerificationDialog(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('Verify', style: TextStyle(color: kBlue, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(child: IndexedStack(index: _tab, children: pages)),
        ],
      ),
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

Future<void> showEmailVerificationDialog(BuildContext context) async {
  final state = context.read<AppState>();
  final user = state.user;
  if (user == null) return;

  final codeCtrl = TextEditingController();
  var isSubmitting = false;
  var isResending = false;
  String? errorMsg;
  String? infoMsg;

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF0B0F1E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0x3332B4FF)),
            ),
            title: const Row(
              children: [
                Icon(Icons.mark_email_unread_rounded, color: kCrimson, size: 26),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Email Verification',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'We sent a 6-digit verification code to:\n${user.email}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: codeCtrl,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 8,
                      fontFamily: 'monospace',
                    ),
                    decoration: InputDecoration(
                      hintText: '000000',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.25),
                        fontSize: 26,
                        letterSpacing: 8,
                      ),
                      counterText: '',
                      filled: true,
                      fillColor: const Color(0xFF141A2E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0x4432B4FF)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: kBlue, width: 2),
                      ),
                    ),
                  ),
                  if (errorMsg != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorMsg!,
                      style: const TextStyle(color: Color(0xFFFF5252), fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (infoMsg != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      infoMsg!,
                      style: const TextStyle(color: Color(0xFF2ECC71), fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: isResending
                        ? null
                        : () async {
                            setDialogState(() {
                              isResending = true;
                              errorMsg = null;
                              infoMsg = null;
                            });
                            final ok = await state.resendVerification(user.email);
                            setDialogState(() {
                              isResending = false;
                              if (ok) {
                                infoMsg = 'New code sent to ${user.email}';
                              } else {
                                errorMsg = 'Failed to resend. Please try again.';
                              }
                            });
                          },
                    icon: isResending
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh_rounded, size: 16, color: kBlue),
                    label: Text(
                      isResending ? 'Sending...' : 'Resend Code',
                      style: const TextStyle(color: kBlue, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('Later', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kCrimson),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final code = codeCtrl.text.trim();
                        if (code.length < 4) {
                          setDialogState(() => errorMsg = 'Enter the 6-digit code');
                          return;
                        }
                        setDialogState(() {
                          isSubmitting = true;
                          errorMsg = null;
                        });
                        final ok = await state.verifyCode(email: user.email, code: code);
                        if (!ctx.mounted) return;
                        if (ok) {
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: Color(0xFF1E824C),
                              content: Text('🎉 Email verified successfully!'),
                            ),
                          );
                        } else {
                          setDialogState(() {
                            isSubmitting = false;
                            errorMsg = state.authError ?? 'Invalid or expired code';
                          });
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Verify'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> showForgotPasswordDialog(BuildContext context, {String? initialEmail}) async {
  final state = context.read<AppState>();
  final emailCtrl = TextEditingController(text: initialEmail?.trim() ?? '');
  final codeCtrl = TextEditingController();
  final newPassCtrl = TextEditingController();
  final confirmPassCtrl = TextEditingController();

  var step = 1; // 1 = enter email, 2 = enter code & new password
  var isSubmitting = false;
  var isResending = false;
  var hideNewPass = true;
  var hideConfirmPass = true;
  String? errorMsg;
  String? infoMsg;

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF0B0F1E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0x3332B4FF)),
            ),
            title: Row(
              children: [
                const Icon(Icons.lock_reset_rounded, color: kCrimson, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    step == 1 ? 'Forgot Password' : 'Reset Password',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (step == 1) ...[
                      Text(
                        'Enter your account email to receive a 6-digit password reset code.',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        autofocus: true,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        decoration: InputDecoration(
                          labelText: 'Account Email',
                          labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 14),
                          prefixIcon: const Icon(Icons.email_outlined, color: kBlue, size: 20),
                          filled: true,
                          fillColor: const Color(0xFF141A2E),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0x4432B4FF)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: kBlue, width: 2),
                          ),
                        ),
                      ),
                    ] else ...[
                      Text(
                        'Enter the 6-digit code sent to ${emailCtrl.text.trim()} and choose a new password.',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: codeCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 8,
                          fontFamily: 'monospace',
                        ),
                        decoration: InputDecoration(
                          hintText: '000000',
                          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 24, letterSpacing: 8),
                          counterText: '',
                          filled: true,
                          fillColor: const Color(0xFF141A2E),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0x4432B4FF)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: kBlue, width: 2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: newPassCtrl,
                        obscureText: hideNewPass,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        decoration: InputDecoration(
                          labelText: 'New Password (min 8 chars)',
                          labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13),
                          prefixIcon: const Icon(Icons.lock_outline, color: kBlue, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              hideNewPass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              color: hideNewPass ? Colors.white.withValues(alpha: 0.6) : kBlue,
                              size: 20,
                            ),
                            tooltip: hideNewPass ? 'Show password' : 'Hide password',
                            onPressed: () => setDialogState(() => hideNewPass = !hideNewPass),
                          ),
                          filled: true,
                          fillColor: const Color(0xFF141A2E),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0x4432B4FF)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: kBlue, width: 2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: confirmPassCtrl,
                        obscureText: hideConfirmPass,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        decoration: InputDecoration(
                          labelText: 'Confirm New Password',
                          labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13),
                          prefixIcon: const Icon(Icons.lock_outline, color: kBlue, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              hideConfirmPass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              color: hideConfirmPass ? Colors.white.withValues(alpha: 0.6) : kBlue,
                              size: 20,
                            ),
                            tooltip: hideConfirmPass ? 'Show password' : 'Hide password',
                            onPressed: () => setDialogState(() => hideConfirmPass = !hideConfirmPass),
                          ),
                          filled: true,
                          fillColor: const Color(0xFF141A2E),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0x4432B4FF)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: kBlue, width: 2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: () => setDialogState(() {
                              step = 1;
                              errorMsg = null;
                              infoMsg = null;
                            }),
                            child: const Text('Change Email', style: TextStyle(color: Color(0xFFA0AEC0), fontSize: 12)),
                          ),
                          TextButton.icon(
                            onPressed: isResending
                                ? null
                                : () async {
                                    setDialogState(() {
                                      isResending = true;
                                      errorMsg = null;
                                      infoMsg = null;
                                    });
                                    final ok = await state.forgotPassword(emailCtrl.text.trim());
                                    setDialogState(() {
                                      isResending = false;
                                      if (ok) {
                                        infoMsg = 'Code resent to ${emailCtrl.text.trim()}';
                                      } else {
                                        errorMsg = state.authError ?? 'Failed to resend code';
                                      }
                                    });
                                  },
                            icon: isResending
                                ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.refresh_rounded, size: 15, color: kBlue),
                            label: Text(
                              isResending ? 'Sending...' : 'Resend Code',
                              style: const TextStyle(color: kBlue, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (errorMsg != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        errorMsg!,
                        style: const TextStyle(color: Color(0xFFFF5252), fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (infoMsg != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        infoMsg!,
                        style: const TextStyle(color: Color(0xFF2ECC71), fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kCrimson),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (step == 1) {
                          final em = emailCtrl.text.trim();
                          if (!em.contains('@')) {
                            setDialogState(() => errorMsg = 'Please enter a valid email');
                            return;
                          }
                          setDialogState(() {
                            isSubmitting = true;
                            errorMsg = null;
                            infoMsg = null;
                          });
                          final ok = await state.forgotPassword(em);
                          setDialogState(() {
                            isSubmitting = false;
                            if (ok) {
                              step = 2;
                              infoMsg = 'Reset code sent to $em';
                            } else {
                              errorMsg = state.authError ?? 'Failed to send reset code';
                            }
                          });
                        } else {
                          final cd = codeCtrl.text.trim();
                          final np = newPassCtrl.text;
                          final cp = confirmPassCtrl.text;
                          if (cd.length < 4) {
                            setDialogState(() => errorMsg = 'Enter the 6-digit code');
                            return;
                          }
                          if (np.length < 8) {
                            setDialogState(() => errorMsg = 'Password must be at least 8 characters');
                            return;
                          }
                          if (np != cp) {
                            setDialogState(() => errorMsg = 'Passwords do not match');
                            return;
                          }
                          setDialogState(() {
                            isSubmitting = true;
                            errorMsg = null;
                          });
                          final ok = await state.resetPassword(
                            email: emailCtrl.text.trim(),
                            code: cd,
                            newPassword: np,
                          );
                          if (!ctx.mounted) return;
                          if (ok) {
                            Navigator.of(ctx).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                backgroundColor: Color(0xFF1E824C),
                                content: Text('🎉 Password reset successfully! You are now logged in.'),
                              ),
                            );
                          } else {
                            setDialogState(() {
                              isSubmitting = false;
                              errorMsg = state.authError ?? 'Invalid or expired reset code';
                            });
                          }
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(step == 1 ? 'Send Code' : 'Reset Password'),
              ),
            ],
          );
        },
      );
    },
  );
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
  bool _timeTravelOpen = false;
  double _timeTravelDays = 0.0;
  bool _isPlaying = false;
  Timer? _playTimer;
  bool _showMembranes = true;
  bool _radarActive = false;
  int _radarTargetIndex = 0;
  bool _slingshotActive = false;
  final TextEditingController _slingTitle = TextEditingController();
  String? _aimedSpaceName;
  UrgencyBand _aimedBand = UrgencyBand.now;
  double _slingTension = 0.0;

  @override
  void dispose() {
    _slingTitle.dispose();
    _playTimer?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _togglePlay() {
    setState(() {
      _isPlaying = !_isPlaying;
      if (_isPlaying) {
        _playTimer?.cancel();
        _playTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
          if (!mounted) return;
          setState(() {
            _timeTravelDays += 0.25;
            if (_timeTravelDays > 30.0) {
              _timeTravelDays = 0.0;
            }
          });
        });
      } else {
        _playTimer?.cancel();
        _playTimer = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final selected = _selected == null ? null : s.threadById(_selected!);
    final dark = Theme.of(context).brightness == Brightness.dark;

    final timeTravelOffset = Duration(minutes: (_timeTravelDays * 24 * 60).round());
    final simulatedNow = DateTime.now().add(timeTravelOffset);
    final simulatedLayout = WebLayout.compute(
      threads: s.threads,
      spaces: s.spaces,
      now: simulatedNow,
      showDone: s.settings.showDone,
      hiddenSpaceIds: Set.of(_hidden),
    );
    final bottleneckCount = s.threads.where((t) {
      if (t.isDone) return false;
      final node = simulatedLayout.nodes[t.id];
      return node != null && node.band == UrgencyBand.now;
    }).length;

    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: dark ? const [Color(0xFF111833), Color(0xFF03040A)] : const [Color(0xFFF4F7FF), Color(0xFFDDE5F5)],
          radius: 0.95,
        ),
      ),
      child: Stack(children: [
        Column(children: [
          SafeArea(
            bottom: false,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                child: Row(children: [
                  const Text('Your web', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  const SizedBox(width: 10),
                  _LinkPill(s),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Cinematic Voice-to-Web',
                    icon: const Icon(
                      Icons.mic_none_rounded,
                      color: Color(0xFFD946EF),
                    ),
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      showVoiceToWebModal(
                        context,
                        onThreadCreated: (threadId) {
                          _ctl.focusOn(threadId);
                        },
                      );
                    },
                  ),
                  IconButton(
                    tooltip: 'Slingshot Quick-Capture',
                    icon: Icon(
                      Icons.gps_fixed,
                      color: _slingshotActive ? const Color(0xFF00FF88) : null,
                    ),
                    onPressed: () {
                      setState(() {
                        _slingshotActive = !_slingshotActive;
                        if (_slingshotActive) {
                          _timeTravelOpen = false;
                          _radarActive = false;
                          HapticFeedback.mediumImpact();
                        }
                      });
                    },
                  ),
                  IconButton(
                    tooltip: 'Spider Radar Focus Mode',
                    icon: Icon(
                      Icons.radar,
                      color: _radarActive ? const Color(0xFF00F5FF) : null,
                    ),
                    onPressed: () {
                      setState(() {
                        _radarActive = !_radarActive;
                        if (_radarActive) {
                          _timeTravelOpen = false;
                          _slingshotActive = false;
                          final moves = s.nextMoves(limit: 5);
                          if (moves.isNotEmpty) {
                            _radarTargetIndex = 0;
                            _ctl.focusOn(moves[0].thread.id);
                            HapticFeedback.mediumImpact();
                          } else {
                            _radarActive = false;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('No active tasks to focus on! Add tasks to engage Spider Radar.')),
                            );
                          }
                        }
                      });
                    },
                  ),
                  IconButton(
                    tooltip: 'Constellation Membranes (Project Sails)',
                    icon: Icon(
                      _showMembranes ? Icons.auto_awesome : Icons.auto_awesome_outlined,
                      color: _showMembranes ? kBlue : null,
                    ),
                    onPressed: () => setState(() => _showMembranes = !_showMembranes),
                  ),
                  IconButton(
                    tooltip: 'Future Scrubber (Time Travel)',
                    icon: Icon(
                      _timeTravelDays > 0 ? Icons.hourglass_top_rounded : Icons.hourglass_bottom_rounded,
                      color: _timeTravelDays > 0 ? kCrimson : (_timeTravelOpen ? kBlue : null),
                    ),
                    onPressed: () => setState(() => _timeTravelOpen = !_timeTravelOpen),
                  ),
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
          Expanded(
            child: Builder(builder: (context) {
              final radarMoves = s.nextMoves(limit: 5);
              final radarTargetId = (_radarActive && radarMoves.isNotEmpty)
                  ? radarMoves[_radarTargetIndex.clamp(0, radarMoves.length - 1)].thread.id
                  : null;
              final focusIds = _radarActive ? radarMoves.map((m) => m.thread.id).toSet() : const <String>{};

              return WebView3D(
                threads: s.threads,
                spaces: s.spaces,
                controller: _ctl,
                selectedId: selected?.id,
                flashIds: s.flashIds,
                showDone: s.settings.showDone,
                showMembranes: _showMembranes,
                radarActive: _radarActive,
                radarTargetId: radarTargetId,
                focusThreadIds: focusIds,
                slingshotActive: _slingshotActive,
                slingshotSeedTitle: _slingTitle.text,
                onSlingshotAimChanged: (tension, spaceName, band) {
                  setState(() {
                    _slingTension = tension;
                    _aimedSpaceName = spaceName;
                    _aimedBand = band;
                  });
                },
                onSlingshotFired: (worldPos, spaceId, band) {
                  final title = _slingTitle.text.trim().isEmpty ? 'Quick Thread' : _slingTitle.text.trim();
                  DateTime? due;
                  switch (band) {
                    case UrgencyBand.now:
                      due = DateTime.now().add(const Duration(hours: 3));
                      break;
                    case UrgencyBand.tomorrow:
                      due = DateTime.now().add(const Duration(days: 1));
                      break;
                    case UrgencyBand.week:
                      due = DateTime.now().add(const Duration(days: 5));
                      break;
                    case UrgencyBand.month:
                      due = DateTime.now().add(const Duration(days: 20));
                      break;
                    default:
                      due = null;
                  }
                  final targetSpace = (spaceId != null ? s.spaceById(spaceId) : null) ?? (s.spaces.isNotEmpty ? s.spaces.first : null);
                  final thread = s.createThread(
                    title: title,
                    spaceId: targetSpace?.id,
                    dueAt: due,
                  );
                  s.flashThread(thread.id);
                  _ctl.focusOn(thread.id);
                  HapticFeedback.heavyImpact();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: const Color(0xFF060914),
                      content: Row(
                        children: [
                          const Icon(Icons.gps_fixed, color: Color(0xFF00FF88), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Injected "$title" into ${targetSpace?.name ?? "Web"} (${band.label})!',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                  setState(() {
                    _slingTitle.clear();
                    _slingTension = 0.0;
                  });
                },
                hiddenSpaceIds: Set.of(_hidden),
                highlightKeyword: _search && _kw.trim().isNotEmpty ? _kw.trim() : null,
                reduceMotion: s.settings.reduceMotion,
                lowGraphics: s.settings.lowGraphics,
                timeTravelOffset: timeTravelOffset,
                onSelect: (id) => setState(() => _selected = id),
              );
            }),
          ),
        ]),
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
        bottom: selected != null
            ? 200
            : ((_timeTravelOpen || _timeTravelDays > 0 || _radarActive || _slingshotActive) ? 190 : 90),
        child: Column(children: [
          IconButton.filledTonal(tooltip: 'Zoom in', icon: const Icon(Icons.add), onPressed: () => _ctl.zoomBy(1.4)),
          const SizedBox(height: 6),
          IconButton.filledTonal(tooltip: 'Zoom out', icon: const Icon(Icons.remove), onPressed: () => _ctl.zoomBy(1 / 1.4)),
        ]),
      ),
      if (_timeTravelOpen || _timeTravelDays > 0)
        Positioned(
          left: 14,
          right: 14,
          bottom: selected == null ? 84 : 194,
          child: _FutureScrubberDock(
            days: _timeTravelDays,
            isPlaying: _isPlaying,
            bottleneckCount: bottleneckCount,
            simulatedDate: simulatedNow,
            onChanged: (v) => setState(() => _timeTravelDays = v),
            onTogglePlay: _togglePlay,
            onReset: () => setState(() {
              _timeTravelDays = 0.0;
              _isPlaying = false;
              _playTimer?.cancel();
            }),
            onClose: () => setState(() {
              _timeTravelOpen = false;
              _timeTravelDays = 0.0;
              _isPlaying = false;
              _playTimer?.cancel();
            }),
          ),
        ),
      if (_radarActive)
        Positioned(
          left: 14,
          right: 14,
          bottom: selected == null ? 84 : 194,
          child: _SpiderRadarFocusDock(
            moves: s.nextMoves(limit: 5),
            currentIndex: _radarTargetIndex,
            onCycleNext: () {
              final moves = s.nextMoves(limit: 5);
              if (moves.isEmpty) return;
              setState(() {
                _radarTargetIndex = (_radarTargetIndex + 1) % moves.length;
                _ctl.focusOn(moves[_radarTargetIndex].thread.id);
                HapticFeedback.lightImpact();
              });
            },
            onStartDoing: (threadId) {
              s.setStatus(threadId, ThreadStatus.doing);
              HapticFeedback.mediumImpact();
            },
            onMarkDone: (threadId) {
              s.setStatus(threadId, ThreadStatus.done);
              HapticFeedback.mediumImpact();
              final moves = s.nextMoves(limit: 5);
              if (moves.isEmpty) {
                setState(() => _radarActive = false);
              } else {
                setState(() {
                  _radarTargetIndex = _radarTargetIndex.clamp(0, moves.length - 1);
                  _ctl.focusOn(moves[_radarTargetIndex].thread.id);
                });
              }
            },
            onClose: () => setState(() => _radarActive = false),
          ),
        ),
      if (_slingshotActive)
        Positioned(
          left: 14,
          right: 14,
          bottom: selected == null ? 84 : 194,
          child: _SlingshotDock(
            titleController: _slingTitle,
            tension: _slingTension,
            aimedSpaceName: _aimedSpaceName,
            aimedBand: _aimedBand,
            onLaunch: () {
              final title = _slingTitle.text.trim().isEmpty ? 'Quick Thread' : _slingTitle.text.trim();
              DateTime? due;
              switch (_aimedBand) {
                case UrgencyBand.now:
                  due = DateTime.now().add(const Duration(hours: 3));
                  break;
                case UrgencyBand.tomorrow:
                  due = DateTime.now().add(const Duration(days: 1));
                  break;
                case UrgencyBand.week:
                  due = DateTime.now().add(const Duration(days: 5));
                  break;
                case UrgencyBand.month:
                  due = DateTime.now().add(const Duration(days: 20));
                  break;
                default:
                  due = null;
              }
              final targetSpace = (_aimedSpaceName != null
                      ? s.spaces.cast<Space?>().firstWhere(
                            (sp) => sp?.name.toLowerCase() == _aimedSpaceName!.toLowerCase(),
                            orElse: () => null,
                          )
                      : null) ??
                  (s.spaces.isNotEmpty ? s.spaces.first : null);
              final thread = s.createThread(
                title: title,
                spaceId: targetSpace?.id,
                dueAt: due,
              );
              s.flashThread(thread.id);
              _ctl.focusOn(thread.id);
              HapticFeedback.heavyImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFF060914),
                  content: Row(
                    children: [
                      const Icon(Icons.gps_fixed, color: Color(0xFF00FF88), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Injected "$title" into ${targetSpace?.name ?? "Web"} (${_aimedBand.label})!',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  duration: const Duration(seconds: 3),
                ),
              );
              setState(() {
                _slingTitle.clear();
                _slingTension = 0.0;
              });
            },
            onClose: () => setState(() {
              _slingshotActive = false;
              _slingTension = 0.0;
            }),
          ),
        ),
      if (selected != null)
        Positioned(left: 12, right: 12, bottom: 84, child: _SelectedCard(thread: selected, onFocus: () => _ctl.focusOn(selected.id), onClose: () => setState(() => _selected = null))),
      ]),
    );
  }
}

class _FutureScrubberDock extends StatelessWidget {
  const _FutureScrubberDock({
    required this.days,
    required this.isPlaying,
    required this.bottleneckCount,
    required this.simulatedDate,
    required this.onChanged,
    required this.onTogglePlay,
    required this.onReset,
    required this.onClose,
  });

  final double days;
  final bool isPlaying;
  final int bottleneckCount;
  final DateTime simulatedDate;
  final ValueChanged<double> onChanged;
  final VoidCallback onTogglePlay;
  final VoidCallback onReset;
  final VoidCallback onClose;

  String _formatDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final w = weekdays[dt.weekday - 1];
    final m = months[dt.month - 1];
    return '$w, $m ${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    final isCrunch = bottleneckCount >= 3;
    final isNow = days <= 0.05;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF0080C1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCrunch ? kCrimson.withValues(alpha: 0.8) : const Color(0x5532B4FF),
          width: isCrunch ? 1.8 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isCrunch ? kCrimson.withValues(alpha: 0.35) : Colors.black.withValues(alpha: 0.6),
            blurRadius: isCrunch ? 28 : 20,
            spreadRadius: isCrunch ? 2 : 0,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isCrunch ? kCrimson.withValues(alpha: 0.2) : kBlue.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isCrunch ? Icons.warning_amber_rounded : Icons.hourglass_top_rounded,
                  color: isCrunch ? kCrimson : kBlue,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isNow
                          ? 'TIME TRAVEL: REAL TIME'
                          : 'SIMULATING: +${days.toStringAsFixed(1)}d (${_formatDate(simulatedDate)})',
                      style: TextStyle(
                        color: isNow ? Colors.white.withValues(alpha: 0.7) : (isCrunch ? kCrimson : kBlue),
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isCrunch
                          ? '🚨 CRUNCH: $bottleneckCount threads converging on NOW'
                          : (isNow
                              ? '$bottleneckCount thread(s) currently at NOW ring'
                              : '$bottleneckCount thread(s) in NOW ring on this date'),
                      style: TextStyle(
                        color: isCrunch ? const Color(0xFFFF8595) : Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                        fontWeight: isCrunch ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isNow)
                TextButton(
                  onPressed: onReset,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Reset', style: TextStyle(color: kBlue, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                color: Colors.white.withValues(alpha: 0.6),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              IconButton(
                tooltip: isPlaying ? 'Pause Simulation' : 'Play Time-Travel',
                icon: Icon(
                  isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                  color: isPlaying ? kCrimson : kBlue,
                  size: 30,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onTogglePlay,
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: isCrunch ? kCrimson : kBlue,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                    thumbColor: isCrunch ? kCrimson : Colors.white,
                    overlayColor: (isCrunch ? kCrimson : kBlue).withValues(alpha: 0.2),
                    trackHeight: 3.5,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    value: days.clamp(0.0, 30.0),
                    min: 0.0,
                    max: 30.0,
                    onChanged: onChanged,
                  ),
                ),
              ),
            ],
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _PresetChip(label: 'NOW', selected: isNow, onTap: () => onChanged(0.0)),
                _PresetChip(label: '+1d', selected: (days - 1.0).abs() < 0.3, onTap: () => onChanged(1.0)),
                _PresetChip(label: '+3d', selected: (days - 3.0).abs() < 0.3, onTap: () => onChanged(3.0)),
                _PresetChip(label: '+1w', selected: (days - 7.0).abs() < 0.5, onTap: () => onChanged(7.0)),
                _PresetChip(label: '+2w', selected: (days - 14.0).abs() < 0.5, onTap: () => onChanged(14.0)),
                _PresetChip(label: '+1m', selected: (days - 30.0).abs() < 0.5, onTap: () => onChanged(30.0)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? kBlue.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? kBlue : Colors.white.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white.withValues(alpha: 0.7),
              fontSize: 11,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _SpiderRadarFocusDock extends StatelessWidget {
  const _SpiderRadarFocusDock({
    required this.moves,
    required this.currentIndex,
    required this.onCycleNext,
    required this.onStartDoing,
    required this.onMarkDone,
    required this.onClose,
  });

  final List<NextMove> moves;
  final int currentIndex;
  final VoidCallback onCycleNext;
  final void Function(String id) onStartDoing;
  final void Function(String id) onMarkDone;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    if (moves.isEmpty) return const SizedBox.shrink();
    final current = moves[currentIndex.clamp(0, moves.length - 1)];
    final t = current.thread;
    final isDoing = t.status == ThreadStatus.doing;
    final s = context.watch<AppState>();
    final space = s.spaceById(t.spaceId);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: BoxDecoration(
            color: const Color(0xFF090E1E).withValues(alpha: 0.90),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF00F5FF).withValues(alpha: 0.45), width: 1.4),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00F5FF).withValues(alpha: 0.18),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.radar, color: Color(0xFF00F5FF), size: 16),
                  const SizedBox(width: 8),
                  const Text(
                    'SPIDER RADAR • FOCUS LOCK',
                    style: TextStyle(
                      color: Color(0xFF00F5FF),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Target ${currentIndex + 1} of ${moves.length}',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white70),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: onClose,
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.close, size: 18, color: Colors.white70),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: space?.color ?? const Color(0xFF32B4FF),
                    radius: 7,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: current.score >= 100
                          ? kCrimson.withValues(alpha: 0.22)
                          : const Color(0xFF00F5FF).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: current.score >= 100 ? kCrimson : const Color(0xFF00F5FF),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      current.reason.isEmpty
                          ? (current.score >= 100 ? 'Overdue' : 'Next Move')
                          : current.reason,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: current.score >= 100 ? kCrimson : const Color(0xFF00F5FF),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (!isDoing)
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF00F5FF),
                          side: const BorderSide(color: Color(0xFF00F5FF)),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 16),
                        label: const Text('Start Doing', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () => onStartDoing(t.id),
                      ),
                    ),
                  if (!isDoing) const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF50FA7B),
                        foregroundColor: const Color(0xFF03040A),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Mark Done', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () => onMarkDone(t.id),
                    ),
                  ),
                  if (moves.length > 1) const SizedBox(width: 8),
                  if (moves.length > 1)
                    IconButton.filledTonal(
                      tooltip: 'Next Target in Radar',
                      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                      onPressed: onCycleNext,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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

class _SlingshotDock extends StatelessWidget {
  const _SlingshotDock({
    required this.titleController,
    required this.tension,
    required this.aimedSpaceName,
    required this.aimedBand,
    required this.onLaunch,
    required this.onClose,
  });

  final TextEditingController titleController;
  final double tension;
  final String? aimedSpaceName;
  final UrgencyBand aimedBand;
  final VoidCallback onLaunch;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    const neonEmerald = Color(0xFF00FF88);
    final tensionPct = (tension * 100).toInt();

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF070B18).withValues(alpha: 0.90),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: neonEmerald.withValues(alpha: 0.65), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: neonEmerald.withValues(alpha: 0.18),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: neonEmerald,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: neonEmerald, blurRadius: 8, spreadRadius: 2),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'SLINGSHOT QUICK-CAPTURE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      color: neonEmerald,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Colors.white70),
                    onPressed: onClose,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Exit Slingshot',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: titleController,
                      style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: 'Thread title to inject...',
                        hintStyle: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.4)),
                        prefixIcon: const Icon(Icons.gps_fixed, size: 18, color: neonEmerald),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.08),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: neonEmerald.withValues(alpha: 0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: neonEmerald, width: 1.4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: neonEmerald,
                      foregroundColor: const Color(0xFF03040A),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.rocket_launch_rounded, size: 16),
                    label: const Text('Fire', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    onPressed: onLaunch,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      tension > 0.1 ? Icons.track_changes : Icons.touch_app_outlined,
                      size: 15,
                      color: neonEmerald,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tension > 0.05
                            ? 'Tension $tensionPct%  •  Target: [${aimedSpaceName ?? 'Web'}] (${aimedBand.label})'
                            : 'Pull back on canvas to aim trajectory  →  Release to shoot seed!',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: tension > 0.05 ? neonEmerald : Colors.white70,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

