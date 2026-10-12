import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vietyaku/features/translation/application/meaning_choice_controller.dart';
import 'package:vietyaku/features/translation/application/token_selection.dart';
import 'package:vietyaku/features/translation/application/translation_controller.dart';
import 'package:vietyaku/features/translation/domain/token.dart';
import 'package:vietyaku/features/translation/domain/translation_engine.dart';
import 'package:vietyaku/features/translation/presentation/result_pane.dart';

void main() {
  test('choose inserts selected alternative at the draft caret', () {
    final draft = TextEditingController(text: 'đầu cuối');
    draft.selection = const TextSelection.collapsed(offset: 4);
    final controller = MeaningChoiceController(
      readSelection: () => const TokenSelection(
        start: 0,
        end: 1,
        word: '行',
        origin: TokenSelectionOrigin.result,
      ),
      readTranslation: () => const TranslationState(
        mode: TranslationMode.japanese,
        sourceText: '行',
        tokens: [
          Token(
            source: '行',
            sourceStart: 0,
            kind: TokenKind.matched,
            rawValue: 'hành/đi',
          ),
        ],
      ),
      readDraft: () => draft,
    );

    controller.choose(2);

    expect(draft.text, 'đầu đi cuối');
    draft.dispose();
  });

  test('choose is a no-op without a result token or for an invalid index', () {
    final draft = TextEditingController(text: 'giữ nguyên');
    final controller = MeaningChoiceController(
      readSelection: () => null,
      readTranslation: () => const TranslationState(
        mode: TranslationMode.japanese,
        sourceText: '行',
        tokens: [
          Token(
            source: '行',
            sourceStart: 0,
            kind: TokenKind.matched,
            rawValue: 'hành/đi',
          ),
        ],
      ),
      readDraft: () => draft,
    );

    controller.choose(1);
    expect(draft.text, 'giữ nguyên');

    controller.choose(10);
    expect(draft.text, 'giữ nguyên');
    draft.dispose();
  });

  testWidgets('number shortcut invokes the choice controller', (tester) async {
    final draft = TextEditingController();
    final controller = MeaningChoiceController(
      readSelection: () => const TokenSelection(
        start: 0,
        end: 1,
        word: '行',
        origin: TokenSelectionOrigin.result,
      ),
      readTranslation: () => const TranslationState(
        mode: TranslationMode.japanese,
        sourceText: '行',
        tokens: [
          Token(
            source: '行',
            sourceStart: 0,
            kind: TokenKind.matched,
            rawValue: 'hành/đi',
          ),
        ],
      ),
      readDraft: () => draft,
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MeaningChoiceShortcuts(
          controller: controller,
          child: const Focus(autofocus: true, child: Text('kết quả')),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);

    expect(draft.text, 'đi');
    draft.dispose();
  });
}
