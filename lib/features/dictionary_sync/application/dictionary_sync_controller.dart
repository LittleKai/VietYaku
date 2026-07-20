import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../dictionary/application/dictionaries_provider.dart';
import '../../settings/settings_provider.dart';
import '../../translation/application/translation_controller.dart';
import '../../translation/domain/translation_engine.dart';
import '../data/dictionary_sync_api.dart';
import '../data/shared_dictionary_service.dart';
import '../domain/shared_dictionary_entry.dart';

class DictionarySyncState {
  final bool isLoggingIn;
  final bool isSyncing;
  final bool isPublishing;
  final AdminSession? session;
  final String? message;

  const DictionarySyncState({
    this.isLoggingIn = false,
    this.isSyncing = false,
    this.isPublishing = false,
    this.session,
    this.message,
  });

  bool get isAdmin => session != null;

  DictionarySyncState copyWith({
    bool? isLoggingIn,
    bool? isSyncing,
    bool? isPublishing,
    AdminSession? session,
    bool clearSession = false,
    String? message,
    bool clearMessage = false,
  }) => DictionarySyncState(
    isLoggingIn: isLoggingIn ?? this.isLoggingIn,
    isSyncing: isSyncing ?? this.isSyncing,
    isPublishing: isPublishing ?? this.isPublishing,
    session: clearSession ? null : (session ?? this.session),
    message: clearMessage ? null : (message ?? this.message),
  );
}

class DictionarySyncController extends Notifier<DictionarySyncState> {
  static const _sessionUsernameKey = 'dictionarySync.admin.username';
  static const _sessionTokenKey = 'dictionarySync.admin.token';

  /// Số sửa đổi cục bộ đang chờ mà khi đạt tới sẽ tự động Update lên server,
  /// ngoài việc bấm nút Update thủ công.
  static const _autoPublishThreshold = 10;

  static String _cursorKey(TranslationMode mode) =>
      'sharedDictionary.cursor.${mode.name}';

