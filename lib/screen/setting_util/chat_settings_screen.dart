import 'package:flutter/material.dart';

import '../../service/ChatAppearanceService.dart';
import '../../util/AppBarStyle.dart';

class ChatSettingsScreen extends StatelessWidget {
  const ChatSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBarStyle.build(title: 'Chat settings'),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Conversation appearance',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Choose a background for all your conversations on this device.',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          ValueListenableBuilder<Color>(
            valueListenable: ChatAppearanceService.backgroundColor,
            builder: (context, selectedColor, _) => Container(
              height: 190,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: selectedColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _PreviewBubble(
                      text: 'Hi! This is your chat background.',
                      color: colors.surface,
                      textColor: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _PreviewBubble(
                      text: 'Looks lovely 💕',
                      color: Colors.pinkAccent,
                      textColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Background colors',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<Color>(
            valueListenable: ChatAppearanceService.backgroundColor,
            builder: (context, selectedColor, _) => Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final color in ChatAppearanceService.availableColors)
                  _ColorChoice(
                    color: color,
                    selected: color.toARGB32() == selectedColor.toARGB32(),
                    onTap: () => ChatAppearanceService.setBackgroundColor(color),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () => ChatAppearanceService.setBackgroundColor(
              ChatAppearanceService.defaultBackground,
            ),
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Reset to default'),
          ),
        ],
      ),
    );
  }
}

class _ColorChoice extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorChoice({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Colors.pinkAccent : Colors.grey.shade400,
              width: selected ? 3 : 1,
            ),
          ),
          child: selected
              ? Icon(
                  Icons.check_rounded,
                  color: color.computeLuminance() < 0.35
                      ? Colors.white
                      : Colors.pinkAccent,
                )
              : null,
        ),
      ),
    );
  }
}

class _PreviewBubble extends StatelessWidget {
  final String text;
  final Color color;
  final Color textColor;

  const _PreviewBubble({
    required this.text,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: TextStyle(color: textColor, fontSize: 13),
      ),
    );
  }
}
