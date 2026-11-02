import 'package:flutter/material.dart';

/// A bounded option list for the active TextMate snippet choice.
///
/// Keyboard handling stays with the workbench editor focus route so Shift+Tab
/// can keep its snippet-navigation priority while the list is visible.
class SnippetChoiceSuggestionList extends StatelessWidget {
  const SnippetChoiceSuggestionList({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onPreview,
    required this.onAccept,
  }) : assert(options.length > 0);

  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onPreview;
  final ValueChanged<int> onAccept;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleCount = options.length.clamp(1, 8);
    return Material(
      key: const ValueKey<String>('snippet-choice-suggestion-list'),
      color: theme.colorScheme.surfaceContainer,
      elevation: 8,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 256,
        height: visibleCount * 34,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 2),
          itemExtent: 34,
          itemCount: options.length,
          itemBuilder: (context, index) {
            final selected = index == selectedIndex;
            return Semantics(
              key: ValueKey<String>('snippet-choice-option-$index'),
              button: true,
              selected: selected,
              label: options[index],
              child: MouseRegion(
                onHover: (_) => onPreview(index),
                child: InkWell(
                  onTap: () => onAccept(index),
                  child: ColoredBox(
                    key: selected
                        ? ValueKey<String>(
                            'snippet-choice-option-highlighted-$index',
                          )
                        : null,
                    color: selected
                        ? theme.colorScheme.primary.withValues(alpha: 0.22)
                        : Colors.transparent,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          options[index],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