  @override
  DictionarySyncState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final username = prefs.getString(_sessionUsernameKey);
    final token = prefs.getString(_sessionTokenKey);
    final session = username == null || token == null || token.isEmpty
        ? null
        : AdminSession(username: username, token: token);
    return DictionarySyncState(session: session);
  }

  static String _messageFor(Object error) {
    if (error is DictionarySyncException) return error.message;
    if (error is TimeoutException) return 'Server phản hồi quá chậm.';
    if (error is http.ClientException) {
      return 'Không thể kết nối LittleKai server.';
    }
    return 'Đồng bộ từ điển thất bại.';
  }

  Future<void> login({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    state = state.copyWith(isLoggingIn: true, clearMessage: true);
    final client = http.Client();
    try {
      final session = await DictionarySyncApi(
        serverUrl: serverUrl,
        client: client,
      ).login(username.trim(), password);
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.setString(_sessionUsernameKey, session.username);
      await prefs.setString(_sessionTokenKey, session.token);
      state = state.copyWith(
        isLoggingIn: false,
        session: session,
        message: 'Đã đăng nhập quản trị.',
      );
    } catch (error) {
      state = state.copyWith(isLoggingIn: false, message: _messageFor(error));
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<void> logout() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove(_sessionUsernameKey);
    await prefs.remove(_sessionTokenKey);
    state = state.copyWith(clearSession: true, message: 'Đã đăng xuất.');
  }

  Future<void> stageLocalEdit({
    required TranslationMode mode,
    required SharedDictionaryKind kind,
    required String source,
    required String target,
  }) async {
    if (!state.isAdmin) return;
    final entry = SharedDictionaryEntry(
      kind: kind,
      source: source,
      target: target,
    );
    final paths = await ref.read(appPathsProvider.future);
    final service = SharedDictionaryService(paths);
    await service.stageLocalEdit(mode, entry);
    await _reloadCurrentTranslation();
    final dictionaryName = kind == SharedDictionaryKind.vietPhrase
        ? 'VietPhrase'
        : 'Lạc Việt';

    var pendingCount = 0;
    for (final m in TranslationMode.values) {
      pendingCount += (await service.pendingEntries(m)).length;
    }
    if (pendingCount >= _autoPublishThreshold) {
      // Đủ số sửa đổi chờ: tự động Update, không cần bấm nút thủ công.
      try {
        await publishPending();
      } catch (_) {
        // publishPending() đã ánh xạ lỗi vào state.message.
      }
      return;
    }

    state = state.copyWith(
      message: 'Đã lưu $dictionaryName. Bấm Update để gửi lên server.',
    );
  }

  /// Gửi tất cả sửa đổi admin đang chờ của cả hai ngôn ngữ lên server.
  Future<int> publishPending() async {
    final session = state.session;
    if (session == null || state.isPublishing) return 0;
    state = state.copyWith(isPublishing: true, clearMessage: true);
    final client = http.Client();
    try {
      final api = DictionarySyncApi(
        serverUrl: ref.read(settingsProvider).syncServerUrl,
        client: client,
      );
      final paths = await ref.read(appPathsProvider.future);
      final service = SharedDictionaryService(paths);
      var published = 0;
      for (final mode in TranslationMode.values) {
        final entries = await service.pendingEntries(mode);
        for (final entry in entries) {
          await api.publish(session.token, mode, entry);
        }
        if (entries.isNotEmpty) {
          await service.clearPending(mode);
          published += entries.length;
        }
      }
      state = state.copyWith(
        isPublishing: false,
        message: published == 0
            ? 'Không có thay đổi nào đang chờ Update.'
            : 'Đã Update $published mục VietPhrase/Lạc Việt lên server.',
      );
      return published;
    } catch (error) {
      if (error is DictionarySyncException && error.statusCode == 401) {
        await _clearPersistedSession();
        state = state.copyWith(
          isPublishing: false,
          clearSession: true,
          message: error.message,
        );
      } else {
        state = state.copyWith(
          isPublishing: false,
          message: _messageFor(error),
        );
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<int> sync(TranslationMode mode) async {
    if (state.isSyncing) return 0;
    state = state.copyWith(isSyncing: true, clearMessage: true);
    final prefs = ref.read(sharedPreferencesProvider);
    var cursor = prefs.getString(_cursorKey(mode)) ?? '';
    final entries = <SharedDictionaryEntry>[];
    final client = http.Client();
    try {
      final api = DictionarySyncApi(
        serverUrl: ref.read(settingsProvider).syncServerUrl,
        client: client,
      );
      while (true) {
        final page = await api.fetchPage(mode, cursor);
        entries.addAll(page.items);
        if (!page.hasMore) {
          cursor = page.nextCursor;
          break;
        }
        if (page.nextCursor.isEmpty || page.nextCursor == cursor) {
          throw const DictionarySyncException(
            'Server trả về cursor đồng bộ không hợp lệ.',
          );
        }
        cursor = page.nextCursor;
      }

      final paths = await ref.read(appPathsProvider.future);
      final service = SharedDictionaryService(paths);
      final changed = await service.applyDelta(mode, entries);
      // Bản server không được ghi đè các sửa đổi admin chưa bấm Update.
      final restored = await service.applyDelta(
        mode,
        await service.pendingEntries(mode),
      );
      await prefs.setString(_cursorKey(mode), cursor);
      if (changed > 0 || restored > 0) {
        await _reloadCurrentTranslation();
      }
      state = state.copyWith(
        isSyncing: false,
        message: changed == 0
            ? 'Từ điển chung đã là bản mới nhất.'
            : 'Đã cập nhật $changed mục từ.',
      );
      return changed;
    } catch (error) {
      state = state.copyWith(isSyncing: false, message: _messageFor(error));
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<void> _reloadCurrentTranslation() async {
    await ref.read(dictionariesProvider.notifier).reload();
    final translation = ref.read(translationControllerProvider);
    if (translation.sourceText.isNotEmpty) {
      ref
          .read(translationControllerProvider.notifier)
          .translate(translation.sourceText);
    }
  }

  Future<void> _clearPersistedSession() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove(_sessionUsernameKey);
    await prefs.remove(_sessionTokenKey);
  }
}

final dictionarySyncProvider =
    NotifierProvider<DictionarySyncController, DictionarySyncState>(
      DictionarySyncController.new,
    );
