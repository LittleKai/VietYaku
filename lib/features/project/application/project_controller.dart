import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../dictionary/application/dictionaries_provider.dart';
import '../../translation/application/translation_controller.dart';
import '../data/project_store.dart';
import '../data/translation_memory_store.dart';
import '../domain/project_document.dart';
import '../domain/project_segment.dart';
import '../domain/sentence_segmenter.dart';

typedef ProjectTranslator = String Function(String source);

class ProjectState {
  const ProjectState({
    this.root,
    this.sourcePath,
    this.document,
    this.selectedIndex = 0,
    this.error,
  });

  final Directory? root;
  final String? sourcePath;
  final ProjectDocument? document;
  final int selectedIndex;
  final String? error;

  ProjectState copyWith({
    Directory? root,
    String? sourcePath,
    ProjectDocument? document,
    int? selectedIndex,
    String? error,
    bool clearError = false,
  }) => ProjectState(
    root: root ?? this.root,
    sourcePath: sourcePath ?? this.sourcePath,
    document: document ?? this.document,
    selectedIndex: selectedIndex ?? this.selectedIndex,
    error: clearError ? null : error ?? this.error,
  );
}

class ProjectController extends Notifier<ProjectState> {
  @override
  ProjectState build() => const ProjectState();

  Future<void> openSourcePath(
    String path, {
    Directory? projectRoot,
    ProjectTranslator? machineTranslate,
  }) async {
    try {
      final sourceFile = File(path);
      final source = await sourceFile.readAsString();
      final root =
          projectRoot ??
          Directory(
            p.join(
              sourceFile.parent.path,
              '${p.basenameWithoutExtension(sourceFile.path)}.vietyaku',
            ),
          );
      final store = ProjectStore(root);
      ProjectDocument document;
      if (await File(p.join(root.path, 'project.json')).exists()) {
        document = await store.open();
      } else {
        final segments = SentenceSegmenter.split(source)
            .asMap()
            .entries
            .map(
              (entry) => ProjectSegment.fromSource(
                segmentId: 's${entry.key + 1}',
                source: entry.value,
                machineOutput:
                    machineTranslate?.call(entry.value) ??
                    _translateSegment(entry.value),
              ),
            )
            .toList(growable: false);
        document = ProjectDocument(
          name: p.basenameWithoutExtension(sourceFile.path),
          segments: segments,
        );
      }
      state = ProjectState(
        root: root,
        sourcePath: sourceFile.path,
        document: document,
      );
    } catch (error) {
      state = state.copyWith(error: '$error');
    }
  }

  void selectSegment(int index) {
    final count = state.document?.segments.length ?? 0;
    if (index < 0 || index >= count) return;
    state = state.copyWith(selectedIndex: index);
  }

  void setTarget(int index, String target) {
    final document = state.document;
    if (document == null || index < 0 || index >= document.segments.length) {
      return;
    }
    final segments = [...document.segments];
    segments[index] = segments[index].copyWith(
      editedTarget: target,
      status: ProjectSegmentStatus.draft,
    );
    state = state.copyWith(document: document.copyWith(segments: segments));
  }

  void markReviewed(int index) {
    final document = state.document;
    if (document == null || index < 0 || index >= document.segments.length) {
      return;
    }
    final segments = [...document.segments];
    segments[index] = segments[index].copyWith(
      status: ProjectSegmentStatus.reviewed,
      updatedAt: DateTime.now().toUtc(),
    );
    state = state.copyWith(document: document.copyWith(segments: segments));
  }

  Future<void> applyTmSuggestion(int index, [String? suggestion]) async {
    final document = state.document;
    final root = state.root;
    if (document == null ||
        root == null ||
        index < 0 ||
        index >= document.segments.length) {
      return;
    }
    final segment = document.segments[index];
    if (segment.editedTarget.trim().isNotEmpty) return;
    final value =
        suggestion ??
        await TranslationMemoryStore(root).lookupExact(segment.source);
    if (value == null || value.trim().isEmpty) return;
    setTarget(index, value);
  }

  Future<void> save() async {
    final document = state.document;
    final root = state.root;
    if (document == null || root == null) return;
    await ProjectStore(root).save(document);
    final tm = TranslationMemoryStore(root);
    for (final segment in document.segments) {
      await tm.upsertReviewed(segment);
    }
    final targetDir = Directory(p.join(root.path, 'target'));
    await targetDir.create(recursive: true);
    final target = File(p.join(targetDir.path, 'translated.txt'));
    await target.writeAsString(
      document.segments.map((segment) => segment.editedTarget).join('\n'),
      flush: true,
    );
  }

  String _translateSegment(String source) {
    final dictionaries = ref.read(dictionariesProvider).valueOrNull;
    if (dictionaries == null) return source;
    ref.read(translationControllerProvider.notifier).translate(source);
    final tokens = ref.read(translationControllerProvider).tokens;
    return tokens.map((token) => token.display).join();
  }
}

final projectControllerProvider =
    NotifierProvider<ProjectController, ProjectState>(ProjectController.new);
