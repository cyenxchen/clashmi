import 'dart:convert';
import 'dart:io';

import 'package:clashmi/app/local_services/vpn_service.dart';
import 'package:clashmi/app/modules/clash_setting_manager.dart';
import 'package:clashmi/app/modules/profile_manager.dart';
import 'package:clashmi/app/modules/profile_patch_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('clashmi_vpn_service');
  late Directory directory;
  late List<Object?> excludedPorts;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('clashmi-mixed-port-');
    PackageInfo.setMockInitialValues(
      appName: 'Clash Mi',
      packageName: 'com.nebula.clashmi',
      version: '1.0.24',
      buildNumber: '1000',
      buildSignature: '',
    );
    FlutterSecureStorage.setMockInitialValues({});
    ClashSettingManager.getConfig().Secret = 'test-secret';
    ClashSettingManager.getConfig().MixedPort = 7890;
  });

  tearDownAll(() => directory.delete(recursive: true));

  setUp(() {
    excludedPorts = [];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      switch (call.method) {
        case 'getAppGroupDirectory':
          return directory.path;
        case 'prepareConfig':
          final args = call.arguments as Map;
          excludedPorts = args['excludePorts'] as List<Object?>;
        case 'currentState':
          return 'connected';
      }
      return null;
    });
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
  });

  Future<Map<String, dynamic>> prepareProfile(
    String patch,
    int? port, {
    String extraConfig = '',
    void Function(ProfileSetting)? configure,
  }) async {
    final file = File('${directory.path}/profile.yaml');
    await file.writeAsString(
      'port: 7890\n${port == null ? '' : 'mixed-port: $port\n'}proxies: []\n$extraConfig',
    );
    expect(await ProfileManager.addLocal(file.path), isNull);
    final profile = ProfileManager.getCurrent()!;
    profile.patch = patch;
    configure?.call(profile);
    await VPNService.init();
    final content = await File(
      '${directory.path}/service_core_patch_final.json',
    ).readAsString();
    return jsonDecode(content) as Map<String, dynamic>;
  }

  test('built-in no-overwrite keeps the profile mixed-port', () async {
    final patch = await prepareProfile(kProfilePatchBuildinNoOverwrite, 7893);

    expect(patch['mixed-port'] ?? 7893, 7893);
    expect(excludedPorts, [9090, 7893]);
    expect(await VPNService.getPortsByPrefer(true), [7893, null]);
  });

  test(
    'built-in no-overwrite keeps an explicitly disabled mixed-port',
    () async {
      final patch = await prepareProfile(kProfilePatchBuildinNoOverwrite, 0);

      expect(patch['mixed-port'] ?? 0, 0);
      expect(excludedPorts, [9090]);
      expect(await VPNService.getPortsByPrefer(true), [null]);
    },
  );

  test('built-in no-overwrite uses the app port when omitted', () async {
    final patch = await prepareProfile(kProfilePatchBuildinNoOverwrite, null);

    expect(patch['mixed-port'], 7890);
    expect(excludedPorts, [9090, 7890]);
    expect(await VPNService.getPortsByPrefer(true), [7890, null]);
  });

  test('custom YAML with built-in no-overwrite keeps its mixed-port', () async {
    final file = File('${directory.path}/patch.yaml');
    await file.writeAsString('mixed-port: 0\n');
    expect(await ProfilePatchManager.addLocal(file.path), isNull);
    final customPatch = ProfilePatchManager.getProfiles().last;
    customPatch.appendPatchBuildin = kProfilePatchBuildinNoOverwrite;

    final patch = await prepareProfile(customPatch.id, 7893);

    expect(patch.containsKey('mixed-port'), isFalse);
    expect(excludedPorts, [9090]);
    expect(await VPNService.getPortsByPrefer(true), [null]);
  });

  test('built-in overwrite uses the app mixed-port', () async {
    final patch = await prepareProfile(kProfilePatchBuildinOverwrite, 7893);

    expect(patch['mixed-port'], 7890);
    expect(excludedPorts, [9090, 7890]);
  });

  test(
    'prepends Apple Push rules in the YAML applied by the open bridge',
    () async {
      final patch = await prepareProfile(
        kProfilePatchBuildinNoOverwrite,
        7893,
        extraConfig: '''
rules:
  - MATCH,DIRECT
proxy-groups:
  - name: Keep
    type: select
    proxies: [DIRECT]
''',
        configure: (profile) => profile.appendApplePushRules = true,
      );

      final rules = patch['rules'] as List;
      expect(rules.first, 'DOMAIN-SUFFIX,push.apple.com,Keep');
      expect(rules.last, 'MATCH,DIRECT');
      expect(patch.containsKey('proxy-groups'), isFalse);
      expect(patch.containsKey('mixed-port'), isFalse);
    },
  );
}
