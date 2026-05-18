// ignore_for_file: unused_catch_stack, empty_catches

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clashmi/app/clash/clash_config.dart';
import 'package:clashmi/app/clash/clash_http_api.dart';
import 'package:clashmi/app/local_services/vpn_service.dart';
import 'package:clashmi/app/modules/diversion_template_manager.dart';
import 'package:clashmi/app/modules/profile_manager.dart';
import 'package:clashmi/app/runtime/return_result.dart';
import 'package:clashmi/app/utils/app_utils.dart';
import 'package:clashmi/app/utils/did.dart';
import 'package:clashmi/app/utils/log.dart';
import 'package:clashmi/app/utils/path_utils.dart';
import 'package:clashmi/i18n/strings.g.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'package:clashmi_vpn_service/proxy_manager.dart';
import 'package:path/path.dart' as path;

class ClashSettingManager {
  static final List<void Function()> onEventModeChanged = [];
  static const _bundledGeoMetadataFileName = ".clashmi_bundled_geodata.json";
  static const _bundledGeoManifestAssetPath =
      "assets/datas/geodata_manifest.json";
  static const _externalGeoMetadataPrefix = "external:";
  static const iNet4Address = "172.19.0.1/30";
  static const iNet6Address = "fdfe:dcbe:9876::1/126";
  static const dnsHijack = "0.0.0.0:53";
  static RawConfig _setting = defaultConfig();

  static Future<void> init() async {
    ClashHttpApi.getControlPort = () {
      return getControlPort();
    };
    ClashHttpApi.getSecret = () {
      return _setting.Secret ?? "";
    };
    await load();
    await initGeo();
  }

  static Future<void> initGeo() async {
    final homePath = await PathUtils.profileDir();
    final fileNameList = [
      "geosite.zip",
      "geoip.zip",
      if (!Platform.isIOS) "ASN.mmdb",
      if (Platform.isAndroid) ...["GeoSite.dat", "GeoIP.dat"],
    ];

    try {
      final bundledGeoManifest = await _loadBundledGeoManifest();
      final bundledGeoMetadata = await _loadBundledGeoMetadata(homePath);
      var metadataChanged = false;
      for (final fileName in fileNameList) {
        final filePath = File(path.join(homePath, fileName));
        final bundledAsset =
            bundledGeoManifest[fileName] ??
            await _loadBundledGeoAssetWithHash(fileName);
        final bundledHash = bundledAsset.sha256;
        final metadataValue = bundledGeoMetadata[fileName];
        final previousBundledHash = _metadataBundledHash(metadataValue);
        final exists = await filePath.exists();
        var shouldCopy = !exists;
        var reason = "missing";
        int? localAgeDays;

        if (exists && _metadataMatchesBundled(metadataValue, bundledHash)) {
          Log.i(
            "ClashSettingManager.initGeo skipped current local $fileName "
            "reason=metadata-current path=$filePath size=${bundledAsset.size} "
            "hash=${_shortHash(bundledHash)} metadata=${_metadataLabel(metadataValue)}",
          );
          continue;
        }

        if (exists &&
            _isAndroidDat(fileName) &&
            _isExternalGeoMetadata(metadataValue)) {
          final nextMetadataValue = _externalGeoMetadataValue(bundledHash);
          if (metadataValue != nextMetadataValue) {
            bundledGeoMetadata[fileName] = nextMetadataValue;
            metadataChanged = true;
          }
          Log.i(
            "ClashSettingManager.initGeo preserved external DAT $fileName "
            "reason=metadata-external path=$filePath bundled=${_shortHash(bundledHash)} "
            "previous=${_shortHash(previousBundledHash)}",
          );
          continue;
        }

        if (exists) {
          final stat = await filePath.stat();
          localAgeDays = DateTime.now().difference(stat.modified).inDays;
          final localHash = sha256
              .convert(await filePath.readAsBytes())
              .toString();
          if (localHash == bundledHash) {
            reason = "already current";
          } else if (previousBundledHash != null &&
              localHash == previousBundledHash) {
            shouldCopy = true;
            reason = "bundled asset updated";
          } else if (previousBundledHash == null && _isAndroidDat(fileName)) {
            reason = "metadata migration preserved existing DAT";
          } else if (previousBundledHash == null && localAgeDays >= 7) {
            shouldCopy = true;
            reason = "metadata migration refresh after ${localAgeDays}d";
          } else {
            reason = previousBundledHash == null
                ? "metadata migration kept recent local file"
                : "local file changed outside bundled asset";
          }

          if (!shouldCopy && localHash != bundledHash) {
            if (_isAndroidDat(fileName)) {
              final nextMetadataValue = _externalGeoMetadataValue(bundledHash);
              if (bundledGeoMetadata[fileName] != nextMetadataValue) {
                bundledGeoMetadata[fileName] = nextMetadataValue;
                metadataChanged = true;
              }
            }
            // Unknown local geodata may come from an online update, so do not
            // stamp it as bundled until the local copy is known bundled.
            Log.i(
              "ClashSettingManager.initGeo kept local $fileName reason=$reason "
              "local=${_shortHash(localHash)} bundled=${_shortHash(bundledHash)} "
              "previous=${_shortHash(previousBundledHash)} ageDays=$localAgeDays "
              "metadata=${_isAndroidDat(fileName) ? "external" : "unchanged"}",
            );
            continue;
          }
        }

        if (shouldCopy) {
          final bytes = await _loadBundledGeoAssetBytes(fileName);
          await filePath.writeAsBytes(bytes, flush: true);
        }
        if (bundledGeoMetadata[fileName] != bundledHash) {
          bundledGeoMetadata[fileName] = bundledHash;
          metadataChanged = true;
        }
        Log.i(
          "ClashSettingManager.initGeo ${shouldCopy ? "refreshed" : "verified"} bundled $fileName "
          "reason=$reason path=$filePath size=${bundledAsset.size} hash=${_shortHash(bundledHash)}",
        );
      }
      if (metadataChanged) {
        await _saveBundledGeoMetadata(homePath, bundledGeoMetadata);
      }
    } catch (err) {
      Log.w("ClashSettingManager.initGeo exception ${err.toString()} ");
    }
  }

