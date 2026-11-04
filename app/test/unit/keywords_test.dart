import 'package:flutter_test/flutter_test.dart';
import 'package:spider_mind/logic/keywords.dart';

void main() {
  group('deriveKeywords pure Dart', () {
    test('lowercases, splits on non-alphanumerics, drops short words', () {
      expect(
        deriveKeywords(title: 'Buy MILK, eggs & bread!'),
        ['milk', 'egg', 'bread'],
      );
    });

    test('drops stop words', () {
      expect(deriveKeywords(title: 'What should this be about'), <String>[]);
    });

    test('strips ing/ed only when length > 5', () {
      expect(deriveKeywords(title: 'planning'), ['plann']);
      expect(deriveKeywords(title: 'finished'), ['finish']);
      expect(deriveKeywords(title: 'bring'), ['bring']); // length 5
      expect(deriveKeywords(title: 'speed'), ['speed']); // length 5
    });

    test('strips a single trailing s except ss, when length > 3', () {
      expect(deriveKeywords(title: 'tasks class boss'), ['task', 'class', 'boss']);
      expect(deriveKeywords(title: 'bus'), <String>[]);
      expect(deriveKeywords(title: 'meetings'), ['meeting']);
    });

    test('de-duplicates across title, notes and tags, in first-seen order', () {
      expect(
        deriveKeywords(
          title: 'Budget review',
          notes: 'review the budgets',
          tags: ['Finance', 'budget'],
        ),
        ['budget', 'review', 'finance'],
      );
    });

    test('caps at 20 keywords', () {
      final words = List.generate(40, (i) => 'word${String.fromCharCode(97 + (i % 26))}${i}x');
      expect(deriveKeywords(title: words.join(' ')).length, 20);
    });

    test('handles empty input and non-ASCII separators', () {
      expect(deriveKeywords(title: '', notes: '', tags: []), <String>[]);
      expect(deriveKeywords(title: 'naïve plan'), ['plan']);
    });
  });
}
