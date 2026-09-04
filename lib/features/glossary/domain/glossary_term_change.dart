/// Một sửa đổi Global Glossary đang chờ đẩy lên LittleKai server.
///
/// Server dùng chung collection với từ điển VietPhrase/Lạc Việt nhưng tách bằng
/// `kind`: `glossaryTerm` chỉ đi qua `/api/glossary/terms/sync`, nơi
/// AI_Translation_Bridge kéo về merge vào `Global Glossary.json` của nó.
class GlossaryTermChange {
  static const kind = 'glossaryTerm';

  final String source;
  final String target;
  final bool isDelete;

  const GlossaryTermChange({
    required this.source,
    this.target = '',
    this.isDelete = false,
  });

  /// Server từ chối cả lô (HTTP 400) nếu một mục sai định dạng, mà lô hỏng thì
  /// hàng đợi không bao giờ trống — nên lọc ngay lúc xếp hàng.
  /// Giới hạn khớp `normalizeItems` bên `LittleKai-server/utils/glossarySync.js`.
  bool get isValid {
    if (source.isEmpty || source.length > 256) return false;
    if (RegExp(r'[=\r\n\x00]').hasMatch(source)) return false;
    if (isDelete) return true;
    return target.isNotEmpty &&
        target.length <= 4096 &&
        !RegExp(r'[\r\n\x00]').hasMatch(target);
  }

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'source': source,
    if (!isDelete) 'target': target,
    if (isDelete) 'operation': 'delete',
  };
}
