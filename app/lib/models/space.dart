import 'dart:ui' show Color;

import 'thread.dart' show newObjectId;

/// Distinct, accessible space colours (used as spoke colours in the web).
const List<String> kSpacePalette = [
  '#FF2A44', // crimson
  '#32B4FF', // electric blue
  '#FFC247', // amber
  '#3DDC97', // mint
  '#B07CFF', // violet
  '#FF7A3D', // orange
  '#4FE3E8', // cyan
  '#FF6FB5', // pink
];

/// A Space is one spoke of the web: a life area such as Work or Study.
class Space {
  const Space({
    required this.id,
    required this.name,
    required this.colorHex,
    this.order = 0,
  });

  final String id;
  final String name;

  /// '#RRGGBB'
  final String colorHex;
  final int order;

  Color get color {
    final h = colorHex.replaceFirst('#', '');
    final v = int.tryParse(h, radix: 16) ?? 0x32B4FF;
    return Color(0xFF000000 | v);
  }

  factory Space.create(String name, String colorHex, int order) =>
      Space(id: newObjectId(), name: name, colorHex: colorHex, order: order);

  factory Space.fromJson(Map<String, dynamic> j) => Space(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        colorHex: (j['color'] as String?) ?? '#32B4FF',
        order: (j['order'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'color': colorHex, 'order': order};

  Space copyWith({String? name, String? colorHex, int? order}) => Space(
        id: id,
        name: name ?? this.name,
        colorHex: colorHex ?? this.colorHex,
        order: order ?? this.order,
      );
}
