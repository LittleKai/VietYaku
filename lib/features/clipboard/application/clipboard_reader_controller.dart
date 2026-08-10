import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../dictionary/application/dictionaries_provider.dart';
import '../../settings/settings_provider.dart';
import '../../translation/application/translation_controller.dart';
import '../domain/clipboard_read_filter.dart';

class ClipboardBridgeStatus {
  final bool available;
  final bool enabled;
  final bool hotkeyRegistered;
  final String? lastMessage;

  const ClipboardBridgeStatus({
    required this.available,
    this.enabled = false,
    this.hotkeyRegistered = false,
    this.lastMessage,
  });

  ClipboardBridgeStatus copyWith({
    bool? available,
    bool? enabled,
    bool? hotkeyRegistered,
    String? lastMessage,
  }) => ClipboardBridgeStatus(
    available: available ?? this.available,
    enabled: enabled ?? this.enabled,
    hotkeyRegistered: hotkeyRegistered ?? this.hotkeyRegistered,
    lastMessage: lastMessage ?? this.lastMessage,
  );
}

class WindowsClipboardBridge {
  static const _channel = MethodChannel('vietyaku/windows_bridge');

  Future<void> Function(String event)? onEvent;

  WindowsClipboardBridge() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'clipboardChanged' || call.method == 'hotkeyPressed') {
        await onEvent?.call(call.method);
      }
    });
  }

  Future<bool> setEnabled(bool enabled) async {
    final response = await _channel.invokeMapMethod<String, Object?>(
      'setEnabled',
      enabled,
    );
    return response?['hotkeyRegistered'] == true;
  }

  void dispose() {
    onEvent = null;
    _channel.setMethodCallHandler(null);
  }
}

final windowsClipboardBridgeProvider = Provider<WindowsClipboardBridge>((ref) {
  final bridge = WindowsClipboardBridge();
  ref.onDispose(bridge.dispose);
  return bridge;
});

class ClipboardReaderController extends Notifier<ClipboardBridgeStatus> {
  final _filter = ClipboardReadFilter();
  bool _nativeEnabled = false;
  bool _active = true;

  @override
  ClipboardBridgeStatus build() {
    _active = true;
    final available = Platform.isWindows;
    final enabled = ref.watch(
      settingsProvider.select((settings) => settings.clipboardReaderEnabled),
    );
    if (!available) {
      return const ClipboardBridgeStatus(available: false);
    }
    final bridge = ref.watch(windowsClipboardBridgeProvider);
    bridge.onEvent = _handleNativeEvent;
    unawaited(_setNativeEnabled(enabled));
    ref.onDispose(() {
      _active = false;
      if (_nativeEnabled) unawaited(bridge.setEnabled(false));
    });
    return ClipboardBridgeStatus(available: true, enabled: enabled);
  }

  Future<void> _setNativeEnabled(bool enabled) async {
    if (_nativeEnabled == enabled) return;
    _nativeEnabled = enabled;
    try {
      final registered = await ref
          .read(windowsClipboardBridgeProvider)
          .setEnabled(enabled);
      if (!_active) return;
      state = state.copyWith(
        enabled: enabled,
        hotkeyRegistered: enabled && registered,
        lastMessage: enabled && !registered
            ? 'Không đăng ký được Ctrl+Shift+V; clipboard reader vẫn hoạt động.'
            : null,
      );
    } on PlatformException catch (error) {
      if (!_active) return;
      state = state.copyWith(
        enabled: false,
        hotkeyRegistered: false,
        lastMessage: error.message ?? 'Không thể bật clipboard reader.',
      );
    }
  }

  Future<void> _handleNativeEvent(String event) async {
    if (!ref.read(settingsProvider).clipboardReaderEnabled) return;
    // Cho ứng dụng nguồn hoàn tất việc đặt CF_UNICODETEXT trước khi đọc.
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || !_filter.shouldAccept(text, DateTime.now())) return;
    await ref.read(dictionariesProvider.future);
    if (!_active) return;
    ref.read(translationControllerProvider.notifier).translate(text);
    if (event == 'hotkeyPressed') {
      await windowManager.show();
      await windowManager.focus();
    }
    if (!_active) return;
    state = state.copyWith(
      lastMessage: event == 'hotkeyPressed'
          ? 'Đã dịch clipboard bằng Ctrl+Shift+V.'
          : 'Đã tự động dịch nội dung clipboard mới.',
    );
  }

  Future<void> writeClipboard(String text) async {
    _filter.markOwnWrite(text, DateTime.now());
    await Clipboard.setData(ClipboardData(text: text));
  }
}

final clipboardReaderControllerProvider =
    NotifierProvider<ClipboardReaderController, ClipboardBridgeStatus>(
      ClipboardReaderController.new,
    );

Future<void> writeAppClipboard(WidgetRef ref, String text) =>
    ref.read(clipboardReaderControllerProvider.notifier).writeClipboard(text);
