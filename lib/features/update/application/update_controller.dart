import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../settings/settings_provider.dart';
import '../data/download_file.dart';
import '../data/github_release_api.dart';
import '../data/windows_installer.dart';
import '../domain/app_version.dart';

enum UpdatePhase { idle, checking, upToDate, available, downloading, installing, error }

class UpdateState {
  const UpdateState({
    this.phase = UpdatePhase.idle,
    this.release,
    this.matchedAsset,
    this.downloadProgress = 0,
    this.message,
  });

  final UpdatePhase phase;
  final GitHubRelease? release;
  final ReleaseAsset? matchedAsset;
  final double downloadProgress;
  final String? message;

  UpdateState copyWith({
    UpdatePhase? phase,
    double? downloadProgress,
    String? message,
    bool clearMessage = false,
  }) => UpdateState(
    phase: phase ?? this.phase,
    release: release,
    matchedAsset: matchedAsset,
    downloadProgress: downloadProgress ?? this.downloadProgress,
    message: clearMessage ? null : (message ?? this.message),
  );
}

class UpdateController extends Notifier<UpdateState> {
  static const _lastCheckedMsKey = 'update.lastCheckedMs';
  static const _skippedVersionKey = 'update.skippedVersion';
  static const _checkIntervalMs = 24 * 60 * 60 * 1000;

  @override
  UpdateState build() => const UpdateState();

  static String _messageFor(Object error) {
    if (error is UpdateCheckException) return error.message;
    if (error is TimeoutException) return 'Server phản hồi quá chậm.';
    if (error is http.ClientException) return 'Không thể kết nối GitHub.';
    return 'Kiểm tra cập nhật thất bại.';
  }

  Future<void> checkForUpdate({bool silent = false}) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (silent) {
      final lastChecked = prefs.getInt(_lastCheckedMsKey) ?? 0;
      final elapsed = DateTime.now().millisecondsSinceEpoch - lastChecked;
      if (elapsed < _checkIntervalMs) return;
    }
    if (!silent) {
      state = const UpdateState(phase: UpdatePhase.checking);
    }
    try {
      final release = await const GitHubReleaseApi().fetchLatestRelease();
      await prefs.setInt(_lastCheckedMsKey, DateTime.now().millisecondsSinceEpoch);

      if (release == null) {
        state = UpdateState(
          phase: UpdatePhase.upToDate,
          message: silent ? null : 'Chưa có bản phát hành nào.',
        );
        return;
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final current = AppVersion.parse(packageInfo.version);
      final latest = AppVersion.parse(release.tagName);

      if (!(latest > current)) {
        state = UpdateState(
          phase: UpdatePhase.upToDate,
          message: silent ? null : 'Bạn đang dùng bản mới nhất.',
        );
        return;
      }

      final skippedVersion = prefs.getString(_skippedVersionKey);
      if (silent && skippedVersion == release.tagName) {
        state = const UpdateState();
        return;
      }

      final matchedAsset = Platform.isWindows
          ? findWindowsAsset(release.assets)
          : Platform.isAndroid
              ? findAndroidApkAsset(release.assets)
              : null;

      state = UpdateState(
        phase: UpdatePhase.available,
        release: release,
        matchedAsset: matchedAsset,
      );
    } catch (error) {
      state = UpdateState(
        phase: UpdatePhase.error,
        message: silent ? null : _messageFor(error),
      );
    }
  }

  Future<void> downloadAndInstall() async {
    final release = state.release;
    if (release == null) return;
    if (Platform.isWindows) {
      await _installWindows();
    } else if (Platform.isAndroid) {
      await _installAndroid();
    }
  }

  Future<void> _installWindows() async {
    final asset = state.matchedAsset;
    if (asset == null) {
      await openReleasePage();
      return;
    }
    state = state.copyWith(phase: UpdatePhase.downloading, downloadProgress: 0, clearMessage: true);
    try {
      final tempDir = Directory.systemTemp;
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final zipPath = p.join(tempDir.path, 'vietyaku_update_$stamp.zip');

      await downloadWithProgress(
        url: asset.downloadUrl,
        savePath: zipPath,
        onProgress: (progress) {
          state = state.copyWith(downloadProgress: progress < 0 ? 0 : progress);
        },
      );

      state = state.copyWith(phase: UpdatePhase.installing);

      final stagingDir = p.join(tempDir.path, 'vietyaku_staging_$stamp');
      await extractWindowsZip(zipPath, stagingDir);
      await File(zipPath).delete();

      final exePath = Platform.resolvedExecutable;
      final installDir = File(exePath).parent.path;
      final scriptPath = await writeSelfUpdateScript(
        stagingDir: stagingDir,
        installDir: installDir,
        exePath: exePath,
      );
      await spawnSelfUpdateScript(scriptPath);
      exit(0);
    } catch (error) {
      state = state.copyWith(phase: UpdatePhase.error, message: _messageFor(error));
    }
  }

  Future<void> _installAndroid() async {
    final asset = state.matchedAsset;
    if (asset == null) {
      await openReleasePage();
      return;
    }
    state = state.copyWith(phase: UpdatePhase.downloading, downloadProgress: 0, clearMessage: true);
    try {
      final tempDir = await getTemporaryDirectory();
      final apkPath = p.join(tempDir.path, 'vietyaku_update.apk');

      await downloadWithProgress(
        url: asset.downloadUrl,
        savePath: apkPath,
        onProgress: (progress) {
          state = state.copyWith(downloadProgress: progress < 0 ? 0 : progress);
        },
      );

      state = state.copyWith(phase: UpdatePhase.installing);
      final result = await OpenFilex.open(apkPath);
      if (result.type != ResultType.done) {
        state = state.copyWith(
          phase: UpdatePhase.error,
          message: result.message.isNotEmpty ? result.message : 'Không thể mở trình cài đặt.',
        );
        return;
      }
      state = state.copyWith(phase: UpdatePhase.idle);
    } catch (error) {
      state = state.copyWith(phase: UpdatePhase.error, message: _messageFor(error));
    }
  }

  Future<void> openReleasePage() async {
    final url = state.release?.htmlUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> skipCurrentVersion() async {
    final release = state.release;
    if (release == null) return;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_skippedVersionKey, release.tagName);
    state = const UpdateState();
  }

  void dismiss() {
    state = const UpdateState();
  }
}

final updateControllerProvider = NotifierProvider<UpdateController, UpdateState>(UpdateController.new);
