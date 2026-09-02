import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Render Markdown cho phần thân của một mục tra (AI / online).
///
/// AI trả về Markdown (đậm, heading, gạch đầu dòng); trước đây hiển thị nguyên
/// văn nên đầy `**` và `###`. Dùng chung style chữ của pane để cỡ chữ/font vẫn
/// theo Cài đặt, và bật `selectable` để copy được như SelectableText cũ.
class MarkdownBodyView extends StatelessWidget {
  const MarkdownBodyView({super.key, required this.data, required this.style});

  final String data;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final headingStyle = style.copyWith(
      fontWeight: FontWeight.bold,
      color: scheme.primary,
    );

    return MarkdownBody(
      data: data,
      selectable: true,
      // Bảng/ảnh/link hiếm khi xuất hiện trong nghĩa từ điển; giữ styleSheet
      // tối giản để không phá bố cục hẹp của ô Nghĩa.
      styleSheet: MarkdownStyleSheet(
        p: style,
        pPadding: const EdgeInsets.only(bottom: 2),
        strong: style.copyWith(fontWeight: FontWeight.bold),
        em: style.copyWith(fontStyle: FontStyle.italic),
        h1: headingStyle,
        h2: headingStyle,
        h3: headingStyle,
        h4: headingStyle,
        h5: headingStyle,
        h6: headingStyle,
        h1Padding: const EdgeInsets.only(top: 6, bottom: 2),
        h2Padding: const EdgeInsets.only(top: 6, bottom: 2),
        h3Padding: const EdgeInsets.only(top: 6, bottom: 2),
        listBullet: style,
        listBulletPadding: const EdgeInsets.only(right: 4),
        blockSpacing: 4,
        code: style.copyWith(
          fontFamily: 'Consolas',
          backgroundColor: scheme.surfaceContainerHighest,
        ),
        codeblockDecoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        blockquoteDecoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}
