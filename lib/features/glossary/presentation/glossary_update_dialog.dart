import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/app_dialog.dart';
import '../../translation/application/translation_controller.dart';
import '../../translation/domain/translation_engine.dart';
import '../../translation/domain/vietphrase_value.dart';
import '../application/glossary_service_provider.dart';
import '../application/glossary_sync_controller.dart';
import '../data/glossary_service.dart';
import '../domain/glossary_term.dart';

const _glossaryAccent = Color(0xFF6A1B9A);

/// Nghĩa ghi vào glossary: gom tất cả các cách dịch của các tầng nghĩa,
/// lọc sạch marker số và từ loại, nối bằng dấu `/`.
/// VD: `(n)/ký ức/hồi ức/(2)/(v)/nhớ lại` -> `ký ức/hồi ức/nhớ lại`.
String glossaryTargetOf(String meaning) => allVietPhraseMeaningsClean(meaning);

/// Cầu nối đọc nội dung ô Nghĩa sau khi dialog đã đóng (controller sống theo
/// vòng đời widget, dispose sau animation thoát).
class _TargetHolder {
  _TargetHolder(this.text);

  String text;
}

/// Xác nhận rồi ghi [source] vào `Global Glossary.json` của ngôn ngữ đang dịch.
/// Dialog hiện thông tin mục từ đang có trong glossary (nếu có) trước khi ghi.
///
/// Trả về [GlossaryTerm] khi file glossary THỰC SỰ được ghi (hoặc đã trùng khớp) —
/// dialog gọi nó (Sửa vào VietPhrase) dựa vào đây để nạp lại trạng thái
/// glossary đang hiển thị ngay lập tức.
Future<GlossaryTerm?> showGlossaryUpdateDialog(
  BuildContext context,
  WidgetRef ref, {
  required String source,
  required String meaning,
  TranslationMode? mode,
}) async {
  final TranslationMode activeMode = mode ?? ref.read(currentModeProvider);
  final service = ref.read(glossaryServiceProvider);
  final lang = GlossaryService.langFor(activeMode);
  final initialTarget = glossaryTargetOf(meaning);
  if (source.isEmpty || initialTarget.isEmpty) {
    if (context.mounted) {
      _showMessage(context, 'Cần cả từ nguồn và nghĩa để cập nhật glossary.');
    }
    return null;
  }

  final GlossaryTerm? existing;
  try {
    existing = await service.find(activeMode, source);
  } catch (_) {
    if (context.mounted) {
      _showMessage(context, 'Không đọc được Global Glossary $lang.');
    }
    return null;
  }
  if (!context.mounted) return null;

  final holder = _TargetHolder(initialTarget);

  final confirmed = await showAppDialog<bool>(
    context: context,
    icon: Icons.menu_book_outlined,
    accentColor: _glossaryAccent,
    title: 'Cập nhật Global Glossary $lang',
    description: existing == null
        ? 'Từ này chưa có trong glossary — sẽ được thêm mới.'
        : 'Từ này đã có trong glossary — nghĩa sẽ được ghi đè.',
    width: 560,
    content: _GlossaryPreview(
      lang: lang,
      source: source,
      meaning: meaning,
      existing: existing,
      holder: holder,
    ),
    actionsBuilder: (dialogContext) => [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext, false),
        child: const Text('Hủy'),
      ),
      FilledButton.icon(
        icon: const Icon(Icons.menu_book_outlined, size: 18),
        onPressed: () => Navigator.pop(dialogContext, true),
        label: Text(existing == null ? 'Thêm vào glossary' : 'Ghi đè glossary'),
      ),
    ],
  );
  if (confirmed != true) return null;

  final target = holder.text.trim();
  if (target.isEmpty) {
    if (context.mounted) {
      _showMessage(context, 'Nghĩa trong glossary không được để trống.');
    }
    return null;
  }

  if (existing != null && existing.target.trim() == target) {
    if (context.mounted) {
      _showMessage(
        context,
        'Nghĩa Global Glossary $lang đã trùng khớp: $source → $target',
      );
    }
    return existing;
  }

  final newTerm = (existing != null)
      ? existing.copyWith(target: target, createdBy: 'user')
      : GlossaryTerm(
          source: source.trim(),
          target: target,
          dateAdded: GlossaryService.todayStamp(),
        );

  try {
    await service.upsert(activeMode, source: source, target: target);
  } catch (_) {
    if (context.mounted) {
      _showMessage(context, 'Không ghi được Global Glossary $lang.');
    }
    return null;
  }
  // Bảng đồng bộ hàng loạt đang mở phải bỏ mục vừa xử lý (cả hai chiều).
  ref.invalidate(
    glossarySyncRowsProvider(GlossarySyncDirection.glossaryToVietPhrase),
  );
  ref.invalidate(
    glossarySyncRowsProvider(GlossarySyncDirection.vietPhraseToGlossary),
  );
  if (context.mounted) {
    _showMessage(context, 'Đã cập nhật Global Glossary $lang: $source → $target');
  }
  return newTerm;
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// So sánh mục đang có trong glossary với giá trị sắp ghi, cho phép sửa trực tiếp target.
class _GlossaryPreview extends StatefulWidget {
  const _GlossaryPreview({
    required this.lang,
    required this.source,
    required this.meaning,
    required this.existing,
    required this.holder,
  });

  final String lang;
  final String source;
  final String meaning;
  final GlossaryTerm? existing;
  final _TargetHolder holder;

