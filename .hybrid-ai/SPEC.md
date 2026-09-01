# Japanese Dynamic Orthographic Variants

## Goal

Make Japanese entries added through `UserDict`, `UserNames`, and shared
VietPhrase/LacViet overlays automatically match safe kanji/kana spelling
variants without duplicating meanings. Keep the existing greedy engine and
dictionary value bytes unchanged.

Required examples:

- Canonical `吞み込ま=nuốt chửng` must also recognize `吞みこま` and the
  lexical prefix `のみこま` in `のみこまれ`.
- Canonical `扱いきれ=xử lý được` must also recognize `扱い切れ` and
  `あつかいきれ`.

## Context / Constraints

- Flutter/Dart app; domain logic must stay pure Dart.
- Translation dictionaries remain `HashMap<String, String>` plus
  `maxLenByFirstUnit`; do not introduce a trie, database, runtime Java, MeCab,
  or a network dependency.
- Existing `data/jp/SudachiVariants.txt` is build-time and tied to bundled
  VietPhrase values. It cannot cover entries added later to User/Shared files.
- Existing explicit entries must beat generated aliases. Generated aliases
  must never overwrite an explicit key.
- Alias values must be copied byte-for-byte from their source entry.
- Japanese-only behavior, controlled by the existing `sudachiVariants`
  setting. Chinese mode must not load or apply this asset.
- Preserve the unrelated current edits in
  `.claude/skills/build-and-release/scripts/release.ps1` and
  `.claude/skills/build-and-release/scripts/upload-b2.ps1`.

## Context Pack

### Existing load path

`lib/features/dictionary/data/dictionary_repository.dart` exposes:

```dart
Future<LoadedDictionaries> loadAll(
  Map<DictType, String> dictPaths, {
  required TranslationMode mode,
  bool useSudachiVariants = true,
  Trad2SimpTable? trad2simp,
})
```

It loads these overlay slots:

```dart
() => loadPath(DictType.names, userNamesPath),
() => loadPath(DictType.vietPhrase, sharedVietPhrasePath(mode)),
() => loadPath(DictType.lacViet, sharedLacVietPath(mode)),
() => useSudachiVariants
    ? loadPath(DictType.vietPhrase, sudachiPath('SudachiVariants.txt'))
    : emptyResult(DictType.vietPhrase),
```

The bundle merge currently places `SudachiVariants` below bundled
VietPhrase, then shared VietPhrase on top:

```dart
vietPhrase = PhraseDictionary(DictType.vietPhrase, {
  ...sudachiVariants.entries,
  ...vietPhrase.entries,
  ...sharedVietPhrase.entries,
});
```

### Dictionary invariant

`lib/features/dictionary/domain/phrase_dictionary.dart` stores:

```dart
final Map<String, String> entries;
final Map<int, int> maxLenByFirstUnit;
```

Keep this representation. Alias expansion must return an ordinary map that
is passed to `PhraseDictionary`; do not change `TranslationEngine` lookup.

### Sudachi raw fields already used

`tool/build_sudachi_assets.dart` parses RFC-4180 rows with `_parseCsvLine`.
Relevant fields are copied from the real source:

- `fields[0]`: surface
- `fields[5]..fields[10]`: POS and conjugation identity
- `fields[11]`: katakana reading
- `fields[12]`: normalized/dictionary form

Rows such as `吞みこま` and `のみこま` share reading `ノミコマ`, normalized
form `飲み込む`, POS `動詞`, conjugation type `五段-マ行`, and conjugation
form `未然形-一般`. Those fields form one safe orthographic group.

### Applicable conventions

- New Dart files use `snake_case.dart`; tests are `test/<object>_test.dart`.
- Imports: `dart:` then `package:` then relative imports.
- Public domain class/function gets a short Vietnamese `///` comment that
  explains the safety invariant.
- Use UTF-16 code-unit offsets and `runeLengthAt` for advancing a rune.
- Generated text assets use UTF-8 BOM + CRLF and deterministic sorting.
- Run `dart format`, `flutter analyze`, and `flutter test` before completion.

## Clarified Decisions / Assumptions

