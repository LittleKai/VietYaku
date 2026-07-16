import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/cjk.dart';
import '../../../shared/widgets/entry_edit_dialog.dart';
import '../../../shared/widgets/tts_button.dart';
import '../../dictionary/application/dictionaries_provider.dart';
import '../application/recent_files_provider.dart';
import '../application/translation_controller.dart';
import '../domain/translation_engine.dart';

class SourcePane extends ConsumerStatefulWidget {
  const SourcePane({super.key});

  @override
  ConsumerState<SourcePane> createState() => _SourcePaneState();
}

class _SourcePaneState extends ConsumerState<SourcePane> {
  final _controller = TextEditingController();
  bool _dragging = false;

  // Clipboard watcher (Phase 5b): poll 1s, text CJK mới → tự dán + dịch.
  bool _watchingClipboard = false;
  Timer? _clipboardTimer;
  String? _lastClipboard;

  @override
  void dispose() {
    _clipboardTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleClipboardWatch() async {
    if (_watchingClipboard) {
      _clipboardTimer?.cancel();
      _clipboardTimer = null;
      setState(() => _watchingClipboard = false);
      return;
    }
    // Mồi giá trị hiện tại để chỉ phản ứng với text MỚI.
    _lastClipboard =
        (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    _clipboardTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _pollClipboard());
    setState(() => _watchingClipboard = true);
  }

  Future<void> _pollClipboard() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || text == _lastClipboard) return;
    _lastClipboard = text;
    if (!_containsCjk(text) || !mounted) return;
    _controller.text = text;
    _translate();
  }

  static bool _containsCjk(String text) {
    for (var i = 0; i < text.length; i++) {
      if (isCjkCodePoint(codePointAt(text, i))) return true;
    }
    return false;
  }

  Future<void> _openFile() async {
    const typeGroup = XTypeGroup(label: 'Text', extensions: ['txt']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    await _loadFile(file.path);
  }

  Future<void> _loadFile(String path) async {
    try {
      var text = await File(path).readAsString();
      if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
        text = text.substring(1);
      }
      _controller.text = text;
      await ref.read(recentFilesProvider.notifier).add(path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không đọc được file: $e')),
      );
    }
  }

  void _translate() {
    ref
        .read(translationControllerProvider.notifier)
        .translate(_controller.text);
  }

  Widget _buildEditor(BuildContext context) {
    return TextField(
      controller: _controller,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      decoration: const InputDecoration(
        border: InputBorder.none,
        contentPadding: EdgeInsets.all(12),
        hintText: 'Dán văn bản Nhật/Trung hoặc kéo-thả file .txt…',
      ),
      contextMenuBuilder: (context, editableTextState) {
        final value = editableTextState.textEditingValue;
        final selection = value.selection.textInside(value.text).trim();
        final items = [...editableTextState.contextMenuButtonItems];
        if (selection.isNotEmpty) {
          items.insert(
            0,
            ContextMenuButtonItem(
              label: 'Thêm vào Names',
              onPressed: () {
                editableTextState.hideToolbar();
                showEntryEditDialog(context, ref,
                    word: selection, toNames: true);
              },
            ),
          );
        }
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: editableTextState.contextMenuAnchors,
          buttonItems: items,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final mode =
        ref.watch(translationControllerProvider.select((s) => s.mode));
    final dictsLoading = ref.watch(dictionariesProvider).isLoading;
    final recentFiles = ref.watch(recentFilesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<TranslationMode>(
                segments: const [
                  ButtonSegment(
                      value: TranslationMode.japanese, label: Text('Nhật')),
                  ButtonSegment(
                      value: TranslationMode.chinese, label: Text('Trung')),
                ],
                selected: {mode},
                onSelectionChanged: (selection) => ref
                    .read(translationControllerProvider.notifier)
                    .setMode(selection.first),
              ),
              IconButton(
                icon: const Icon(Icons.folder_open),
                tooltip: 'Mở file .txt',
                onPressed: _openFile,
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.history),
                tooltip: 'File gần đây',
                enabled: recentFiles.isNotEmpty,
                onSelected: _loadFile,
                itemBuilder: (context) => [
                  for (final path in recentFiles)
                    PopupMenuItem(
                      value: path,
                      child: Text(p.basename(path),
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
              ),
              IconButton(
                icon: Icon(_watchingClipboard
                    ? Icons.content_paste
                    : Icons.content_paste_off),
                isSelected: _watchingClipboard,
                tooltip: _watchingClipboard
                    ? 'Đang theo dõi clipboard (bấm để tắt)'
                    : 'Theo dõi clipboard: copy text CJK → tự dán + dịch',
                onPressed: _toggleClipboardWatch,
              ),
              TtsButton(
                textProvider: () => _controller.text,
                mode: mode,
                tooltip: 'Đọc cả đoạn',
              ),
              FilledButton.icon(
                icon: const Icon(Icons.translate),
                label: const Text('Dịch'),
                onPressed: dictsLoading ? null : _translate,
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: DropTarget(
              onDragEntered: (_) => setState(() => _dragging = true),
              onDragExited: (_) => setState(() => _dragging = false),
              onDragDone: (detail) async {
                setState(() => _dragging = false);
                if (detail.files.isNotEmpty) {
                  await _loadFile(detail.files.first.path);
                }
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _dragging
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                    width: _dragging ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _buildEditor(context),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
