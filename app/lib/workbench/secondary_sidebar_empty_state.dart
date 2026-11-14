import 'package:flutter/material.dart';

class SecondarySidebarEmptyState extends StatelessWidget {
  const SecondarySidebarEmptyState({super.key, this.title = '次侧栏'});

  static const semanticsLabel = '次侧栏为空。当前没有分配的视图。';
  final String title;

  String get _semanticsLabel =>
      title == '次侧栏' ? semanticsLabel : '$title为空。当前没有分配的视图。';

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF181B20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 34,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF2A2E37))),
            ),
            child: Text(
              title,
              style: const TextStyle(
                color: Color(0xFFCCCCCC),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Semantics(
                container: true,
                liveRegion: true,
                label: _semanticsLabel,
                child: const ExcludeSemantics(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 28,
                        color: Color(0xFF858585),
                      ),
                      SizedBox(height: 10),
                      Text(
                        '此侧栏暂时没有视图',
                        style: TextStyle(
                          color: Color(0xFF9B9B9B),
                          fontSize: 12,
                        ),
                      ),
                    ],
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