- “Recognize `のみこまれ`” means the generated lexical alias `のみこま`
  matches its prefix and receives the canonical meaning. The grammatical
  suffix `れ` remains a separate token; this feature must not erase passive,
  negative, tense, or connective suffixes blindly.
- Dynamic expansion is required for overlays that can change after shipping:
  UserDict, UserNames, shared VietPhrase, and shared LacViet.
- Bundled VietPhrase continues using the existing precomputed
  `SudachiVariants.txt` to avoid expanding ~187k entries at startup.
- Pure-hiragana aliases shorter than 4 UTF-16 code units are forbidden. This
  preserves the existing safety lesson that short hiragana can be grammar
  (`し`, `く`, `くれ`) rather than a lexical spelling variant.
- Each source entry may produce at most 64 aliases. Prefer longer surface
  segments and stop deterministically at the cap.

## No-Placeholder Contract

This phase must ship working behavior. Do not leave TODO-only code, empty
functions/classes, mocks, fake data, disconnected loaders, or unused assets.

## Deferred Work

- Translating Japanese grammatical suffixes such as `れ`, `ずに`, `た`, or
  `ない` is out of scope. This feature only normalizes the lexical spelling.
- Runtime morphological lattice/Viterbi disambiguation is out of scope.

## Steps

### 1. Add failing domain tests

**Files:** `test/japanese_variant_index_test.dart` (new)

**Location anchor:** new file.

**Action:** Define small in-memory variant groups and test a pure domain API
that expands explicit maps. Required assertions:

- `吞み込ま` generates `吞みこま` and `のみこま`, preserving
  `nuốt chửng` exactly.
- `扱いきれ` is segmented into the groups for `扱い` and `きれ`, generating
  `扱い切れ` and `あつかいきれ` with `xử lý được`.
- An explicit alias value wins over a generated value.
- A pure-hiragana alias shorter than 5 code units is rejected.
- Expansion stops at 64 aliases.

**Do NOT:** Test by reading the 100+ MB real dictionaries. Keep this unit test
small and deterministic.

**Verify:**

```powershell
& 'D:\3.Flutter\flutter\bin\flutter.bat' test test/japanese_variant_index_test.dart
```

Expected before implementation: compile/test failure because the API is
missing. Expected after Step 2: all tests pass.

### 2. Implement the pure variant index

**Files:**

- `lib/features/dictionary/domain/japanese_variant_index.dart` (new)
- `test/japanese_variant_index_test.dart`

**Location anchor:** new domain class.

**Action:** Implement `JapaneseVariantIndex` from a list of variant groups.
Index every surface to one or more group IDs and build a
`maxLenByFirstUnit`-style prefix bound. Expose:

```dart
Map<String, String> expandEntries(
  Map<String, String> explicitEntries, {
  int maxAliasesPerEntry = 64,
})
```

Use a bounded DFS/DP segmentation. A recognized group surface is a segment;
unmatched kana may advance as a literal rune; unmatched Han invalidates that
parse. Generate cross-products deterministically, add aliases first, then
overlay `explicitEntries` last. Reject an alias if it equals the source key,
contains no Han and has length `< 4`, or exceeds the per-entry cap.

**Code for the hard parts:** Prefix probing must mirror the existing
`PhraseDictionary` pattern: for a position, get max length by first code unit,
try longer substrings first, and look them up in `groupIdsBySurface`. Advance
literal text with `runeLengthAt`, never `index + 1`.

**Do NOT:** Import Flutter, change `PhraseDictionary`, or change
`TranslationEngine`.

**Verify:** Run the focused test from Step 1; all cases pass.

### 3. Generate the universal orthographic group asset

**Files:**

- `tool/build_sudachi_assets.dart`
- `data/jp/SudachiVariantGroups.txt` (generated)
- `test/sudachi_data_test.dart`

**Location anchor:** the lexicon scan and output section in
`build_sudachi_assets.dart`.

**Action:** While scanning Sudachi rows, group distinct surfaces by the exact
signature:

```text
normalized + reading + fields[5..10]
```

Retain only groups with at least two distinct surfaces, at least one
Han-containing surface, and surfaces of at least two UTF-16 code units.
Write one deterministic tab-separated line per group:

