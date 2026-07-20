import 'package:flutter_test/flutter_test.dart';
import 'package:vietyaku/features/update/data/github_release_api.dart';

void main() {
  group('findWindowsAsset', () {
    test('tìm đúng file .zip có tên chứa windows', () {
      final assets = [
        const ReleaseAsset(name: 'VietYaku-1.0.0.apk', downloadUrl: 'a', size: 1),
        const ReleaseAsset(
          name: 'VietYaku-1.0.0-windows-x64.zip',
          downloadUrl: 'b',
          size: 2,
        ),
      ];
      final result = findWindowsAsset(assets);
      expect(result?.name, 'VietYaku-1.0.0-windows-x64.zip');
    });

    test('trả về null nếu không có asset windows', () {
      final assets = [
        const ReleaseAsset(name: 'VietYaku-1.0.0.apk', downloadUrl: 'a', size: 1),
      ];
      expect(findWindowsAsset(assets), isNull);
    });

    test('không khớp .zip không phải windows', () {
      final assets = [
        const ReleaseAsset(name: 'source-code.zip', downloadUrl: 'a', size: 1),
      ];
      expect(findWindowsAsset(assets), isNull);
    });
  });

  group('findAndroidApkAsset', () {
    test('tìm đúng file .apk', () {
      final assets = [
        const ReleaseAsset(
          name: 'VietYaku-1.0.0-windows-x64.zip',
          downloadUrl: 'a',
          size: 1,
        ),
        const ReleaseAsset(name: 'VietYaku-1.0.0.apk', downloadUrl: 'b', size: 2),
      ];
      final result = findAndroidApkAsset(assets);
      expect(result?.name, 'VietYaku-1.0.0.apk');
    });

    test('trả về null nếu chưa có apk (thực trạng hiện tại)', () {
      final assets = [
        const ReleaseAsset(
          name: 'VietYaku-1.0.0-windows-x64.zip',
          downloadUrl: 'a',
          size: 1,
        ),
      ];
      expect(findAndroidApkAsset(assets), isNull);
    });
  });

  group('GitHubRelease.fromJson', () {
    test('parse đầy đủ field từ JSON GitHub API', () {
      final release = GitHubRelease.fromJson({
        'tag_name': 'v1.2.0',
        'name': 'VietYaku 1.2.0',
        'body': 'Ghi chú phát hành',
        'html_url': 'https://github.com/LittleKai/VietYaku/releases/tag/v1.2.0',
        'assets': [
          {
            'name': 'VietYaku-1.2.0-windows-x64.zip',
            'browser_download_url': 'https://example.com/file.zip',
            'size': 12345,
          },
        ],
      });

      expect(release.tagName, 'v1.2.0');
      expect(release.name, 'VietYaku 1.2.0');
      expect(release.body, 'Ghi chú phát hành');
      expect(release.assets, hasLength(1));
      expect(release.assets.first.downloadUrl, 'https://example.com/file.zip');
      expect(release.assets.first.size, 12345);
    });

    test('name fallback về tag_name nếu thiếu', () {
      final release = GitHubRelease.fromJson({'tag_name': 'v1.0.0'});
      expect(release.name, 'v1.0.0');
      expect(release.assets, isEmpty);
    });
  });
}
