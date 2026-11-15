import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  String get template {
    if (takesCount) return '#${key}3{}';
    if (key == 'if' || key == 'else') return '#$key{}';
    return '#$key{}';
  }
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
        description: 'Monospace / code text (Telegram style)',
        example: '#code{x = 1}',
        icon: Icons.code_rounded),
    ShortcutKey(
        key: 'capital',
        description: 'Capitalize each word',
        example: '#capital{hello world} → Hello World',
        icon: Icons.title_rounded),
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
        key: 'if',
        description: 'Condition truthy check: #if{cond ? val}',
        example: '#if{name ? Welcome} or #if{cond}',
        icon: Icons.alt_route_rounded),
    ShortcutKey(
        key: 'else',
        description: 'Fallback alternative: #else{fallback}',
        example: '#else{Default text}',
        icon: Icons.help_outline_rounded),
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

  // ───────────── Converting on send / format ─────────────

  static final RegExp _shortcut = RegExp(r'#([A-Za-z]+)(\d*)\{([^{}]*)\}');

  /// Converts `#key{content}` into the final message text.
  /// Innermost shortcuts are resolved first, so nesting works cleanly:
  /// e.g. `#bold{#upper{#italic{text}}}}`
  /// Unknown keys are left untouched.
  static String apply(String input) {
    var text = input;
    for (var i = 0; i < 15; i++) {
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
    switch (k.key) {
      case 'bold':
        if (c.isEmpty) return '';
        return '**$c**';
      case 'italic':
        if (c.isEmpty) return '';
        return '*$c*';
      case 'strike':
        if (c.isEmpty) return '';
        return '~~$c~~';
      case 'code':
        if (c.isEmpty) return '';
        // If it's multi-line, format as code block, otherwise inline code
        if (c.contains('\n')) {
          return '```\n$c\n```';
        }
        return '`$c`';
      case 'capital':
        if (c.isEmpty) return '';
        return _capitalize(c);
      case 'upper':
        if (c.isEmpty) return '';
        return c.toUpperCase();
      case 'lower':
        if (c.isEmpty) return '';
        return c.toLowerCase();
      case 'if':
        // Supports: #if{cond ? value} or #if{val}
        return _evaluateIf(c);
      case 'else':
        return c.trim();
      case 'loop':
        if (c.isEmpty) return '';
        final n = (int.tryParse(count) ?? 2).clamp(1, 50);
        return List.filled(n, c.trim()).join(' ');
      default:
        return c;
    }
  }

  static String _capitalize(String s) {
    return s.split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  static String _evaluateIf(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return '';

    // If has '?' e.g. "cond ? output"
    if (trimmed.contains('?')) {
      final parts = trimmed.split('?');
      final cond = parts[0].trim().toLowerCase();
      final rest = parts.sublist(1).join('?');
      final isTrue = cond.isNotEmpty &&
          cond != 'false' &&
          cond != '0' &&
          cond != 'null' &&
          cond != 'no';

      if (rest.contains(':')) {
        final branches = rest.split(':');
        return isTrue ? branches[0].trim() : branches.sublist(1).join(':').trim();
      }
      return isTrue ? rest.trim() : '';
    }

    // Direct check: if content is not "false" / "0" / "null" / "no"
    final cond = trimmed.toLowerCase();
    if (cond == 'false' || cond == '0' || cond == 'null' || cond == 'no') {
      return '';
    }
    return trimmed;
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

/// ----------------------------------------------------------------------------
/// Renders Markdown formatted text + Telegram style code blocks & copy snippet
/// ----------------------------------------------------------------------------
class FormattedMessageText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final bool isMe;

  const FormattedMessageText(
    this.text, {
    super.key,
    this.style,
    this.isMe = false,
  });

  /// Parse text for code blocks ```code```, inline code `code`,
  /// bold **bold**, italic *italic*, strikethrough ~~strike~~, and combinations like ***bold italic***
  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;

    // Check if the message contains multi-line code block ```code```
    if (text.contains('```')) {
      return _buildWithCodeBlocks(context, text, baseStyle);
    }

    return Text.rich(
      TextSpan(children: _parseInlineMarkdown(text, baseStyle, isMe: isMe)),
    );
  }

  Widget _buildWithCodeBlocks(BuildContext context, String content, TextStyle base) {
    final parts = content.split('```');
    final widgets = <Widget>[];

    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (i.isOdd) {
        // This is a Telegram-style code block
        widgets.add(_TelegramCodeBlock(code: part.trim(), isMe: isMe));
      } else if (part.isNotEmpty) {
        widgets.add(Text.rich(
          TextSpan(children: _parseInlineMarkdown(part, base, isMe: isMe)),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  static List<InlineSpan> _parseInlineMarkdown(String s, TextStyle base, {bool isMe = false}) {
    final spans = <InlineSpan>[];

    // Regex for:
    // 1: ***bold italic***
    // 2: **bold**
    // 3: *italic*
    // 4: ~~strikethrough~~
    // 5: `inline code`
    final regex = RegExp(
      r'\*\*\*(.+?)\*\*\*|\*\*(.+?)\*\*|\*(.+?)\*|~~(.+?)~~|`(.+?)`',
      dotAll: true,
    );

    var last = 0;
    for (final m in regex.allMatches(s)) {
      if (m.start > last) {
        spans.add(TextSpan(text: s.substring(last, m.start), style: base));
      }

      if (m[1] != null) {
        // ***bold italic***
        spans.add(TextSpan(
          text: m[1],
          style: base.copyWith(
            fontWeight: FontWeight.bold,
            fontStyle: FontStyle.italic,
          ),
        ));
      } else if (m[2] != null) {
        // **bold** - might also contain inner italic *...*
        final boldContent = m[2]!;
        if (boldContent.startsWith('*') && boldContent.endsWith('*') && boldContent.length > 2) {
          spans.add(TextSpan(
            text: boldContent.substring(1, boldContent.length - 1),
            style: base.copyWith(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic),
          ));
        } else {
          spans.add(TextSpan(
            text: boldContent,
            style: base.copyWith(fontWeight: FontWeight.bold),
          ));
        }
      } else if (m[3] != null) {
        // *italic* - might also contain inner bold **...**
        final italicContent = m[3]!;
        if (italicContent.startsWith('**') && italicContent.endsWith('**') && italicContent.length > 4) {
          spans.add(TextSpan(
            text: italicContent.substring(2, italicContent.length - 2),
            style: base.copyWith(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic),
          ));
        } else {
          spans.add(TextSpan(
            text: italicContent,
            style: base.copyWith(fontStyle: FontStyle.italic),
          ));
        }
      } else if (m[4] != null) {
        // ~~strike~~
        spans.add(TextSpan(
          text: m[4],
          style: base.copyWith(decoration: TextDecoration.lineThrough),
        ));
      } else if (m[5] != null) {
        // `inline code` - Telegram inline code badge style
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _TelegramInlineCode(code: m[5]!, isMe: isMe),
        ));
      }

      last = m.end;
    }

    if (last < s.length) {
      spans.add(TextSpan(text: s.substring(last), style: base));
    }

    return spans;
  }
}

/// ----------------------------------------------------------------------------
/// Telegram Style Inline Code (`code`)
/// ----------------------------------------------------------------------------
class _TelegramInlineCode extends StatelessWidget {
  final String code;
  final bool isMe;

  const _TelegramInlineCode({required this.code, this.isMe = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isMe
        ? Colors.black.withValues(alpha: 0.22)
        : (isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFF0F0F0));
    final fg = isMe
        ? Colors.white
        : (isDark ? const Color(0xFFFF80AB) : const Color(0xFFE91E63));

    return InkWell(
      borderRadius: BorderRadius.circular(5),
      onTap: () {
        Clipboard.setData(ClipboardData(text: code));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Code copied to clipboard"),
            duration: Duration(milliseconds: 900),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isMe ? Colors.white24 : Colors.pink.withValues(alpha: 0.15),
            width: 0.8,
          ),
        ),
        child: Text(
          code,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      ),
    );
  }
}

/// ----------------------------------------------------------------------------
/// Telegram Style Multi-Line Code Block (```code```) with Copy Header & Monospace
/// ----------------------------------------------------------------------------
class _TelegramCodeBlock extends StatelessWidget {
  final String code;
  final bool isMe;

  const _TelegramCodeBlock({required this.code, this.isMe = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isMe
        ? Colors.black.withValues(alpha: 0.28)
        : (isDark ? const Color(0xFF1E1E24) : const Color(0xFFF4F4F6));
    final borderColor = isMe
        ? Colors.white.withValues(alpha: 0.2)
        : (isDark ? Colors.white12 : Colors.grey.shade300);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with Copy action
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "CODE",
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    color: isMe ? Colors.white70 : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Code copied to clipboard"),
                        duration: Duration(milliseconds: 900),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.copy_rounded,
                          size: 13,
                          color: isMe ? Colors.white70 : Colors.pinkAccent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "Copy",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isMe ? Colors.white70 : Colors.pinkAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Code Content with horizontal scroll
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(10),
            child: Text(
              code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                color: isMe ? Colors.white : (isDark ? Colors.grey.shade200 : Colors.black87),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
