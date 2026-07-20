import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../shared/widgets/settings_layout.dart';
import '../domain/epub_converter.dart';

class EpubConverterScreen extends StatefulWidget {
  const EpubConverterScreen({super.key});

  @override
  State<EpubConverterScreen> createState() => _EpubConverterScreenState();
}

class _EpubConverterScreenState extends State<EpubConverterScreen> {
  XFile? _source;
  Uint8List? _sourceBytes;
  EpubBook? _book;
  EpubOutputFormat _format = EpubOutputFormat.csv;
  EpubRubyHandling _rubyHandling = EpubRubyHandling.removeHiragana;
  bool _busy = false;
  String? _message;

  Future<void> _pickEpub() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'EPUB', extensions: ['epub']),
      ],
    );
    if (file == null) return;
    setState(() {
      _busy = true;
      _message = null;
      _source = file;
      _sourceBytes = null;
      _book = null;
      _rubyHandling = EpubRubyHandling.removeHiragana;
    });
    try {
      final bytes = await file.readAsBytes();
      final book = await compute(
        parseEpubRequest,
        EpubParseRequest(bytes: bytes, rubyHandling: _rubyHandling),
      );
      if (!mounted) return;
      setState(() {
        _sourceBytes = bytes;
        _book = book;
        _message =
            'Đã nhận diện ${book.language.label} · '
            '${book.chapters.length} chương · '
            '${book.translationRows.length} dòng.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Không thể đọc EPUB: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setRubyHandling(EpubRubyHandling value) async {
    final bytes = _sourceBytes;
    if (bytes == null || value == _rubyHandling) return;
    setState(() {
      _rubyHandling = value;
      _busy = true;
      _message = 'Đang xử lý lại furigana…';
    });
    try {
      final book = await compute(
        parseEpubRequest,
        EpubParseRequest(bytes: bytes, rubyHandling: value),
      );
      if (!mounted) return;
      setState(() {
        _book = book;
        _message =
            'Đã áp dụng: ${value.label} · '
            '${book.translationRows.length} dòng.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Không thể xử lý furigana: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _convert() async {
    final source = _source;
    final book = _book;
    if (source == null || book == null) return;
    final baseName = p.basenameWithoutExtension(source.name);
    final location = await getSaveLocation(
      suggestedName: '$baseName.${_format.extension}',
      acceptedTypeGroups: [
        XTypeGroup(label: _format.label, extensions: [_format.extension]),
      ],
    );
    if (location == null) return;
    setState(() {
      _busy = true;
      _message = 'Đang tạo ${_format.label}…';
    });
    try {
      final bytes = await compute(
        exportEpubRequest,
        EpubExportRequest(book: book, format: _format),
      );
      await File(location.path).writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      setState(() => _message = 'Đã lưu: ${location.path}');
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Không thể xuất file: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    return SettingsPage(
      title: 'Chuyển đổi EPUB',
      description:
          'Tách nội dung EPUB theo thứ tự spine và xuất sang dữ liệu dịch hoặc tài liệu đọc.',
      children: [
        SettingsSection(
          icon: Icons.auto_stories_outlined,
          accentColor: const Color(0xFF1565C0),
          title: 'Nguồn EPUB',
          description:
              'Tự nhận diện ngôn ngữ; sách Nhật có thêm tùy chọn furigana.',
          children: [
            SettingsControlRow(
              title: _source?.name ?? 'Chưa chọn file',
              description: book == null
                  ? 'Chọn một file .epub để đọc nội dung.'
                  : '${book.title} · ${book.chapters.length} chương',
              controlWidth: 220,
              control: Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Chọn EPUB'),
                  onPressed: _busy ? null : _pickEpub,
                ),
              ),
            ),
            if (book != null)
              SettingsControlRow(
                title: 'Ngôn ngữ nhận diện',
                description: '${book.language.label} (${book.language.code})',
                controlWidth: 430,
                control: book.language == EpubLanguage.japanese
                    ? DropdownMenu<EpubRubyHandling>(
                        key: ValueKey(_rubyHandling),
                        initialSelection: _rubyHandling,
                        expandedInsets: EdgeInsets.zero,
                        enabled: !_busy,
                        dropdownMenuEntries: [
                          for (final handling in EpubRubyHandling.values)
                            DropdownMenuEntry(
                              value: handling,
                              label: handling.label,
                            ),
                        ],
                        onSelected: (value) {
                          if (value != null) _setRubyHandling(value);
                        },
                      )
                    : Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Không cần xử lý furigana',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
              ),
          ],
        ),
        SettingsSection(
          icon: Icons.file_download_outlined,
          accentColor: const Color(0xFF00897B),
          title: 'Định dạng đầu ra',
          description:
              'CSV/Excel dùng hai cột id,text tương thích AI Translation Bridge.',
          children: [
            SettingsControlRow(
              title: 'Loại file',
              description: 'CSV, Excel, Markdown, Word hoặc văn bản thuần.',
              controlWidth: 430,
              control: Row(
                children: [
                  Expanded(
                    child: DropdownMenu<EpubOutputFormat>(
                      key: ValueKey(_format),
                      initialSelection: _format,
                      expandedInsets: EdgeInsets.zero,
                      dropdownMenuEntries: [
                        for (final format in EpubOutputFormat.values)
                          DropdownMenuEntry(
                            value: format,
                            label: '${format.label} (.${format.extension})',
                          ),
                      ],
                      onSelected: _busy
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _format = value);
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_alt),
                    label: const Text('Chuyển đổi'),
                    onPressed: _busy || book == null ? null : _convert,
                  ),
                ],
              ),
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  _message!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
        if (book != null)
          SettingsSection(
            icon: Icons.preview_outlined,
            accentColor: const Color(0xFF7B1FA2),
            title: 'Xem trước',
            description: 'Một số dòng đầu sau khi tách nội dung.',
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  book.translationRows.take(12).join('\n\n'),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
