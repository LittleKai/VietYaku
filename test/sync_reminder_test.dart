import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietyaku/features/dictionary_sync/application/dictionary_sync_controller.dart';
import 'package:vietyaku/features/dictionary_sync/domain/sync_reminder.dart';
import 'package:vietyaku/features/settings/settings_provider.dart';

void main() {
  final now = DateTime(2026, 9, 1, 10);

  group('SyncReminder', () {
    test('chu kỳ nhỏ hơn 2 tuần bị nâng lên 14 ngày', () {
      expect(SyncReminder.normalizeIntervalDays(1), 14);
      expect(SyncReminder.normalizeIntervalDays(13), 14);
      expect(SyncReminder.normalizeIntervalDays(14), 14);
      expect(SyncReminder.normalizeIntervalDays(30), 30);
      expect(SyncReminder.normalizeIntervalDays(0), 0);
      expect(SyncReminder.normalizeIntervalDays(-5), 0);
    });

    test('tới hạn đúng theo chu kỳ', () {
      bool due(DateTime baseline, {int days = 30}) => SyncReminder.isDue(
        intervalDays: days,
        baseline: baseline,
        now: now,
      );

      expect(due(now.subtract(const Duration(days: 29, hours: 23))), isFalse);
      expect(due(now.subtract(const Duration(days: 30))), isTrue);
      expect(due(now.subtract(const Duration(days: 400))), isTrue);
      // Chu kỳ dưới mức tối thiểu vẫn phải đợi đủ 14 ngày.
      expect(due(now.subtract(const Duration(days: 10)), days: 3), isFalse);
      expect(due(now.subtract(const Duration(days: 14)), days: 3), isTrue);
    });

    test('tắt nhắc, chưa có mốc, hoặc mốc ở tương lai đều không nhắc', () {
      expect(
        SyncReminder.isDue(
          intervalDays: 0,
          baseline: now.subtract(const Duration(days: 999)),
          now: now,
        ),
        isFalse,
      );
      expect(
        SyncReminder.isDue(intervalDays: 30, baseline: null, now: now),
        isFalse,
      );
      expect(
        SyncReminder.isDue(
          intervalDays: 30,
          baseline: now.add(const Duration(days: 1)),
          now: now,
        ),
        isFalse,
      );
    });
  });

  group('DictionarySyncController — nhắc cập nhật', () {
    Future<ProviderContainer> containerWith(
      Map<String, Object> values,
    ) async {
      SharedPreferences.setMockInitialValues(values);
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('lần chạy đầu chỉ ghi mốc, không nhắc', () async {
      final container = await containerWith({});
      final notifier = container.read(dictionarySyncProvider.notifier);

      expect(notifier.reminderBaseline(), isNull);
      expect(await notifier.isReminderDue(now: now), isFalse);
      expect(notifier.reminderBaseline(), now);
      // Mốc đã có: một tháng sau mới tới hạn.
      expect(
        await notifier.isReminderDue(now: now.add(const Duration(days: 29))),
        isFalse,
      );
      expect(
        await notifier.isReminderDue(now: now.add(const Duration(days: 30))),
        isTrue,
      );
    });

    test('trả lời hộp thoại đẩy mốc lên, không hỏi lại ngay', () async {
      final container = await containerWith({
        'dictionarySync.reminderBaseline': now
            .subtract(const Duration(days: 45))
            .millisecondsSinceEpoch,
      });
      final notifier = container.read(dictionarySyncProvider.notifier);

      expect(await notifier.isReminderDue(now: now), isTrue);
      await notifier.markReminderPrompted(now: now);
      expect(notifier.reminderBaseline(), now);
      expect(await notifier.isReminderDue(now: now), isFalse);
    });

    test('chu kỳ "Tắt" thì không bao giờ nhắc', () async {
      final container = await containerWith({
        'dictionarySync.reminderDays': 0,
        'dictionarySync.reminderBaseline': now
            .subtract(const Duration(days: 999))
            .millisecondsSinceEpoch,
      });
      final notifier = container.read(dictionarySyncProvider.notifier);
      expect(await notifier.isReminderDue(now: now), isFalse);
    });

    test('setting kẹp chu kỳ đã lưu về tối thiểu 2 tuần', () async {
      final container = await containerWith({
        'dictionarySync.reminderDays': 3,
      });
      expect(
        container.read(settingsProvider).dictionarySyncReminderDays,
        SyncReminder.minIntervalDays,
      );

      await container
          .read(settingsProvider.notifier)
          .setDictionarySyncReminderDays(5);
      expect(
        container.read(settingsProvider).dictionarySyncReminderDays,
        SyncReminder.minIntervalDays,
      );
    });
  });
}