```text
surface1\tsurface2\tsurface3
```

Sort surfaces inside each group and sort final lines lexicographically. Write
UTF-8 BOM + CRLF. Add real-data validation that every non-empty line has at
least two unique fields and no field is empty.

**Do NOT:** Put meanings in this file, remove existing
`SudachiVariants.txt`, or alter its current semantics.

**Verify:**

```powershell
& 'D:\3.Flutter\flutter\bin\dart.bat' run tool/build_sudachi_assets.dart
& 'D:\3.Flutter\flutter\bin\flutter.bat' test test/sudachi_data_test.dart
```

Expected: all three Sudachi assets are written and the validation passes.

### 4. Parse and integrate dynamic overlay expansion

**Files:**

- `lib/features/dictionary/data/dictionary_repository.dart`
- `test/dictionary_repository_variant_test.dart` (new)

**Location anchor:** `DictionaryRepository.loadAll`, immediately after the
parallel `results` are available and before overlay merges.

**Action:** In Japanese mode with `useSudachiVariants == true`, read
`SudachiVariantGroups.txt`, parse tab-separated groups, create
`JapaneseVariantIndex`, and expand only:

- `results[0].dictionary` (UserDict)
- `results[12].dictionary` (UserNames overlay)
- `results[13].dictionary` (shared VietPhrase)
- `results[14].dictionary` (shared LacViet)

Use the expanded dictionaries in engine merges and corresponding search
layers. Do not expand bundled dictionaries. Missing/malformed group asset must
degrade to no dynamic aliases, matching current behavior.

Keep overlay precedence exactly:

```text
UserDict > Names > Shared VietPhrase > bundled VietPhrase > static Sudachi aliases
```

Add a repository-level temp-directory test with tiny dictionary fixtures and
a tiny group file. Prove Japanese + enabled expands the two examples, while
Japanese + disabled and Chinese mode do not.

**Do NOT:** Add a new setting, reload dependency, cache format, or network
call. Do not include `OnlineDict`; online saved results are lookup cache, not
translation vocabulary.

**Verify:** Run the new repository test and existing `test/engine_test.dart`.

### 5. Documentation and final validation

**Files:**

- `.claude/PROJECT_SUMMARY.md`
- `.hybrid-ai/BUILDER_LOG.md`

**Location anchor:** Sudachi assets/file structure, data flow, active feature
status, and current test count.

**Action:** Document dynamic overlay alias expansion, its safety filters, and
the fact that grammatical suffixes remain separate. Append a Builder log entry
without changing previous entries.

**Do NOT:** Add a changelog narrative to `PROJECT_SUMMARY.md`.

**Verify:** Documentation describes current state only and names the exact new
asset/API.

## Validation Plan

Preflight:

```powershell
git status --short
& 'D:\3.Flutter\flutter\bin\flutter.bat' test test/sudachi_data_test.dart
```

Focused:

```powershell
& 'D:\3.Flutter\flutter\bin\flutter.bat' test test/japanese_variant_index_test.dart test/dictionary_repository_variant_test.dart test/engine_test.dart test/sudachi_data_test.dart
```

Final:

```powershell
& 'D:\3.Flutter\flutter\bin\dart.bat' format lib/features/dictionary/domain/japanese_variant_index.dart lib/features/dictionary/data/dictionary_repository.dart test/japanese_variant_index_test.dart test/dictionary_repository_variant_test.dart test/sudachi_data_test.dart tool/build_sudachi_assets.dart
& 'D:\3.Flutter\flutter\bin\flutter.bat' analyze --no-pub
& 'D:\3.Flutter\flutter\bin\flutter.bat' test --no-pub
rg -n "TODO|stub|mock|placeholder|NotImplemented" lib/features/dictionary/domain/japanese_variant_index.dart lib/features/dictionary/data/dictionary_repository.dart test/japanese_variant_index_test.dart test/dictionary_repository_variant_test.dart tool/build_sudachi_assets.dart
```

Expected: analyze clean, full suite passes, and placeholder scan finds no new
implementation placeholders.
