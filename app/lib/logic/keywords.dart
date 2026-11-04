// Pure Dart keyword extraction mirroring server/src/services/keywords.js (CONTRACT.md section 1).
const int maxKeywords = 20;

final Set<String> stopWords = Set<String>.unmodifiable({
  'about', 'above', 'after', 'again', 'also', 'been', 'before', 'being', 'below',
  'between', 'both', 'come', 'could', 'does', 'doing', 'down', 'during', 'each',
  'from', 'further', 'gets', 'getting', 'have', 'having', 'here', 'hers',
  'herself', 'himself', 'into', 'itself', 'just', 'like', 'make', 'many',
  'more', 'most', 'much', 'must', 'myself', 'need', 'only', 'other', 'ours',
  'ourselves', 'over', 'same', 'should', 'some', 'such', 'take', 'than',
  'that', 'their', 'theirs', 'them', 'themselves', 'then', 'there', 'these',
  'they', 'this', 'those', 'through', 'under', 'until', 'upon', 'very',
  'want', 'was', 'were', 'what', 'when', 'where', 'which', 'while', 'whom',
  'will', 'with', 'would', 'your', 'yours', 'yourself', 'yourselves',
});

String _stem(String w) {
  var s = w;
  if (s.length > 5 && (s.endsWith('ing') || s.endsWith('ed'))) {
    s = s.substring(0, s.endsWith('ing') ? s.length - 3 : s.length - 2);
  }
  if (s.length > 3 && s.endsWith('s') && !s.endsWith('ss')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// Derives keywords from title + notes + tags: first-appearance order, max 20.
List<String> deriveKeywords({
  String title = '',
  String notes = '',
  Iterable<String> tags = const [],
}) {
  final allParts = <String>[
    title,
    notes,
    ...tags,
  ];
  final text = allParts.join(' ').toLowerCase();
  final out = <String>[];
  final seen = <String>{};

  final tokens = text.split(RegExp(r'[^a-z0-9]+'));
  for (final raw in tokens) {
    if (raw.length < 4 || stopWords.contains(raw)) continue;
    final w = _stem(raw);
    if (seen.contains(w)) continue;
    seen.add(w);
    out.add(w);
    if (out.length == maxKeywords) break;
  }
  return out;
}
