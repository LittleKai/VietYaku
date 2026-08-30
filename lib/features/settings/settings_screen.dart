import 'dart:io' show Directory, Platform;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/platform_features.dart';
import '../../core/tts_service.dart';
import '../../shared/widgets/feature_help_button.dart';
import '../../shared/widgets/settings_layout.dart';
import '../clipboard/application/clipboard_reader_controller.dart';
import '../dictionary_sync/application/dictionary_sync_controller.dart';
import '../glossary/data/glossary_service.dart';
import '../glossary/presentation/glossary_sync_screen.dart';
import '../repair/domain/jp_repair_pipeline.dart';
import '../repair/presentation/repair_screen.dart';
import '../translation/application/translation_controller.dart';
import '../translation/domain/translation_engine.dart';
import '../translation/domain/online_lookup_source.dart';
import '../translation/domain/translation_rule.dart';
import '../translation/presentation/translation_rule_tester_dialog.dart';
import '../update/application/update_controller.dart';
import '../update/presentation/update_dialog.dart';
import 'settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return SettingsPage(
      title: 'Cài đặt',
      description:
          'Cấu hình cách dịch, phát âm, sửa và đồng bộ dữ liệu từ điển.',
      tabs: [
        SettingsTab(
          label: 'Chung',
          icon: Icons.tune,
          accentColor: const Color(0xFF3949AB),
          children: [
            SettingsSection(
              icon: Icons.account_tree_outlined,
              accentColor: const Color(0xFF3949AB),
              title: 'Xử lý bản dịch',
              description:
                  'Các thay đổi được áp dụng ở lần bấm Dịch tiếp theo.',
              children: [
                SettingsControlRow(
                  title: 'Thuật toán dịch',
                  description:
                      'Chọn cách ưu tiên cụm từ khi quét toàn bộ văn bản.',
                  controlWidth: 500,
                  control: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<TranslationAlgorithm>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: TranslationAlgorithm.leftToRight,
                          label: Text('Trái → phải'),
                          tooltip:
                              'Quét trái sang phải, mỗi vị trí lấy cụm dài nhất',
                        ),
                        ButtonSegment(
                          value: TranslationAlgorithm.longestPhrase,
                          label: Text('Ưu tiên cụm dài'),
                          tooltip: 'Cụm dài nhất toàn văn bản được dịch trước',
                        ),
                        ButtonSegment(
                          value: TranslationAlgorithm.longestPhrase4,
                          label: Text('Cụm dài ≥ 4'),
                          tooltip:
                              'Chỉ cụm từ 4 ký tự trở lên được ưu tiên toàn văn',
                        ),
                      ],
                      selected: {settings.translationAlgorithm},
                      onSelectionChanged: (selection) =>
                          notifier.setTranslationAlgorithm(selection.first),
                    ),
                  ),
                ),
                SettingsSwitchRow(
                  title: 'Ưu tiên Names hơn VietPhrase',
                  description:
                      'Names tại một vị trí thắng cụm VietPhrase dài hơn. UserDict vẫn cao nhất.',
                  value: settings.prioritizeNames,
                  onChanged: notifier.setPrioritizeNames,
                ),
                SettingsControlRow(
                  title: 'Luật Nhân',
                  description:
                      'Mode Trung: chọn từ điển được phép lấp {0}; cụm dài hơn thắng, mục từ điển tĩnh thắng khi hòa.',
                  controlWidth: 430,
                  control: DropdownMenu<PersonRuleScope>(
                    expandedInsets: EdgeInsets.zero,
                    initialSelection: settings.personRuleScope,
                    onSelected: (value) {
                      if (value != null) notifier.setPersonRuleScope(value);
                    },
                    dropdownMenuEntries: const [
                      DropdownMenuEntry(
                        value: PersonRuleScope.off,
                        label: 'Tắt',
                      ),
                      DropdownMenuEntry(
                        value: PersonRuleScope.pronouns,
                        label: 'Pronouns',
                      ),
                      DropdownMenuEntry(
                        value: PersonRuleScope.pronounsAndNames,
                        label: 'Pronouns + Names',
                      ),
                      DropdownMenuEntry(
                        value: PersonRuleScope.pronounsNamesAndVietPhrase,
                        label: 'Pronouns + Names + VietPhrase',
                      ),
                    ],
                  ),
                ),
                SettingsSwitchRow(
                  title: 'Hậu xử lý bằng regex',
                  description:
                      'Áp tuần tự file rule theo ngôn ngữ trong tab Hậu xử lý.',
                  value: settings.postProcessingEnabled,
                  help: const FeatureHelpButton(
                    title: 'Hướng dẫn & Ví dụ Hậu xử lý',
                    summary:
                        'Tự động thay thế hoặc chuẩn hoá văn bản bằng bộ quy tắc regex sau khi dịch VietPhrase.',
                    accentColor: Color(0xFF6A1B9A),
                    points: [
                      'Khi bật, tab "Hậu xử lý" xuất hiện trên màn hình Dịch để xem kết quả sau khi áp dụng quy tắc.',
                      'Quy tắc áp dụng tuần tự từ trên xuống dưới trên bản dịch VietPhrase.',
                      'Thay thế tĩnh: "regex => thay_thế" hoặc "regex<TAB>thay_thế".\nVí dụ: "không có cái gì => không có gì".',
                      'Regex bắt nhóm: Dùng () để bắt nhóm, thế bằng \$1, \$2... \$9.\nVí dụ: "ngươi (\\w+) à => cậu \$1 phải không" (ngươi đi à → cậu đi phải không).',
                      'Phân nhóm & Ghi chú: Dùng [Tên nhóm] để nhóm quy tắc (bật/tắt theo nhóm) và # để viết comment.',
                      'Luật Nhân (mode Trung): Dùng mẫu {0} đại diện cho tên/đại từ động từ từ điển.\nVí dụ: "{0} đại nhân => ngài {0}" (Tiêu Viêm đại nhân → ngài Tiêu Viêm).',
                      'Có thể mở "Mở rule tester" bên dưới để xem danh sách, thử nghiệm hoặc chỉnh sửa quy tắc.',
                    ],
                  ),
                  onChanged: notifier.setPostProcessingEnabled,
                ),
                SettingsControlRow(
                  title: 'Quản lý và thử rule',
                  description:
                      'Soạn regex, xem lỗi và thử cả regex lẫn Luật Nhân trước khi dùng.',
                  controlWidth: 230,
                  control: FilledButton.tonalIcon(
                    onPressed: () =>
                        showTranslationRuleTesterDialog(context, ref),
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('Mở rule tester'),
                  ),
                ),
              ],
            ),
            if (Platform.isWindows)
              const SettingsSection(
                icon: Icons.content_paste_go_outlined,
                accentColor: Color(0xFF6A1B9A),
                title: 'Clipboard reader',
                description:
                    'Tự động nhận văn bản CJK từ ứng dụng khác và dịch mà không cần chuyển cửa sổ.',
                children: [_ClipboardReaderSetting()],
              ),
            const SettingsSection(
              icon: Icons.travel_explore_outlined,
              accentColor: Color(0xFF1565C0),
              title: 'Tra online',
              description:
                  'Nguồn chạy khi bấm "Tra online" ở tab Dịch. Kết quả hiện trong ô Nghĩa; chỉ nghĩa từ điển thật (Mazii, Jisho, Weblio, Youdao) mới lưu vào OnlineDict.',
              children: [_OnlineLookupSourcesSetting()],
            ),
            const SettingsSection(
              icon: Icons.cloud_sync_outlined,
              accentColor: Color(0xFF00838F),
              title: 'Từ điển chung',
              description:
                  'Kéo bản mới từ server; tự động đồng bộ hoặc cập nhật thủ công. Đăng nhập quản trị để xuất bản thay đổi.',
              children: [_DictionarySyncSettings()],
            ),
            const SettingsSection(
              icon: Icons.system_update_alt_outlined,
              accentColor: Color(0xFF0277BD),
              title: 'Cập nhật ứng dụng',
              description: 'Kiểm tra và tải bản mới từ GitHub Releases.',
              children: [_UpdateSettings()],
            ),
            const SettingsSection(
              icon: Icons.info_outline,
              accentColor: Color(0xFF00897B),
              title: 'Thông tin & Nguồn gốc',
              description:
                  'VietYaku được tham khảo từ QuickConverter của diễn đàn Tàng Thư Viện, cải tiến với thêm nhiều bộ từ điển, thuật toán và tích hợp thêm tiếng Nhật.',
              children: [
                SettingsControlRow(
                  title: 'Kế thừa & Cải tiến từ QuickConverter',
                  description:
                      'Ứng dụng được tham khảo từ công cụ QuickConverter (Tàng Thư Viện), kế thừa nguyên lý VietPhrase đồng thời nâng cấp nhiều thuật toán quét linh hoạt, bổ sung nhiều bộ từ điển phong phú và tích hợp dịch tiếng Nhật ngoại tuyến.',
                  controlWidth: 0,
                  control: SizedBox.shrink(),
                ),
              ],
            ),
          ],
        ),
        SettingsTab(
          label: 'Tiếng Nhật',
          icon: Icons.translate,
          accentColor: const Color(0xFFD81B60),
          children: [
            SettingsSection(
              icon: Icons.text_fields_outlined,
              accentColor: const Color(0xFF3949AB),
              title: 'Xử lý văn bản Nhật',
              description: 'Chỉ áp dụng khi đang dịch tiếng Nhật.',
              children: [
                SettingsSwitchRow(
                  title: 'Chuẩn hoá Katakana nửa hình',
                  description:
                      'Đổi ｱｲｳ và ｶﾞ thành アイウ và ガ trước khi tra từ điển.',
                  value: settings.normalizeHalfwidthKana,
                  onChanged: notifier.setNormalizeHalfwidthKana,
                ),
                SettingsSwitchRow(
                  title: 'Gộp số Kanji thành số Ả Rập',
                  description:
                      'Đổi run số chưa match như 三百二十五 thành 325; cụm đã match giữ nguyên.',
                  value: settings.joinKanjiNumerals,
                  onChanged: notifier.setJoinKanjiNumerals,
                ),
                SettingsSwitchRow(
                  title: 'Dùng từ điển biến thể Sudachi',
                  description:
                      'Tra biến thể Okurigana như 打込む → 打ち込む. Đổi lựa chọn sẽ nạp lại từ điển.',
                  value: settings.sudachiVariants,
                  onChanged: notifier.setSudachiVariants,
                ),
                SettingsControlRow(
                  title: 'Nguồn phát âm Kana',
                  description: 'Chọn thứ tự ưu tiên phát âm trong ô Nghĩa.',
                  controlWidth: 430,
                  control: DropdownMenu<SudachiReadingsMode>(
                    expandedInsets: EdgeInsets.zero,
                    initialSelection: settings.sudachiReadings,
                    onSelected: (value) {
                      if (value != null) notifier.setSudachiReadings(value);
                    },
                    dropdownMenuEntries: const [
                      DropdownMenuEntry(
                        value: SudachiReadingsMode.sudachiFirst,
                        label: 'Ưu tiên SudachiDict',
                      ),
                      DropdownMenuEntry(
                        value: SudachiReadingsMode.jaViFirst,
                        label: 'Ưu tiên Nhật Việt / Lạc Việt',
                      ),
                      DropdownMenuEntry(
                        value: SudachiReadingsMode.disabled,
                        label: 'Không dùng SudachiDict',
                      ),
                    ],
                  ),
                ),
                SettingsControlRow(
                  title: 'Đánh dấu cụm từ điển phụ',
                  description:
                      'Cụm kana chỉ có trong Lạc Việt / Nhật Việt / Mazii (không có trong VietPhrase) hiện thế nào trong ô VietPhrase.',
                  controlWidth: 430,
                  control: DropdownMenu<SecondaryPhraseDisplay>(
                    expandedInsets: EdgeInsets.zero,
                    initialSelection: settings.secondaryPhraseDisplay,
                    onSelected: (value) {
                      if (value != null) {
                        notifier.setSecondaryPhraseDisplay(value);
                      }
                    },
                    dropdownMenuEntries: const [
                      DropdownMenuEntry(
                        value: SecondaryPhraseDisplay.off,
                        label: 'Tắt',
                      ),
                      DropdownMenuEntry(
                        value: SecondaryPhraseDisplay.tight,
                        label: 'Sát khoảng cách',
                      ),
                      DropdownMenuEntry(
                        value: SecondaryPhraseDisplay.italic,
                        label: 'In nghiêng',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SettingsSection(
              icon: Icons.open_in_new_outlined,
              accentColor: Color(0xFF7B1FA2),
              title: 'Popup tra nhanh Nhật',
              description:
                  'Hiện nghĩa khi active một cụm trong ô Nguồn ở mode Nhật; chọn tối đa 1 từ điển.',
              children: [
                _PopupDictionarySetting(mode: TranslationMode.japanese),
              ],
            ),
            const SettingsSection(
              icon: Icons.volume_up_outlined,
              accentColor: Color(0xFF00897B),
              title: 'Phát âm',
              description: 'Giọng đọc và tốc độ đọc dùng cho tiếng Nhật.',
              children: [
                _TtsSpeedSetting(mode: TranslationMode.japanese),
                _TtsVoiceSetting(mode: TranslationMode.japanese),
              ],
            ),
            if (PlatformFeatures.dictionaryRepair)
              SettingsSection(
                icon: Icons.handyman_outlined,
                accentColor: const Color(0xFFEF6C00),
                title: 'Sửa từ điển',
                description:
                    'Sửa key thuần Hán, xuất file _JP.txt và nạp kết quả vào ứng dụng.',
                children: [
                  SettingsControlRow(
                    title: 'Chính sách key thuần Hán',
                    description:
                        'Quyết định cách xử lý biến thể khi chạy công cụ sửa từ điển.',
                    controlWidth: 500,
                    control: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<RepairPolicy>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: RepairPolicy.addVariant,
                            label: Text('Giữ gốc + thêm JP'),
                          ),
                          ButtonSegment(
                            value: RepairPolicy.convert,
                            label: Text('Convert hết'),
                          ),
                          ButtonSegment(
                            value: RepairPolicy.keepOnly,
                            label: Text('Không convert'),
                          ),
                        ],
                        selected: {settings.repairPolicy},
                        onSelectionChanged: (selection) =>
                            notifier.setRepairPolicy(selection.first),
                      ),
                    ),
                  ),
                  const RepairScreen(showHeader: false),
                ],
              ),
          ],
        ),
        SettingsTab(
          label: 'Tiếng Trung',
          icon: Icons.language,
          accentColor: const Color(0xFFEF6C00),
          children: [
            SettingsSection(
              icon: Icons.text_fields_outlined,
              accentColor: const Color(0xFF3949AB),
              title: 'Xử lý văn bản Trung',
              description: 'Chỉ áp dụng khi đang dịch tiếng Trung.',
              children: [
                SettingsSwitchRow(
                  title: 'Quy phồn thể về giản thể trước khi tra',
                  description:
                      'Bộ từ điển Trung là giản thể nên 時間 phải tra thành 时间. Ô Nguồn vẫn giữ nguyên chữ phồn thể đã dán vào.',
                  value: settings.convertTraditionalToSimplified,
                  onChanged: notifier.setConvertTraditionalToSimplified,
                ),
              ],
            ),
            const SettingsSection(
              icon: Icons.open_in_new_outlined,
              accentColor: Color(0xFF7B1FA2),
              title: 'Popup tra nhanh Trung',
              description:
                  'Hiện nghĩa khi active một cụm trong ô Nguồn ở mode Trung; chọn tối đa 1 từ điển.',
              children: [
                _PopupDictionarySetting(mode: TranslationMode.chinese),
              ],
            ),
            const SettingsSection(
              icon: Icons.volume_up_outlined,
              accentColor: Color(0xFF00897B),
              title: 'Phát âm',
              description: 'Giọng đọc và tốc độ đọc dùng cho tiếng Trung.',
              children: [
                _TtsSpeedSetting(mode: TranslationMode.chinese),
                _TtsVoiceSetting(mode: TranslationMode.chinese),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _ClipboardReaderSetting extends ConsumerWidget {
  const _ClipboardReaderSetting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(
      settingsProvider.select((settings) => settings.clipboardReaderEnabled),
    );
    final status = ref.watch(clipboardReaderControllerProvider);
    final detail = status.lastMessage == null
        ? 'Chỉ nhận nội dung có chữ Hán/Kana; chống lặp và bỏ qua clipboard do VietYaku tự ghi. Hotkey toàn hệ thống: Ctrl+Shift+V.'
        : 'Ctrl+Shift+V · ${status.lastMessage}';
    return SettingsSwitchRow(
      title: 'Theo dõi clipboard + global hotkey',
      description: detail,
      value: enabled,
      help: const FeatureHelpButton(
        title: 'Clipboard reader + global hotkey',
        summary:
            'Đọc nhanh văn bản Nhật/Trung từ ứng dụng khác mà không cần Alt+Tab.',
        accentColor: Color(0xFF6A1B9A),
        points: [
          'Chỉ nhận clipboard có chữ Hán hoặc Kana; nội dung Latin/Việt thuần sẽ bị bỏ qua.',
          'Debounce và hash chống xử lý lặp; clipboard do chính VietYaku ghi được bỏ qua.',
          'Ctrl+Shift+V hoạt động toàn hệ thống: đọc clipboard, dịch và đưa VietYaku lên trước.',
          'Có thể kết hợp PowerToys Text Extractor: OCR vào clipboard rồi để VietYaku tự nhận.',
        ],
      ),
      onChanged: ref.read(settingsProvider.notifier).setClipboardReaderEnabled,
    );
  }
}

class _PopupDictionarySetting extends ConsumerWidget {
  const _PopupDictionarySetting({required this.mode});

  final TranslationMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(
      settingsProvider.select(
        (settings) => settings.popupDictionaryTypesFor(mode),
      ),
    );
    final available = availablePopupDictionariesFor(mode);
    final label = mode == TranslationMode.japanese
        ? 'tiếng Nhật'
        : 'tiếng Trung';
    final defaultDesc = mode == TranslationMode.chinese
        ? 'Chỉ chọn được 1 từ điển. Mặc định là Lạc Việt.'
        : 'Chỉ chọn được 1 từ điển. Mặc định không chọn (tắt popup).';
    return SettingsControlRow(
      title: 'Từ điển trong popup ($label)',
      description: defaultDesc,
      controlWidth: 540,
      control: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          for (final type in available)
            FilterChip(
              label: Text(type.label),
              selected: selected.contains(type),
              // Single-select: chọn cái mới thay cái cũ, bỏ chọn → tắt popup.
              onSelected: (enabled) {
                ref
                    .read(settingsProvider.notifier)
                    .setPopupDictionaryTypes(mode, enabled ? [type] : const []);
              },
            ),
        ],
      ),
    );
  }
}

class _OnlineLookupSourcesSetting extends ConsumerWidget {
  const _OnlineLookupSourcesSetting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(
      settingsProvider.select((settings) => settings.onlineLookupSources),
    );
    return SettingsControlRow(
      title: 'Nguồn tra online',
      description:
          'Bỏ chọn hết = tắt tra online. Nguồn nào không hợp với ngôn ngữ đang '
          'dịch sẽ tự bỏ qua.',
      controlWidth: 540,
      control: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          for (final source in OnlineLookupSource.values)
            FilterChip(
              label: Text(source.label),
              tooltip: source.hint,
              selected: selected.contains(source),
              onSelected: (enabled) {
                final next = selected.toSet();
                if (enabled) {
                  next.add(source);
                } else {
                  next.remove(source);
                }
                ref
                    .read(settingsProvider.notifier)
                    .setOnlineLookupSources(next);
              },
            ),
        ],
      ),
    );
  }
}

