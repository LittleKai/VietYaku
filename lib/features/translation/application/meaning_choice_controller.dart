import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/meaning_choice.dart';
import '../domain/token.dart';
import 'token_selection.dart';
import 'translation_controller.dart';
import 'viet_draft.dart';

typedef TokenSelectionReader = TokenSelection? Function();
typedef TranslationStateReader = TranslationState Function();
typedef DraftControllerReader = TextEditingController Function();

/// Chọn một cách dịch của token active và chèn vào bản dịch người dùng.
class MeaningChoiceController {
  const MeaningChoiceController({
    required this.readSelection,
    required this.readTranslation,
    required this.readDraft,
  });

  final TokenSelectionReader readSelection;
  final TranslationStateReader readTranslation;
  final DraftControllerReader readDraft;

  void choose(int index) {
    final selection = readSelection();
    if (selection == null || selection.origin != TokenSelectionOrigin.result) {
      return;
    }

    final state = readTranslation();
    Token? selected;
    for (final token in state.tokens) {
      final end = token.sourceStart + token.source.length;
      if (token.sourceStart == selection.start && end == selection.end) {
        selected = token;
        break;
      }
    }
    final rawValue = selected?.rawValue;
    if (rawValue == null) return;
    final choice = choiceAt(meaningChoicesFromValue(rawValue), index);
    if (choice == null) return;
    insertIntoVietDraft(readDraft(), choice);
  }
}

final meaningChoiceControllerProvider = Provider<MeaningChoiceController>(
  (ref) => MeaningChoiceController(
    readSelection: () => ref.read(tokenSelectionProvider),
    readTranslation: () => ref.read(translationControllerProvider),
    readDraft: () => ref.read(vietDraftControllerProvider),
  ),
);
