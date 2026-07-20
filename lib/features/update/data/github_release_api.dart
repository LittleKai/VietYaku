import 'dart:convert';

import 'package:http/http.dart' as http;

const String _owner = 'LittleKai';
const String _repo = 'VietYaku';

class UpdateCheckException implements Exception {
  const UpdateCheckException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
  });

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) => ReleaseAsset(
    name: json['name'] as String? ?? '',
    downloadUrl: json['browser_download_url'] as String? ?? '',
    size: (json['size'] as num?)?.toInt() ?? 0,
  );

  final String name;
  final String downloadUrl;
  final int size;
}

class GitHubRelease {
  const GitHubRelease({
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.assets,
  });

  factory GitHubRelease.fromJson(Map<String, dynamic> json) => GitHubRelease(
    tagName: json['tag_name'] as String? ?? '',
    name: json['name'] as String? ?? (json['tag_name'] as String? ?? ''),
    body: json['body'] as String? ?? '',
    htmlUrl: json['html_url'] as String? ?? '',
    assets: (json['assets'] as List<dynamic>? ?? const [])
        .map((e) => ReleaseAsset.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  final String tagName;
  final String name;
  final String body;
  final String htmlUrl;
  final List<ReleaseAsset> assets;
}

/// Asset ZIP Windows do skill build-and-release đóng gói: `VietYaku-<version>-windows-x64.zip`.
ReleaseAsset? findWindowsAsset(List<ReleaseAsset> assets) {
  for (final asset in assets) {
    final lower = asset.name.toLowerCase();
    if (lower.contains('windows') && lower.endsWith('.zip')) {
      return asset;
    }
  }
  return null;
}

ReleaseAsset? findAndroidApkAsset(List<ReleaseAsset> assets) {
  for (final asset in assets) {
    if (asset.name.toLowerCase().endsWith('.apk')) {
      return asset;
    }
  }
  return null;
}

class GitHubReleaseApi {
  // ignore: prefer_initializing_formals
  const GitHubReleaseApi({http.Client? client}) : _client = client;

  final http.Client? _client;

  /// Trả về `null` nếu repo chưa có release nào (404).
  Future<GitHubRelease?> fetchLatestRelease() async {
    final client = _client ?? http.Client();
    final owns = _client == null;
    try {
      final response = await client
          .get(
            Uri.parse(
              'https://api.github.com/repos/$_owner/$_repo/releases/latest',
            ),
            headers: const {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) {
        throw UpdateCheckException(
          'Không thể kiểm tra cập nhật (mã lỗi ${response.statusCode}).',
        );
      }

      final json = jsonDecode(utf8.decode(response.bodyBytes));
      return GitHubRelease.fromJson(json as Map<String, dynamic>);
    } on UpdateCheckException {
      rethrow;
    } catch (_) {
      throw const UpdateCheckException(
        'Không thể kết nối GitHub để kiểm tra cập nhật.',
      );
    } finally {
      if (owns) client.close();
    }
  }
}