class _TtsSpeedSetting extends ConsumerWidget {
  const _TtsSpeedSetting({required this.mode});

  final TranslationMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rate = ref.watch(
      settingsProvider.select((value) => value.ttsSpeechRateFor(mode)),
    );
    final notifier = ref.read(settingsProvider.notifier);
    final ratePct = (rate * 100).round();
    final label = mode == TranslationMode.japanese
        ? 'tiếng Nhật'
        : 'tiếng Trung';

    return SettingsControlRow(
      title: 'Tốc độ đọc ($label)',
      description: 'Áp dụng cho giọng $label.',
      controlWidth: 430,
      control: Row(
        children: [
          Expanded(
            child: Slider(
              value: rate,
              min: 0.1,
              max: 1.0,
              divisions: 18,
              label: '$ratePct%',
              onChanged: (v) => notifier.setTtsSpeechRate(mode, v),
            ),
          ),
          SettingsValueBadge(label: '$ratePct%', width: 56),
        ],
      ),
    );
  }
}

class _TtsVoiceSetting extends ConsumerWidget {
  const _TtsVoiceSetting({required this.mode});

  final TranslationMode mode;

  static const _samples = <TranslationMode, String>{
    TranslationMode.japanese: 'こんにちは',
    TranslationMode.chinese: '你好',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final tts = ref.watch(ttsServiceProvider).valueOrNull;
    final label = mode == TranslationMode.japanese
        ? 'Tiếng Nhật'
        : 'Tiếng Trung';
    final voices = tts?.voicesFor(mode) ?? const <Map<String, String>>[];
    final available = tts?.availableFor(mode) ?? false;

    if (!available || voices.isEmpty) {
      return SettingsControlRow(
        title: 'Giọng $label',
        description: 'Chưa có giọng ${TtsService.languageFor(mode)} trên máy.',
        controlWidth: 220,
        control: Text(
          'Không khả dụng',
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final current = settings.ttsVoiceFor(mode);
    final entries = <DropdownMenuEntry<String>>[
      const DropdownMenuEntry(value: '', label: 'Tự động'),
      for (final voice in voices)
        DropdownMenuEntry(
          value: TtsService.voiceKeyOf(voice),
          label: voice['name'] ?? '',
        ),
    ];
    final initial = entries.any((entry) => entry.value == current)
        ? current
        : '';

    return SettingsControlRow(
      title: 'Giọng $label',
      description: 'Chọn giọng hệ thống hoặc để ứng dụng tự động chọn.',
      controlWidth: 430,
      control: Row(
        children: [
          Expanded(
            child: DropdownMenu<String>(
              key: ValueKey('tts:${mode.name}:$initial'),
              initialSelection: initial,
              expandedInsets: EdgeInsets.zero,
              onSelected: (value) => ref
                  .read(settingsProvider.notifier)
                  .setTtsVoice(mode, value ?? ''),
              dropdownMenuEntries: entries,
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            icon: const Icon(Icons.volume_up),
            tooltip: 'Nghe thử $label',
            onPressed: () => tts!.speak(
              _samples[mode]!,
              mode,
              voiceKey: settings.ttsVoiceFor(mode),
              rate: settings.ttsSpeechRateFor(mode),
            ),
          ),
        ],
      ),
    );
  }
}

class _DictionarySyncSettings extends ConsumerStatefulWidget {
  const _DictionarySyncSettings();

  @override
  ConsumerState<_DictionarySyncSettings> createState() =>
      _DictionarySyncSettingsState();
}

class _DictionarySyncSettingsState
    extends ConsumerState<_DictionarySyncSettings> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final url = ref.read(settingsProvider).syncServerUrl;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      _showMessage('Hãy nhập tài khoản và mật khẩu.');
      return;
    }

    try {
      await ref
          .read(dictionarySyncProvider.notifier)
          .login(serverUrl: url, username: username, password: password);
      _passwordController.clear();
      _showMessage('Đã đăng nhập quản trị.');
    } catch (_) {
      if (!mounted) return;
      _showMessage(
        ref.read(dictionarySyncProvider).message ?? 'Không thể đăng nhập.',
      );
    }
  }

  Future<void> _publishPending() async {
    try {
      await ref.read(dictionarySyncProvider.notifier).publishPending();
    } catch (_) {
      // Controller đã ánh xạ lỗi kỹ thuật sang thông báo UI.
    }
    if (!mounted) return;
    _showMessage(
      ref.read(dictionarySyncProvider).message ?? 'Không thể Update server.',
    );
  }

  Future<void> _syncNow() async {
    final mode = ref.read(translationControllerProvider).mode;
    try {
      await ref.read(dictionarySyncProvider.notifier).sync(mode);
    } catch (_) {
      // Controller đã ánh xạ lỗi kỹ thuật sang thông báo UI.
    }
    if (!mounted) return;
    _showMessage(
      ref.read(dictionarySyncProvider).message ?? 'Không thể cập nhật từ điển.',
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(dictionarySyncProvider);
    final session = sync.session;
    final autoSync = ref.watch(
      settingsProvider.select((s) => s.autoSyncDictionary),
    );

    return Column(
      children: [
        SettingsSwitchRow(
          title: 'Tự động đồng bộ khi mở app',
          description:
              'Kéo bản từ điển chung mới nhất từ server mỗi lần khởi động. Mặc định tắt.',
          value: autoSync,
          onChanged: (value) =>
              ref.read(settingsProvider.notifier).setAutoSyncDictionary(value),
        ),
        SettingsControlRow(
          title: 'Cập nhật từ điển',
          description:
              'Kéo thủ công bản mới nhất của ngôn ngữ đang chọn từ server.',
          controlWidth: 210,
          control: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              icon: sync.isSyncing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: const Text('Cập nhật từ điển'),
              onPressed: sync.isSyncing ? null : _syncNow,
            ),
          ),
        ),
        SettingsControlRow(
          title: 'Tài khoản quản trị',
          description: sync.isAdmin
              ? 'Phiên được lưu trên máy. Sửa cục bộ trước, chỉ gửi lên server khi bấm Update.'
              : 'Chỉ cần đăng nhập khi muốn xuất bản thay đổi chung.',
          controlWidth: 650,
          control: session != null
              ? Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(session.username),
                    FilledButton.tonalIcon(
                      icon: sync.isPublishing
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: const Text('Update'),
                      onPressed: sync.isPublishing ? null : _publishPending,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text('Đăng xuất'),
                      onPressed: () =>
                          ref.read(dictionarySyncProvider.notifier).logout(),
                    ),
                  ],
                )
              : Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 190,
                      child: TextField(
                        controller: _usernameController,
                        enabled: !sync.isLoggingIn,
                        decoration: const InputDecoration(
                          labelText: 'Tài khoản',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 190,
                      child: TextField(
                        controller: _passwordController,
                        enabled: !sync.isLoggingIn,
                        obscureText: true,
                        onSubmitted: (_) => _login(),
                        decoration: const InputDecoration(
                          labelText: 'Mật khẩu',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      icon: sync.isLoggingIn
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login, size: 18),
                      label: const Text('Đăng nhập'),
                      onPressed: sync.isLoggingIn ? null : _login,
                    ),
                  ],
                ),
        ),
        // Glossary nằm trong thư mục dự án AI_Translation_Bridge trên máy
        // Windows — trên mobile không có gì để trỏ tới.
        if (sync.isAdmin && PlatformFeatures.glossarySync) ...[
          const _GlossaryDirSetting(),
          const _GlossarySyncSetting(),
        ],
      ],
    );
  }
}

