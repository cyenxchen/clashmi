import 'dart:io';

import 'package:clashmi/app/utils/auto_update_utils.dart';
import 'package:clashmi/app/utils/version_compare_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses GitHub release assets for current platform', () {
    final platform = Platform.operatingSystem;
    final assetName = _assetNameForPlatform(platform);

    final items = AutoupdateUtils.parseAutoupdateItems({
      'tag_name': 'v1.2.3',
      'prerelease': false,
      'assets': [
        {
          'name': assetName,
          'browser_download_url':
              'https://github.com/cyenxchen/clashmi/releases/download/v1.2.3/$assetName',
          'digest': 'sha256:abc123',
        },
      ],
    });

    expect(items, hasLength(1));
    expect(items.single.platform, platform);
    expect(items.single.version, '1.2.3.0');
    expect(items.single.url, contains('cyenxchen/clashmi/releases/download'));
    expect(items.single.sha256, 'abc123');
    expect(items.single.updateChannel, ['stable']);
  });

  test('normalizes GitHub 3-part tag versions for numeric comparison', () {
    final platform = Platform.operatingSystem;
    final assetName = _assetNameForPlatform(platform);

    final items = AutoupdateUtils.parseAutoupdateItems({
      'tag_name': 'v1.0.10',
      'prerelease': false,
      'assets': [
        {
          'name': assetName,
          'browser_download_url':
              'https://github.com/cyenxchen/clashmi/releases/download/v1.0.10/$assetName',
        },
      ],
    });

    expect(items, hasLength(1));
    expect(items.single.version, '1.0.10.0');
    expect(
      VersionCompareUtils.compareVersion('1.0.9.1', items.single.version),
      lessThan(0),
    );
  });

  test('filters non-production GitHub tags out of stable updates', () {
    final platform = Platform.operatingSystem;
    final assetName = _assetNameForPlatform(platform);

    final items = AutoupdateUtils.parseAutoupdateItems({
      'tag_name': 'v1.0.22-ci-test-20260504-3',
      'prerelease': false,
      'assets': [
        {
          'name': assetName,
          'browser_download_url':
              'https://github.com/cyenxchen/clashmi/releases/download/v1.0.22-ci-test-20260504-3/$assetName',
        },
      ],
    });

    expect(items, isEmpty);
  });

  test('preserves Flutter build metadata in GitHub tag versions', () {
    final platform = Platform.operatingSystem;
    final assetName = _assetNameForPlatform(platform);

    final items = AutoupdateUtils.parseAutoupdateItems({
      'tag_name': 'v1.0.22+803',
      'prerelease': false,
      'assets': [
        {
          'name': assetName,
          'browser_download_url':
              'https://github.com/cyenxchen/clashmi/releases/download/v1.0.22%2B803/$assetName',
        },
      ],
    });

    expect(items, hasLength(1));
    expect(items.single.version, '1.0.22.803');
  });

  test('matches Linux GitHub assets to package channels', () {
    final items = AutoupdateUtils.parseAutoupdateItems({
      'tag_name': 'v1.2.3',
      'prerelease': false,
      'assets': [
        {
          'name': 'clashmi_v1.2.3_linux_x86_64.deb',
          'browser_download_url':
              'https://github.com/cyenxchen/clashmi/releases/download/v1.2.3/clashmi.deb',
        },
        {
          'name': 'clashmi_v1.2.3_linux_x86_64.rpm',
          'browser_download_url':
              'https://github.com/cyenxchen/clashmi/releases/download/v1.2.3/clashmi.rpm',
        },
        {
          'name': 'clashmi_v1.2.3_linux_x86_64.AppImage',
          'browser_download_url':
              'https://github.com/cyenxchen/clashmi/releases/download/v1.2.3/clashmi.AppImage',
        },
      ],
    }, operatingSystem: 'linux');

    expect(items, hasLength(2));
    expect(
      items.singleWhere((item) => item.fileName.endsWith('.deb')).channels,
      containsAll(['deb', 'linux-deb']),
    );
    expect(
      items.singleWhere((item) => item.fileName.endsWith('.rpm')).channels,
      containsAll(['rpm', 'linux-rpm']),
    );
    expect(
      items.singleWhere((item) => item.fileName.endsWith('.deb')).channels,
      isNot(contains('rpm')),
    );
    expect(items.any((item) => item.fileName.endsWith('.AppImage')), isFalse);
  });

  test('builds paginated GitHub releases API urls', () {
    const url =
        'https://api.github.com/repos/cyenxchen/clashmi/releases?platform=android';

    expect(AutoupdateUtils.isGithubReleasesApiUrl(url), isTrue);
    expect(AutoupdateUtils.shouldAppendSignedQueryParams(url), isFalse);
    expect(
      AutoupdateUtils.shouldAppendSignedQueryParams(
        'https://clashmi.app/auto_update.json',
      ),
      isTrue,
    );
    expect(
      AutoupdateUtils.githubReleasesPageUrl(url, 2),
      'https://api.github.com/repos/cyenxchen/clashmi/releases?platform=android&per_page=100&page=2',
    );
    expect(
      AutoupdateUtils.isGithubReleasesApiUrl(
        'https://api.github.com/repos/cyenxchen/clashmi/releases/latest',
      ),
      isFalse,
    );
  });

  test('ignores GitHub sidecar assets that are not installers', () {
    final items = AutoupdateUtils.parseAutoupdateItems({
      'tag_name': 'v1.2.3',
      'prerelease': false,
      'assets': [
        {
          'name': 'clashmi_v1.2.3_android_arm64-v8a.apk.sha256',
          'browser_download_url':
              'https://github.com/cyenxchen/clashmi/releases/download/v1.2.3/clashmi.apk.sha256',
        },
        {
          'name': 'clashmi_v1.2.3_android_arm64-v8a.apk',
          'browser_download_url':
              'https://github.com/cyenxchen/clashmi/releases/download/v1.2.3/clashmi.apk',
        },
      ],
    }, operatingSystem: 'android');

    expect(items, hasLength(1));
    expect(items.single.fileName, endsWith('.apk'));
  });

  test('keeps legacy autoupdate json format compatible', () {
    final items = AutoupdateUtils.parseAutoupdateItems([
      {
        'platform': Platform.operatingSystem,
        'channels': ['*'],
        'abis': ['*'],
        'version': '1.2.4',
        'url': 'https://example.com/app.pkg',
        'sha256': 'def456',
        'file_name': 'app.pkg',
        'version_channel': ['beta'],
      },
    ]);

    expect(items, hasLength(1));
    expect(items.single.version, '1.2.4');
    expect(items.single.updateChannel, ['beta']);
  });
}

String _assetNameForPlatform(String platform) {
  switch (platform) {
    case 'android':
      return 'clashmi_v1.2.3_android_arm64-v8a.apk';
    case 'macos':
      return 'clashmi_v1.2.3_macos_universal.dmg';
    case 'windows':
      return 'clashmi_v1.2.3_windows_x86_64.exe';
    case 'linux':
      return 'clashmi_v1.2.3_linux_x86_64.deb';
    default:
      return 'clashmi_v1.2.3_$platform';
  }
}
