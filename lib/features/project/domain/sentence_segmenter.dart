import '../../../core/cjk.dart';

class SentenceSegmenter {
  const SentenceSegmenter._();

  static List<String> split(String text) {
    final segments = <String>[];
    var start = 0;
    var i = 0;
    while (i < text.length) {
      final length = runeLengthAt(text, i);
      final value = text.substring(i, i + length);
      final isBoundary = const {
        '。',
        '．',
        '！',
        '？',
        '!',
        '?',
        '…',
        '\n',
        '\r',
      }.contains(value);
      if (isBoundary) {
        final part = text.substring(start, i + length).trim();
        if (part.isNotEmpty) segments.add(part);
        start = i + length;
      }
      i += length;
    }
    final tail = text.substring(start).trim();
    if (tail.isNotEmpty) segments.add(tail);
    return List<String>.unmodifiable(segments);
  }
}