  @override
  State<_GlossaryPreview> createState() => _GlossaryPreviewState();
}

class _GlossaryPreviewState extends State<_GlossaryPreview> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.holder.text)
      ..addListener(() => widget.holder.text = _controller.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final term = widget.existing;
    final lang = widget.lang;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row(context, 'Từ nguồn', widget.source),
        _row(context, 'Nghĩa trong VietPhrase', widget.meaning),
        const Divider(height: 26),
        Text(
          term == null
              ? 'Mục mới trong Global Glossary $lang'
              : 'Mục hiện có trong Global Glossary $lang',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: _glossaryAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        if (term != null) ...[
          _row(context, 'Nghĩa hiện tại', term.target),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _controller,
          decoration: const InputDecoration(
            labelText: 'Nghĩa trong glossary (target)',
            helperText: 'Dùng dấu / để ngăn cách nhiều nghĩa.',
          ),
          autofocus: true,
        ),
        const SizedBox(height: 12),
        _row(context, 'kind', term?.kind ?? 'proper_noun'),
        _row(context, 'notes', (term?.notes ?? '').isEmpty ? '—' : term!.notes),
        _row(context, 'created_by', term?.createdBy ?? '—', newValue: 'user'),
        _row(
          context,
          'date_added',
          term?.dateAdded ?? GlossaryService.todayStamp(),
        ),
      ],
    );
  }

  /// Một dòng thuộc tính; có [newValue] thì hiện dạng `cũ → mới`.
  Widget _row(
    BuildContext context,
    String label,
    String value, {
    String? newValue,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final changed = newValue != null && newValue != value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(
              label,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: changed
                ? Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: value,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const TextSpan(text: '  →  '),
                        TextSpan(
                          text: newValue,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  )
                : SelectableText(value),
          ),
        ],
      ),
    );
  }
}

/// Sửa RIÊNG nghĩa (`target`) của một mục đã có trong `Global Glossary.json` —
/// giá trị tự nhập, KHÔNG lấy theo ô Nghĩa của dialog VietPhrase.
///
/// Chỉ có ích khi người dùng TẮT "Tự động cập nhật Glossary khi bấm Lưu từ":
/// bật thì glossary luôn bám theo VietPhrase, tắt thì hai bên được phép lệch
/// nhau nên phải sửa được độc lập.
///
/// Trả về [GlossaryTerm] khi file glossary THỰC SỰ được ghi (hoặc đã trùng khớp).
Future<GlossaryTerm?> showGlossaryEditDialog(
  BuildContext context,
  WidgetRef ref, {
  required GlossaryTerm term,
  TranslationMode? mode,
}) async {
  final TranslationMode activeMode = mode ?? ref.read(currentModeProvider);
  final service = ref.read(glossaryServiceProvider);
  final lang = GlossaryService.langFor(activeMode);
  final holder = _TargetHolder(term.target);

  final confirmed = await showAppDialog<bool>(
    context: context,
    icon: Icons.edit_calendar_outlined,
    accentColor: _glossaryAccent,
    title: 'Sửa Global Glossary $lang',
    description: 'Chỉ đổi nghĩa bên glossary; nghĩa VietPhrase giữ nguyên.',
    width: 560,
    content: _GlossaryTargetEditor(holder: holder, term: term),
    actionsBuilder: (dialogContext) => [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext, false),
        child: const Text('Hủy'),
      ),
      FilledButton.icon(
        icon: const Icon(Icons.save_outlined, size: 18),
        onPressed: () => Navigator.pop(dialogContext, true),
        label: const Text('Lưu glossary'),
      ),
    ],
  );
  if (confirmed != true) return null;

  final target = holder.text.trim();
  if (target.isEmpty) {
    if (context.mounted) {
      _showMessage(context, 'Nghĩa trong glossary không được để trống.');
    }
    return null;
  }
  if (target == term.target.trim()) {
    return term;
  }

  final updatedTerm = term.copyWith(target: target, createdBy: 'user');
  try {
    await service.upsert(activeMode, source: term.source, target: target);
  } catch (_) {
    if (context.mounted) {
      _showMessage(context, 'Không ghi được Global Glossary $lang.');
    }
    return null;
  }
  ref.invalidate(
    glossarySyncRowsProvider(GlossarySyncDirection.glossaryToVietPhrase),
  );
  ref.invalidate(
    glossarySyncRowsProvider(GlossarySyncDirection.vietPhraseToGlossary),
  );
  if (context.mounted) {
    _showMessage(
      context,
      'Đã cập nhật Global Glossary $lang: ${term.source} → $target',
    );
  }
  return updatedTerm;
}


class _GlossaryTargetEditor extends StatefulWidget {
  const _GlossaryTargetEditor({required this.holder, required this.term});

  final _TargetHolder holder;
  final GlossaryTerm term;

  @override
  State<_GlossaryTargetEditor> createState() => _GlossaryTargetEditorState();
}

class _GlossaryTargetEditorState extends State<_GlossaryTargetEditor> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.term.target)
      ..addListener(() => widget.holder.text = _controller.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final term = widget.term;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Từ nguồn', style: TextStyle(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        SelectableText(
          term.source,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          decoration: const InputDecoration(
            labelText: 'Nghĩa trong glossary (target)',
            helperText: 'Dùng dấu / để ngăn cách nhiều nghĩa.',
          ),
          autofocus: true,
        ),
      ],
    );
  }
}