  static Future<Map<String, _BundledGeoAsset>> _loadBundledGeoManifest() async {
    final raw = jsonDecode(
      await rootBundle.loadString(_bundledGeoManifestAssetPath),
    );
    if (raw is! Map) {
      throw const FormatException("bundled geodata manifest must be a map");
    }

    final manifest = <String, _BundledGeoAsset>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is! Map) {
        continue;
      }
      final hash = value["sha256"]?.toString();
      final size = int.tryParse(value["size"]?.toString() ?? "");
      if (hash == null || hash.isEmpty || size == null) {
        continue;
      }
      manifest[entry.key.toString()] = _BundledGeoAsset(
        sha256: hash,
        size: size,
      );
    }
    return manifest;
  }

  static Future<_BundledGeoAsset> _loadBundledGeoAssetWithHash(
    String fileName,
  ) async {
    Log.w(
      "ClashSettingManager.initGeo manifest missing $fileName, hashing asset fallback",
    );
    final bytes = await _loadBundledGeoAssetBytes(fileName);
    return _BundledGeoAsset(
      sha256: sha256.convert(bytes).toString(),
      size: bytes.length,
    );
  }

  static Future<List<int>> _loadBundledGeoAssetBytes(String fileName) async {
    final data = await rootBundle.load('assets/datas/$fileName');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  static Future<Map<String, String>> _loadBundledGeoMetadata(
    String homePath,
  ) async {
    final file = File(path.join(homePath, _bundledGeoMetadataFileName));
    try {
      if (!await file.exists()) {
        return {};
      }
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) {
        return {};
      }
      return raw.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } catch (err) {
      Log.w(
        "ClashSettingManager.initGeo metadata load failed ${err.toString()}",
      );
      return {};
    }
  }

  static Future<void> _saveBundledGeoMetadata(
    String homePath,
    Map<String, String> hashes,
  ) async {
    final file = File(path.join(homePath, _bundledGeoMetadataFileName));
    try {
      await file.writeAsString(jsonEncode(hashes), flush: true);
      Log.i("ClashSettingManager.initGeo metadata saved $file");
    } catch (err) {
      Log.w(
        "ClashSettingManager.initGeo metadata save failed ${err.toString()}",
      );
    }
  }

  static bool _isAndroidDat(String fileName) {
    return fileName == "GeoSite.dat" || fileName == "GeoIP.dat";
  }

  static bool _isExternalGeoMetadata(String? value) {
    return value?.startsWith(_externalGeoMetadataPrefix) ?? false;
  }

  static String _externalGeoMetadataValue(String bundledHash) {
    return "$_externalGeoMetadataPrefix$bundledHash";
  }

  static String? _metadataBundledHash(String? value) {
    if (value == null || _isExternalGeoMetadata(value)) {
      return null;
    }
    return value;
  }

  static bool _metadataMatchesBundled(String? value, String bundledHash) {
    return value == bundledHash ||
        value == _externalGeoMetadataValue(bundledHash);
  }

  static String _metadataLabel(String? value) {
    return _isExternalGeoMetadata(value) ? "external" : "bundled";
  }

  static String _shortHash(String? hash) {
    if (hash == null || hash.isEmpty) {
      return "-";
    }
    return hash.length <= 12 ? hash : hash.substring(0, 12);
  }

  static Future<String> getSecretFromDid() async {
    String secret = await Did.getDid();
    return secret.substring(8, 24);
  }

  static Future<void> reload() async {
    await load();
  }

  static RawTun defaultTun() {
    return RawTun.by(
      OverWrite: true,
      Enable: !Platform.isWindows,
      Stack: (Platform.isIOS || Platform.isMacOS)
          ? ClashTunStack.gvisor.name
          : ClashTunStack.system.name,
      MTU: 4064,
      Inet4Address: [iNet4Address],
      Inet6Address: [iNet6Address],
      DNSHijack: [dnsHijack],
    );
  }

  static RawDNS defaultDNS() {
    const nameServer = [
      "223.5.5.5",
      "119.29.29.29",
      "8.8.8.8",
      "8.8.4.4",
      "1.0.0.1",
      "1.1.1.1",
      "tls://223.5.5.5:853",
      "tls://8.8.8.8",
      "tls://8.8.4.4",
      "tls://1.0.0.1",
      "tls://1.1.1.1",
      "https://dns.alidns.com/dns-query#h3=true",
      "https://mozilla.cloudflare-dns.com/dns-query#DNS&h3=true",
      "quic://dns.adguard.com:784",
      "system",
    ];
    const defaultNameserver = [
      "223.5.5.5",
      "119.29.29.29",
      "8.8.8.8",
      "8.8.4.4",
      "1.0.0.1",
      "1.1.1.1",
      "system",
    ];
    const List<String> fallback = [
      /*"tls://223.5.5.5:853",
        "https://dns.alidns.com/dns-query#h3=true",
        "https://cloudflare-dns.com/dns-query",
        "https://1.12.12.12/dns-query",
        "https://120.53.53.53/dns-query"*/
    ];
    const List<String> proxyServerNameserver = [
      /*"tls://8.8.4.4",
        "tls://1.1.1.1",
        "tls://223.5.5.5:853",
        "https://dns.alidns.com/dns-query#h3=true",*/
    ];
    const fakeIPFilter = [
      "*.lan",
      "*.local",
      "time.*.com",
      "time.*.gov",
      "time.*.edu.cn",
      "time.*.apple.com",
      "time-ios.apple.com",
      "time1.*.com",
      "time2.*.com",
      "time3.*.com",
      "time4.*.com",
      "time5.*.com",
      "time6.*.com",
      "time7.*.com",
      "ntp.*.com",
      "ntp1.*.com",
      "ntp2.*.com",
      "ntp3.*.com",
      "ntp4.*.com",
      "ntp5.*.com",
      "ntp6.*.com",
      "ntp7.*.com",
      "*.time.edu.cn",
      "*.ntp.org.cn",
      "*.pool.ntp.org",
      "+.services.googleapis.cn",
      "+.push.apple.com",
      "time1.cloud.tencent.com",
      "localhost.ptlogin2.qq.com",
      "+.stun.*.*",
      "+.stun.*.*.*",
      "+.stun.*.*.*.*",
      "+.stun.*.*.*.*.*",
      "lens.l.google.com",
      "*.n.n.srv.nintendo.net",
      "+.stun.playstation.net",
      "xbox.*.*.microsoft.com",
      "*.*.xboxlive.com",
      "*.msftncsi.com",
      "*.msftconnecttest.com",
      "*.mcdn.bilivideo.cn",
      "+.bilibili.com",
      "+.bilicdn.com",
      "+.bilivideo.com",
      "+.market.xiaomi.com",
      "WORKGROUP",
    ];

    return RawDNS.by(
      OverWrite: true,
      Enable: true,
      PreferH3: true,
      IPv6: false,
      IPv6Timeout: 300,
      UseHosts: true,
      UseSystemHosts: true,
      RespectRules: false,
      NameServer: nameServer,
      Fallback: fallback,
      FallbackFilter: RawFallbackFilter.by(GeoIP: null),
      Listen: null,
      EnhancedMode: ClashDnsEnhancedMode.fakeIp.name,
      FakeIPRange: "${iNet4Address.split('/')[0]}/16",
      FakeIPFilter: fakeIPFilter,
      FakeIPFilterMode: ClashFakeIPFilterMode.blacklist.name,
      DefaultNameserver: defaultNameserver,
      CacheAlgorithm: ClashDnsCacheAlgorithm.arc.name,
      NameServerPolicy: {},
      ProxyServerNameserver: proxyServerNameserver,
      DirectNameServer: [],
      DirectNameServerFollowPolicy: false,
    );
  }

  static RawNTP defaultNTP() {
    return RawNTP.by(OverWrite: false, Enable: false);
  }

  static RawSniffer defaultSniffer() {
    return RawSniffer.by(OverWrite: false, Enable: false);
  }

  static RawTLS defaultTLS() {
    return RawTLS.by(
      OverWrite: false,
      Certificate: null,
      PrivateKey: null,
      CustomTrustCert: null,
    );
  }

  static RawExtensionGeoRuleset defaultRawExtensionRuleset() {
    return RawExtensionGeoRuleset.by(
      GeoSiteUrl:
          "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/refs/heads/meta/geo/geosite",
      GeoIpUrl:
          "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/refs/heads/meta/geo/geoip",
      AsnUrl:
          "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/refs/heads/meta/asn",
      UpdateInterval: 2 * 24 * 3600,
      EnableProxy: true,
    );
  }

  static RawExtension defaultExtension() {
    const bypassDomainLocal = ProxyBypassDoaminsDefault;
    List<String> bypassDomainCN = Platform.isAndroid
        ? [
            "*zhihu.com",
            "*zhimg.com",
            "*jd.com",
            "100ime-iat-api.xfyun.cn",
            "*360buyimg.com",
          ]
        : [];

    return RawExtension.by(
      Ruleset: defaultRawExtensionRuleset(),
      Tun: RawExtensionTun.by(
        httpProxy: RawExtensionTunHttpProxy.by(
          Enable: false,
          BypassDomain: bypassDomainLocal + bypassDomainCN,
        ),
        perApp: RawExtensionTunPerApp.by(Enable: false),
      ),
      PprofAddr: null,
    );
  }

  static RawConfig defaultConfig() {
    return RawConfig.by(
      Mode: ClashConfigsMode.rule.name,
      MixedPort: 7890,
      LogLevel: ClashLogLevel.error.name,
      ExternalController: "127.0.0.1:9090",
      IPv6: false,
      DNS: defaultDNS(),
      NTP: defaultNTP(),
      Sniffer: defaultSniffer(),
      TLS: defaultTLS(),
      Tun: defaultTun(),
      Extension: defaultExtension(),
      GlobalClientFingerprint: ClashGlobalClientFingerprint.chrome.name,
      DisableKeepAlive: false,
      KeepAliveIdle: 30,
      KeepAliveInterval: 30,
      FindProcessMode: Platform.isIOS
          ? ClashFindProcessMode.off.name
          : ClashFindProcessMode.always.name,
    );
  }

  static RawConfig defaultConfigNoOverwrite() {
    return RawConfig.by(
      Mode: _setting.Mode,
      MixedPort: _setting.MixedPort,
      LogLevel: _setting.LogLevel,
      ExternalController: _setting.ExternalController,
      Secret: _setting.Secret,
      IPv6: _setting.IPv6,
      DNS: null,
      NTP: null,
      Sniffer: null,
      TLS: null,
      Tun: _setting.Tun,
      Extension: _setting.Extension,
      UnifiedDelay: _setting.UnifiedDelay,
      FindProcessMode: _setting.FindProcessMode,
      Profile: _setting.Profile,
    );
  }

  static Future<void> uninit() async {}

  static Future<void> save() async {
    String filePath = await PathUtils.serviceCoreSettingFilePath();
    const JsonEncoder encoder = JsonEncoder.withIndent('  ');
    final map = _setting.toJson();
    MapHelper.removeNullOrEmpty(map, false, false);
    String content = encoder.convert(map);
    try {
      await File(filePath).writeAsString(content, flush: true);
    } catch (err, stacktrace) {
      Log.w("ClashSettingManager.save exception  $filePath ${err.toString()}");
    }
  }

  static Future<ReturnResult<String>> getPatchContent(
    String profileId,
    bool overwrite,
    Map<String, String>? overwriteRule,
    Map<String, ProfileSettingProxyGroup>? overwriteProxyGroups,
  ) async {
    if (Platform.isIOS || Platform.isMacOS) {
      _setting.Tun?.Stack = ClashTunStack.gvisor.name;
    }
    _setting.DNS?.IPv6 = _setting.IPv6;
    if (_setting.IPv6 == true) {
      _setting.Tun?.Inet6Address = [iNet6Address];
    } else {
      _setting.Tun?.Inet6Address = null;
    }
    if (_setting.Tun?.Inet4Address == null ||
        _setting.Tun!.Inet4Address!.isEmpty ||
        !_setting.Tun!.Inet4Address!.first.contains("/")) {
      _setting.Tun?.Inet4Address = [iNet4Address];
    }
    final parts = _setting.Tun?.Inet4Address!.first.split('/');
    if (parts != null && parts.length == 2) {
      _setting.DNS?.FakeIPRange = "${parts[0]}/16";
    }

    _setting.OverWriteRuleProviders = false;
    _setting.OverWriteRules = false;
    _setting.OverWriteSubRules = false;
    _setting.Rules = null;
    _setting.RuleProviders = null;
    _setting.ProxyGroups = null;
    _setting.Extension?.ProfileStoreSelectedPrefix = profileId;
    if (Platform.isIOS) {
      _setting.FindProcessMode = ClashFindProcessMode.off.name;
    }

    if (overwriteRule != null && overwriteRule.isNotEmpty) {
      _setting.OverWriteRuleProviders = true;
      _setting.OverWriteRules = true;
      _setting.OverWriteSubRules = true;

      List<RuleProvider> newAllProviders = [];
      final allProviders = DiversionTemplateManager.getRuleProviders();
      final templates = DiversionTemplateManager.getRuleTemplates();
      Set<String> targets = {};
      for (var template in templates) {
        final target = overwriteRule[template.name];
        if (target != null && target.isNotEmpty) {
          targets.add(target);
          _setting.Rules ??= [];
          final providers = allProviders.where((ele) {
            return template.getProviders().contains(ele.name);
          });
          newAllProviders.addAll(providers);
          for (var rule in template.rules) {
            String ruleWithTarget = "";
            if (rule.endsWith(",NO-RESOLVE")) {
              ruleWithTarget =
                  "${rule.substring(0, rule.length - ",NO-RESOLVE".length)},$target,NO-RESOLVE";
            } else {
              ruleWithTarget = "$rule,$target";
            }

            if (!_setting.Rules!.contains(ruleWithTarget)) {
              _setting.Rules!.add(ruleWithTarget);
            }
          }
        }
      }
      if (newAllProviders.isNotEmpty) {
        _setting.RuleProviders ??= {};
        for (var provider in newAllProviders) {
          _setting.RuleProviders![provider.name] = provider.toJsonNoName();
        }
      }
      if (overwriteProxyGroups != null && overwriteProxyGroups.isNotEmpty) {
        _setting.OverWriteProxyGroups = true;
        final pgTemplates = DiversionTemplateManager.getProxyGroupTemplates();
        _setting.ProxyGroups ??= [];
        for (var template in pgTemplates) {
          final pg = overwriteProxyGroups[template.name];
          if (pg == null) {
            return ReturnResult(
              error: ReturnResultError(
                "${t.meta.proxyGroups} [${template.name}]: not exist",
              ),
            );
          }
          if (pg.proxies.isEmpty) {
            return ReturnResult(
              error: ReturnResultError(
                "${t.meta.proxyGroups} [${template.name}]->[${t.meta.proxyNodeList}] is empty",
              ),
            );
          }
          var newTemplate = template.clone();
          newTemplate.proxies = pg.proxies;
          _setting.ProxyGroups!.add(newTemplate.toJson());
        }
      }
    }
    if (overwrite) {
      final map = _setting.toJson();
      MapHelper.removeNullOrEmpty(map, true, true);

      const JsonEncoder encoder = JsonEncoder.withIndent('  ');
      String content = encoder.convert(map);
      return ReturnResult(data: content);
    }
    return ReturnResult(data: getPatchFinalContent());
  }

  static String getPatchFinalContent() {
    final setting = defaultConfigNoOverwrite();
    final map = setting.toJson();
    MapHelper.removeNullOrEmpty(map, true, true);
    const JsonEncoder encoder = JsonEncoder.withIndent('  ');
    String content = encoder.convert(map);
    return content;
  }

  static Future<ReturnResultError?> saveCorePatchFinal(
    String profileId,
    bool overwrite,
    Map<String, String>? overwriteRule,
    Map<String, ProfileSettingProxyGroup>? overwriteProxyGroups,
  ) async {
    final result = await getPatchContent(
      profileId,
      overwrite,
      overwriteRule,
      overwriteProxyGroups,
    );
    if (result.error != null) {
      return result.error;
    }
    String filePath = await PathUtils.serviceCorePatchFinalPath();
    try {
      await File(filePath).writeAsString(result.data!, flush: true);
    } catch (err, stacktrace) {
      return ReturnResultError(err.toString());
    }
    return null;
  }

  static Future<void> load() async {
    String filePath = await PathUtils.serviceCoreSettingFilePath();
    var file = File(filePath);
    bool exists = await file.exists();
    if (exists) {
      try {
        String content = await file.readAsString();
        if (content.isNotEmpty) {
          await _load(content);
        }
      } catch (err, stacktrace) {
        Log.w("ClashSettingManager.load exception ${err.toString()} ");
      }
    } else {
      await save();
    }
    await _initFixed();
  }

  static Future<void> _load(String content) async {
    late RawConfig setting;
    try {
      var config = jsonDecode(content);
      setting = RawConfig.fromJson(config);
    } catch (err, stacktrace) {
      Log.w("ClashSettingManager.load exception ${err.toString()} ");
      _setting = defaultConfig();
      await save();
      return;
    }
    _setting = setting;
    _setting.MixedPort ??= 7890;
    _setting.DNS ??= defaultDNS();
    _setting.NTP ??= defaultNTP();
    _setting.Tun ??= defaultTun();

    _setting.Sniffer ??= defaultSniffer();
    _setting.TLS ??= defaultTLS();
    _setting.Extension ??= defaultExtension();
    if (_setting.Extension?.Tun.perApp.PackageIds != null) {
      _setting.Extension?.Tun.perApp.PackageIds!.removeWhere(
        (element) => element == AppUtils.getId(),
      );
    }

    if (_setting.Extension?.Ruleset.AsnUrl ==
        "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/refs/heads/meta/geo/asn") {
      _setting.Extension?.Ruleset.AsnUrl =
          "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/refs/heads/meta/asn";
      await save();
    }
  }

  static Future<void> _initFixed() async {
    if (_setting.Secret == null || _setting.Secret!.isEmpty) {
      _setting.Secret = await getSecretFromDid();
    }
    _setting.UnifiedDelay = true;
    _setting.ExternalUI = "";
    _setting.ExternalUIName = "";
    _setting.ExternalUIURL = "";
    _setting.ExternalControllerCors = null;
    _setting.Tun?.Device = AppUtils.getName();
    _setting.Tun?.AutoRedirect = Platform.isLinux;
    _setting.Tun?.AutoRoute = !Platform.isAndroid;
    _setting.Tun?.AutoDetectInterface = Platform.isWindows || Platform.isLinux;
    _setting.Profile = RawProfile.by(StoreSelected: true, StoreFakeIP: true);
    _setting.Extension?.RuntimeProfileSavePath =
        await PathUtils.serviceCoreRuntimeProfileFilePath();
  }

  static Future<ReturnResultError?> setConfigsMode(
    ClashConfigsMode mode,
  ) async {
    _setting.Mode = mode.name;
    await save();
    for (var callback in onEventModeChanged) {
      callback();
    }

    bool run = await VPNService.getStarted();
    if (!run) {
      return null;
    }
    return await ClashHttpApi.setConfigsMode(mode.name);
  }

  static ClashConfigsMode getConfigsMode() {
    for (var i = 0; i <= ClashConfigsMode.direct.index; ++i) {
      ClashConfigsMode type = ClashConfigsMode.values[i];
      if (type.name == _setting.Mode) {
        return type;
      }
    }

    return ClashConfigsMode.rule;
  }

  static RawConfig getConfig() {
    return _setting;
  }

  static Future<void> reset() async {
    _setting = defaultConfig();
    await _initFixed();
  }

  static int getControlPort() {
    final parts = _setting.ExternalController?.split(':');
    if (parts?.length == 2) {
      return int.tryParse(parts![1]) ?? 0;
    }
    return 0;
  }

  static int getMixedPort() {
    return _setting.MixedPort ?? 7890;
  }
}

class _BundledGeoAsset {
  const _BundledGeoAsset({required this.sha256, required this.size});

  final String sha256;
  final int size;
}
