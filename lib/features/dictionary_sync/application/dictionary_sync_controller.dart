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
  final AdminSession? session;
  final String? message;

  const DictionarySyncState({
    this.isLoggingIn = false,
    this.isSyncing = false,
    this.session,
    this.message,
  });

  bool get isAdmin => session != null;

  DictionarySyncState copyWith({
    bool? isLoggingIn,
    bool? isSyncing,
    AdminSession? session,
    bool clearSession = false,
    String? message,
    bool clearMessage = false,
  }) => DictionarySyncState(
    isLoggingIn: isLoggingIn ?? this.isLoggingIn,
    isSyncing: isSyncing ?? this.isSyncing,
    session: clearSession ? null : (session ?? this.session),
    message: clearMessage ? null : (message ?? this.message),
  );
}

class DictionarySyncController extends Notifier<DictionarySyncState> {
  static String _cursorKey(TranslationMode mode) =>
      'sharedDictionary.cursor.${mode.name}';

  @override
  DictionarySyncState build() => const DictionarySyncState();

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

  void logout() {
    state = state.copyWith(clearSession: true, message: 'Đã đăng xuất.');
  }

  Future<void> publish({
    required TranslationMode mode,
    required SharedDictionaryKind kind,
    required String source,
    required String target,
  }) async {
    final session = state.session;
    if (session == null) return;
    final entry = SharedDictionaryEntry(
      kind: kind,
      source: source,
      target: target,
    );
    final client = http.Client();
    try {
      await DictionarySyncApi(
        serverUrl: ref.read(settingsProvider).syncServerUrl,
        client: client,
      ).publish(session.token, mode, entry);
      final paths = await ref.read(appPathsProvider.future);
      await SharedDictionaryService(paths).applyDelta(mode, [entry]);
      await _reloadCurrentTranslation();
      final dictionaryName = kind == SharedDictionaryKind.vietPhrase
          ? 'VietPhrase'
          : 'Lạc Việt';
      state = state.copyWith(message: 'Đã cập nhật $dictionaryName chung.');
    } catch (error) {
      if (error is DictionarySyncException && error.statusCode == 401) {
        state = state.copyWith(clearSession: true, message: error.message);
      } else {
        state = state.copyWith(message: _messageFor(error));
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
      final changed = await SharedDictionaryService(
        paths,
      ).applyDelta(mode, entries);
      await prefs.setString(_cursorKey(mode), cursor);
      if (changed > 0) {
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
}

final dictionarySyncProvider =
    NotifierProvider<DictionarySyncController, DictionarySyncState>(
      DictionarySyncController.new,
    );
