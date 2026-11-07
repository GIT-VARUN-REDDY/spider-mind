import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/thread.dart';
import '../../state/app_state.dart';
import 'voice_parser.dart';

/// Opens the Cinematic Voice-to-Web HUD Modal.
Future<void> showVoiceToWebModal(BuildContext context, {void Function(String threadId)? onThreadCreated}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _VoiceToWebHUD(onThreadCreated: onThreadCreated),
  );
}

class _VoiceToWebHUD extends StatefulWidget {
  const _VoiceToWebHUD({this.onThreadCreated});

  final void Function(String threadId)? onThreadCreated;

  @override
  State<_VoiceToWebHUD> createState() => _VoiceToWebHUDState();
}

class _VoiceToWebHUDState extends State<_VoiceToWebHUD> with SingleTickerProviderStateMixin {
  late final TextEditingController _transcriptController;
  late final AnimationController _waveAnim;
  bool _isListening = true;
  ParsedVoiceCommand? _parsed;

  static const List<String> _presets = [
    'Fix server crash in Engineering linked to Backend API urgent',
    'Buy groceries tomorrow for Personal',
    'Design brand identity due next Friday high priority',
    'Brainstorm marketing campaign idea in Work',
  ];

  @override
  void initState() {
    super.initState();
    _transcriptController = TextEditingController(text: _presets.first);
    _waveAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();

    _transcriptController.addListener(_onTranscriptChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reparse();
    });
  }

  @override
  void dispose() {
    _waveAnim.dispose();
    _transcriptController.dispose();
    super.dispose();
  }

  void _onTranscriptChanged() {
    _reparse();
  }

  void _reparse() {
    final s = context.read<AppState>();
    setState(() {
      _parsed = VoiceParser.parse(
        text: _transcriptController.text,
        spaces: s.spaces,
        threads: s.threads,
      );
    });
  }

  void _injectIntoWeb() {
    final parsed = _parsed;
    if (parsed == null || parsed.title.trim().isEmpty) return;

    final s = context.read<AppState>();
    HapticFeedback.heavyImpact();

    // 1. Create thread
    final created = s.createThread(
      title: parsed.title,
      type: parsed.type,
      priority: parsed.priority,
      spaceId: parsed.spaceId,
      dueAt: parsed.dueAt,
    );

    // 2. Weave links to connected threads
    if (parsed.linkedThreadIds.isNotEmpty) {
      final updated = created.copyWith(links: parsed.linkedThreadIds);
      s.saveThread(updated);
      for (final linkId in parsed.linkedThreadIds) {
        final other = s.threadById(linkId);
        if (other != null && !other.links.contains(created.id)) {
          s.saveThread(other.copyWith(links: [...other.links, created.id]));
        }
      }
    }

    // 3. Flash on web
    s.flashThread(created.id);
    widget.onThreadCreated?.call(created.id);

    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF090D1C),
        content: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Color(0xFFD946EF), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '🎙️ Wove "${created.title}" into Web${parsed.linkedThreadTitles.isNotEmpty ? ' with ${parsed.linkedThreadTitles.length} silk links' : ''}!',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const neonMagenta = Color(0xFFD946EF);
    const neonCyan = Color(0xFF00F5FF);
    final parsed = _parsed;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF050814).withValues(alpha: 0.94),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: neonMagenta.withValues(alpha: 0.4), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: neonMagenta.withValues(alpha: 0.25),
                blurRadius: 30,
                spreadRadius: 2,
              ),
            ],
          ),
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white30,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Title Header
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: neonMagenta,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: neonMagenta, blurRadius: 10, spreadRadius: 3),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'CINEMATIC VOICE-TO-WEB',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                      color: neonMagenta,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Acoustic Spider Web Visualizer
              SizedBox(
                height: 100,
                child: AnimatedBuilder(
                  animation: _waveAnim,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _SpiderAcousticWaveformPainter(
                        progress: _waveAnim.value,
                        isListening: _isListening,
                      ),
                      size: Size.infinite,
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),

              // Spoken Transcript Editable Input
              TextField(
                controller: _transcriptController,
                maxLines: 2,
                style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  prefixIcon: IconButton(
                    icon: Icon(
                      _isListening ? Icons.mic : Icons.mic_off,
                      color: _isListening ? neonMagenta : Colors.grey,
                    ),
                    onPressed: () {
                      setState(() {
                        _isListening = !_isListening;
                        HapticFeedback.selectionClick();
                      });
                    },
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear, size: 18, color: Colors.white54),
                    onPressed: () => _transcriptController.clear(),
                  ),
                  hintText: 'Speak or edit voice prompt...',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: neonMagenta.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: neonMagenta, width: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Presets scroll row
              SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _presets.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final p = _presets[index];
                    return ActionChip(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      side: BorderSide(color: neonMagenta.withValues(alpha: 0.35)),
                      label: Text(
                        p,
                        style: const TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                      onPressed: () {
                        _transcriptController.text = p;
                        HapticFeedback.lightImpact();
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Real-time Semantic Entity Extraction HUD Chips
              if (parsed != null) ...[
                const Text(
                  'EXTRACTED SEMANTICS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Colors.white54,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // Title chip
                    Chip(
                      avatar: const Icon(Icons.title, size: 14, color: Colors.white),
                      label: Text(parsed.title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                      side: const BorderSide(color: Colors.white30),
                    ),
                    // Space chip
                    if (parsed.spaceName != null)
                      Chip(
                        avatar: const Icon(Icons.folder_outlined, size: 14, color: neonCyan),
                        label: Text('Space: ${parsed.spaceName}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: neonCyan)),
                        backgroundColor: neonCyan.withValues(alpha: 0.12),
                        side: const BorderSide(color: neonCyan),
                      ),
                    // Due Date chip
                    if (parsed.dueLabel != null)
                      Chip(
                        avatar: const Icon(Icons.event_outlined, size: 14, color: Color(0xFFFFB86C)),
                        label: Text('Due: ${parsed.dueLabel}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFFFB86C))),
                        backgroundColor: const Color(0xFFFFB86C).withValues(alpha: 0.12),
                        side: const BorderSide(color: Color(0xFFFFB86C)),
                      ),
                    // Priority chip
                    if (parsed.priority != Priority.medium)
                      Chip(
                        avatar: const Icon(Icons.bolt, size: 14, color: Color(0xFFFF5555)),
                        label: Text('Priority: ${parsed.priority.name.toUpperCase()}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFFF5555))),
                        backgroundColor: const Color(0xFFFF5555).withValues(alpha: 0.12),
                        side: const BorderSide(color: Color(0xFFFF5555)),
                      ),
                    // Linked Thread chip
                    for (final linkedTitle in parsed.linkedThreadTitles)
                      Chip(
                        avatar: const Icon(Icons.link, size: 14, color: Color(0xFF50FA7B)),
                        label: Text('Link: $linkedTitle', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF50FA7B))),
                        backgroundColor: const Color(0xFF50FA7B).withValues(alpha: 0.12),
                        side: const BorderSide(color: Color(0xFF50FA7B)),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
              ],

              // Commit button
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: neonMagenta,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 6,
                  shadowColor: neonMagenta.withValues(alpha: 0.5),
                ),
                icon: const Icon(Icons.auto_awesome, size: 20),
                label: const Text(
                  'Weave Into Web',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.8),
                ),
                onPressed: _injectIntoWeb,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints undulating harmonic spider web acoustic ripples.
class _SpiderAcousticWaveformPainter extends CustomPainter {
  _SpiderAcousticWaveformPainter({required this.progress, required this.isListening});

  final double progress;
  final bool isListening;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const neonMagenta = Color(0xFFD946EF);
    const neonCyan = Color(0xFF00F5FF);

    // Center microphone glowing core
    final pulse = isListening ? (1.0 + 0.15 * math.sin(progress * 2 * math.pi * 3)) : 1.0;
    canvas.drawCircle(
      center,
      18.0 * pulse,
      Paint()
        ..color = neonMagenta.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawCircle(
      center,
      12.0,
      Paint()..color = neonMagenta,
    );
    canvas.drawCircle(
      center,
      5.0,
      Paint()..color = Colors.white,
    );

    if (!isListening) return;

    // Harmonic Concentric Acoustic Web Waves
    const rings = 4;
    for (var i = 1; i <= rings; i++) {
      final ringPhase = (progress + i / rings) % 1.0;
      final radius = 18.0 + ringPhase * (size.width * 0.42);
      final alpha = (1.0 - ringPhase).clamp(0.0, 1.0);

      final path = Path();
      const points = 24;
      for (var j = 0; j < points; j++) {
        final angle = (j / points) * 2 * math.pi;
        final waveOffset = math.sin(angle * 6 + progress * 2 * math.pi * 2) * (4.0 * ringPhase + 2.0);
        final r = radius + waveOffset;
        final pt = Offset(center.dx + r * math.cos(angle), center.dy + r * math.sin(angle) * 0.45);
        if (j == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      path.close();

      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = Color.lerp(neonMagenta, neonCyan, ringPhase)!.withValues(alpha: alpha * 0.75),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpiderAcousticWaveformPainter oldDelegate) => true;
}