/// Chọn thư mục `Glossary/` của AI_Translation_Bridge. Trỏ đúng chỗ thì dialog
/// sửa VietPhrase có thêm nút đẩy từ sang `Global Glossary.json` JP/CN.
class _GlossaryDirSetting extends ConsumerWidget {
  const _GlossaryDirSetting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dir = ref.watch(settingsProvider.select((s) => s.glossaryDir));
    final service = GlossaryService(dir);
    final found = TranslationMode.values
        .where(service.hasGlossaryFor)
        .map(GlossaryService.langFor)
        .join(', ');

    return SettingsControlRow(
      title: 'Thư mục Glossary',
      description: dir.trim().isEmpty
          ? 'Chưa chọn thư mục.'
          : found.isEmpty
          ? 'Không thấy "Global Glossary.json" trong $dir\\JP hoặc $dir\\CN.'
          : 'Đã thấy Global Glossary: $found. Dialog sửa VietPhrase sẽ có nút cập nhật glossary.',
      controlWidth: 650,
      control: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(
            found.isEmpty ? Icons.error_outline : Icons.check_circle_outline,
            size: 20,
            color: found.isEmpty
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Tooltip(
              message: dir.isEmpty ? 'Chưa chọn' : dir,
              child: Text(
                dir.isEmpty ? 'Chưa chọn' : dir,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('Chọn thư mục'),
            onPressed: () async {
              final picked = await getDirectoryPath(
                initialDirectory: Directory(dir).existsSync() ? dir : null,
              );
              if (picked == null) return;
              await ref.read(settingsProvider.notifier).setGlossaryDir(picked);
            },
          ),
        ],
      ),
    );
  }
}

