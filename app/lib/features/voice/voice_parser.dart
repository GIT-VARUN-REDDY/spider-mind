import '../../models/space.dart';
import '../../models/thread.dart';

/// Semantic parsing result from natural language voice input.
class ParsedVoiceCommand {
  const ParsedVoiceCommand({
    required this.rawTranscript,
    required this.title,
    this.spaceId,
    this.spaceName,
    this.dueAt,
    this.dueLabel,
    this.priority = Priority.medium,
    this.type = ThreadType.task,
    this.linkedThreadIds = const [],
    this.linkedThreadTitles = const [],
  });

  final String rawTranscript;
  final String title;
  final String? spaceId;
  final String? spaceName;
  final DateTime? dueAt;
  final String? dueLabel;
  final Priority priority;
  final ThreadType type;
  final List<String> linkedThreadIds;
  final List<String> linkedThreadTitles;

  bool get hasEntities =>
      spaceName != null || dueLabel != null || priority != Priority.medium || linkedThreadTitles.isNotEmpty;
}

/// Natural language entity extractor for voice-to-web dictation.
class VoiceParser {
  VoiceParser._();

  /// Parses natural language [text] against existing [spaces] and [threads].
  static ParsedVoiceCommand parse({
    required String text,
    required List<Space> spaces,
    required List<Thread> threads,
    DateTime? referenceNow,
  }) {
    final now = referenceNow ?? DateTime.now();
    final lower = text.toLowerCase().trim();
    if (lower.isEmpty) {
      return ParsedVoiceCommand(
        rawTranscript: text,
        title: 'New Voice Thread',
      );
    }

    var remaining = text.trim();

    // 1. Detect Priority
    var priority = Priority.medium;
    final urgentRegex = RegExp(r'\b(urgent|urgently|asap|critical|highest priority|emergency)\b', caseSensitive: false);
    final highRegex = RegExp(r'\b(high priority|important)\b', caseSensitive: false);
    final lowRegex = RegExp(r'\b(low priority|someday|optional)\b', caseSensitive: false);

    if (urgentRegex.hasMatch(remaining)) {
      priority = Priority.high;
      remaining = remaining.replaceAll(urgentRegex, '');
    } else if (highRegex.hasMatch(remaining)) {
      priority = Priority.high;
      remaining = remaining.replaceAll(highRegex, '');
    } else if (lowRegex.hasMatch(remaining)) {
      priority = Priority.low;
      remaining = remaining.replaceAll(lowRegex, '');
    }

    // 2. Detect Thread Type
    var type = ThreadType.task;
    final ideaRegex = RegExp(r'\b(idea|concept|thought)\b', caseSensitive: false);
    final questionRegex = RegExp(r'\b(question|research|find out|investigate)\b', caseSensitive: false);
    final goalRegex = RegExp(r'\b(goal|objective|milestone|major outcome)\b', caseSensitive: false);

    if (ideaRegex.hasMatch(remaining)) {
      type = ThreadType.idea;
      remaining = remaining.replaceAll(ideaRegex, '');
    } else if (questionRegex.hasMatch(remaining)) {
      type = ThreadType.question;
      remaining = remaining.replaceAll(questionRegex, '');
    } else if (goalRegex.hasMatch(remaining)) {
      type = ThreadType.goal;
      remaining = remaining.replaceAll(goalRegex, '');
    }

    // 3. Detect Space
    String? matchedSpaceId;
    String? matchedSpaceName;
    for (final s in spaces) {
      final namePattern = RegExp('\\b(in|for|into|under|space)?\\s*${RegExp.escape(s.name)}\\b', caseSensitive: false);
      if (namePattern.hasMatch(remaining)) {
        matchedSpaceId = s.id;
        matchedSpaceName = s.name;
        remaining = remaining.replaceAll(namePattern, '');
        break;
      }
    }

    // 4. Detect Due Date
    DateTime? dueAt;
    String? dueLabel;
    final todayRegex = RegExp(r'\b(due\s+)?(today|tonight|this evening)\b', caseSensitive: false);
    final tomorrowRegex = RegExp(r'\b(due\s+)?(tomorrow|tmrw)\b', caseSensitive: false);
    final thisWeekRegex = RegExp(r'\b(due\s+)?(this week|end of week|by friday)\b', caseSensitive: false);
    final nextWeekRegex = RegExp(r'\b(due\s+)?(next week|in a week|in 7 days)\b', caseSensitive: false);
    final nextMonthRegex = RegExp(r'\b(due\s+)?(this month|next month|in a month)\b', caseSensitive: false);
    final inDaysRegex = RegExp(r'\bin\s+(\d+)\s+days?\b', caseSensitive: false);

    if (todayRegex.hasMatch(remaining)) {
      dueAt = DateTime(now.year, now.month, now.day, 20, 0);
      dueLabel = 'Today';
      remaining = remaining.replaceAll(todayRegex, '');
    } else if (tomorrowRegex.hasMatch(remaining)) {
      final d = now.add(const Duration(days: 1));
      dueAt = DateTime(d.year, d.month, d.day, 18, 0);
      dueLabel = 'Tomorrow';
      remaining = remaining.replaceAll(tomorrowRegex, '');
    } else if (thisWeekRegex.hasMatch(remaining)) {
      final d = now.add(const Duration(days: 4));
      dueAt = DateTime(d.year, d.month, d.day, 18, 0);
      dueLabel = 'This Week';
      remaining = remaining.replaceAll(thisWeekRegex, '');
    } else if (nextWeekRegex.hasMatch(remaining)) {
      final d = now.add(const Duration(days: 7));
      dueAt = DateTime(d.year, d.month, d.day, 18, 0);
      dueLabel = 'Next Week';
      remaining = remaining.replaceAll(nextWeekRegex, '');
    } else if (nextMonthRegex.hasMatch(remaining)) {
      final d = now.add(const Duration(days: 30));
      dueAt = DateTime(d.year, d.month, d.day, 18, 0);
      dueLabel = 'Next Month';
      remaining = remaining.replaceAll(nextMonthRegex, '');
    } else {
      final m = inDaysRegex.firstMatch(remaining);
      if (m != null) {
        final days = int.tryParse(m.group(1) ?? '1') ?? 1;
        final d = now.add(Duration(days: days));
        dueAt = DateTime(d.year, d.month, d.day, 18, 0);
        dueLabel = 'In $days days';
        remaining = remaining.replaceAll(inDaysRegex, '');
      }
    }

    // 5. Detect Links to existing threads
    final linkedIds = <String>[];
    final linkedTitles = <String>[];
    final linkRegex = RegExp(r'\b(linked to|connect to|connected to|related to|links to)\s+([a-zA-Z0-9\s]+)', caseSensitive: false);
    final linkMatch = linkRegex.firstMatch(remaining);
    if (linkMatch != null) {
      final query = linkMatch.group(2)?.trim().toLowerCase() ?? '';
      for (final t in threads) {
        if (query.contains(t.title.toLowerCase()) || t.title.toLowerCase().contains(query)) {
          linkedIds.add(t.id);
          linkedTitles.add(t.title);
          break;
        }
      }
      remaining = remaining.replaceAll(linkRegex, '');
    }

    // Clean extraneous filler phrases like "SpiderMind", "create a task", "add a", etc.
    final filler = RegExp(
      r'^(spidermind|spider mind|hey spidermind|please|create a task to|create a task|create an idea|create a goal|create a|add a task to|add a task|add|new task)\s*',
      caseSensitive: false,
    );
    remaining = remaining.replaceAll(filler, '');

    // Normalize multiple spaces and punctuation
    remaining = remaining.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (remaining.startsWith('to ')) {
      remaining = remaining.substring(3).trim();
    }
    if (remaining.endsWith('.')) {
      remaining = remaining.substring(0, remaining.length - 1).trim();
    }

    final finalTitle = remaining.isEmpty ? 'New Voice Thread' : remaining[0].toUpperCase() + remaining.substring(1);

    return ParsedVoiceCommand(
      rawTranscript: text,
      title: finalTitle,
      spaceId: matchedSpaceId,
      spaceName: matchedSpaceName,
      dueAt: dueAt,
      dueLabel: dueLabel,
      priority: priority,
      type: type,
      linkedThreadIds: linkedIds,
      linkedThreadTitles: linkedTitles,
    );
  }
}
