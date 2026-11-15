import 'package:flutter/material.dart';

/// One "#" shortcut key.
class ShortcutKey {
  final String key;
  final String description;
  final String example;
  final IconData icon;
  final bool takesCount; // e.g. #loop3{...}

  const ShortcutKey({
    required this.key,
    required this.description,
    required this.example,
    required this.icon,
    this.takesCount = false,
  });

  /// Text inserted when the user picks the suggestion.
  /// The cursor is placed between the braces.
  String get template => takesCount ? '#${key}3{}' : '#$key{}';
}

class MessageShortcuts {
  static const List<ShortcutKey> keys = [
    ShortcutKey(
        key: 'bold',
        description: 'Bold text',
        example: '#bold{Hello}',
        icon: Icons.format_bold_rounded),
    ShortcutKey(
        key: 'italic',
        description: 'Italic text',
        example: '#italic{Hello}',
        icon: Icons.format_italic_rounded),
    ShortcutKey(
        key: 'strike',
        description: 'Strikethrough text',
        example: '#strike{Hello}',
        icon: Icons.format_strikethrough_rounded),
    ShortcutKey(
        key: 'code',
        description: 'Monospace / code text',
        example: '#code{x = 1}',
        icon: Icons.code_rounded),
    ShortcutKey(
        key: 'upper',
        description: 'UPPERCASE text',
        example: '#upper{hello}',
        icon: Icons.text_increase_rounded),
    ShortcutKey(
        key: 'lower',
        description: 'lowercase text',
        example: '#lower{HELLO}',
        icon: Icons.text_decrease_rounded),
    ShortcutKey(
        key: 'loop',
        description: 'Repeat text N times (default 2, max 50)',
        example: '#loop3{ha}  →  ha ha ha',
        icon: Icons.repeat_rounded,
        takesCount: true),
  ];

  static ShortcutKey? find(String name) {
    final n = name.toLowerCase();
    for (final k in keys) {
      if (k.key == n) return k;
    }
    return null;
  }

  /// True when `#<name><digits>` is a valid key (digits only allowed for loop).
  static bool isKey(String name, [String digits = '']) {
    final k = find(name);
    if (k == null) return false;
    return digits.isEmpty || k.takesCount;
  }

  static List<ShortcutKey> search(String query) {
    final q = query.toLowerCase();
    return keys.where((k) => k.key.startsWith(q)).toList();
  }

  // ───────────── Converting on send ─────────────

  static final RegExp _shortcut = RegExp(r'#([A-Za-z]+)(\d*)\{([^{}]*)\}');

  /// Converts `#key{content}` into the final message text.
  /// Innermost shortcuts are resolved first, so nesting works.
  /// Unknown keys are left untouched.
  static String apply(String input) {
    var text = input;
    for (var i = 0; i < 10; i++) {
      var changed = false;
      text = text.replaceAllMapped(_shortcut, (m) {
        final k = find(m[1]!);
        if (k == null || !isKey(m[1]!, m[2]!)) return m[0]!;
        changed = true;
        return _transform(k, m[2]!, m[3]!);
      });
      if (!changed) break;
    }
    return text;
  }

  static String _transform(ShortcutKey k, String count, String c) {
    if (c.isEmpty) return '';
    switch (k.key) {
      case 'bold':
        return '**$c**';
      case 'italic':
        return '*$c*';
      case 'strike':
        return '~~$c~~';
      case 'code':
        return '`$c`';
      case 'upper':
        return c.toUpperCase();
      case 'lower':
        return c.toLowerCase();
      case 'loop':
        final n = (int.tryParse(count) ?? 2).clamp(1, 50);
        return List.filled(n, c.trim()).join(' ');
      default:
        return c;
    }
  }
}

/// TextEditingController that highlights valid "#keys" while typing.
class ShortcutTextController extends TextEditingController {
  ShortcutTextController({super.text, this.keyColor = Colors.pinkAccent});

  Color keyColor;

  static final RegExp _token = RegExp(r'#([A-Za-z]+)(\d*)');

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final src = text;
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _token.allMatches(src)) {
      if (!MessageShortcuts.isKey(m[1]!, m[2]!)) continue;
      if (m.start > last) {
        spans.add(TextSpan(text: src.substring(last, m.start)));
      }
      spans.add(TextSpan(
        text: m[0],
        style: TextStyle(
          color: keyColor,
          fontWeight: FontWeight.w700,
          backgroundColor: keyColor.withAlpha(30),
        ),
      ));
      last = m.end;
    }
    if (last < src.length) spans.add(TextSpan(text: src.substring(last)));
    return TextSpan(style: style, children: spans);
  }
}

/// Renders a message string that may contain **bold**, *italic*,
/// ~~strikethrough~~ or `code` markdown into a rich Text widget.
class FormattedMessageText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const FormattedMessageText(this.text, {super.key, this.style});

  static final RegExp _md = RegExp(
    r'\*\*(.+?)\*\*|\*(.+?)\*|~~(.+?)~~|`(.+?)`',
    dotAll: true,
  );

  static List<InlineSpan> parse(String s, TextStyle base) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _md.allMatches(s)) {
      if (m.start > last) {
        spans.add(TextSpan(text: s.substring(last, m.start), style: base));
      }
      if (m[1] != null) {
        spans.addAll(parse(m[1]!, base.copyWith(fontWeight: FontWeight.w700)));
      } else if (m[2] != null) {
        spans.addAll(parse(m[2]!, base.copyWith(fontStyle: FontStyle.italic)));
      } else if (m[3] != null) {
        spans.addAll(parse(
            m[3]!, base.copyWith(decoration: TextDecoration.lineThrough)));
      } else if (m[4] != null) {
        spans.add(TextSpan(
          text: m[4],
          style: base.copyWith(
            fontFamily: 'monospace',
            backgroundColor: Colors.black12,
          ),
        ));
      }
      last = m.end;
    }
    if (last < s.length) {
      spans.add(TextSpan(text: s.substring(last), style: base));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    return Text.rich(TextSpan(children: parse(text, base)));
  }
}