/// Mở màn đồng bộ hàng loạt Glossary ↔ VietPhrase.
class _GlossarySyncSetting extends ConsumerWidget {
  const _GlossarySyncSetting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dir = ref.watch(settingsProvider.select((s) => s.glossaryDir));
    final mode = ref.watch(
      translationControllerProvider.select((state) => state.mode),
    );
    final ready = GlossaryService(dir).hasGlossaryFor(mode);

    return SettingsControlRow(
      title: 'Đồng bộ Glossary ↔ VietPhrase',
      description: ready
          ? 'So sánh hai bên theo từng chiều, lọc trùng/không trùng và created_by, tick chọn rồi cập nhật hàng loạt.'
          : 'Cần chọn đúng thư mục Glossary có "Global Glossary.json" của ngôn ngữ đang dịch.',
      controlWidth: 210,
      control: Align(
        alignment: Alignment.centerRight,
        child: FilledButton.tonalIcon(
          icon: const Icon(Icons.sync_alt),
          label: const Text('Mở màn đồng bộ'),
          onPressed: ready
              ? () => Navigator.of(context).push(GlossarySyncScreen.route())
              : null,
        ),
      ),
    );
  }
}

class _UpdateSettings extends ConsumerStatefulWidget {
  const _UpdateSettings();

  @override
  ConsumerState<_UpdateSettings> createState() => _UpdateSettingsState();
}

class _UpdateSettingsState extends ConsumerState<_UpdateSettings> {
  String _currentVersion = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _currentVersion = info.version);
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _checkNow() async {
    await ref.read(updateControllerProvider.notifier).checkForUpdate();
    if (!mounted) return;
    final state = ref.read(updateControllerProvider);
    switch (state.phase) {
      case UpdatePhase.available:
        maybeShowUpdateDialog(context, ref);
      case UpdatePhase.upToDate:
        _showMessage(state.message ?? 'Bạn đang dùng bản mới nhất.');
      case UpdatePhase.error:
        _showMessage(state.message ?? 'Kiểm tra cập nhật thất bại.');
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final checking =
        ref.watch(updateControllerProvider.select((s) => s.phase)) ==
        UpdatePhase.checking;

    return Column(
      children: [
        SettingsSwitchRow(
          title: 'Tự động kiểm tra cập nhật',
          description: 'Kiểm tra bản mới mỗi khi khởi động ứng dụng.',
          value: settings.autoCheckUpdates,
          onChanged: (value) =>
              ref.read(settingsProvider.notifier).setAutoCheckUpdates(value),
        ),
        SettingsControlRow(
          title: 'Kiểm tra cập nhật',
          description: _currentVersion.isEmpty
              ? 'Đang đọc phiên bản hiện tại...'
              : 'Phiên bản hiện tại: $_currentVersion',
          controlWidth: 210,
          control: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              icon: checking
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.system_update_alt_outlined),
              label: const Text('Kiểm tra ngay'),
              onPressed: checking ? null : _checkNow,
            ),
          ),
        ),
      ],
    );
  }
}
