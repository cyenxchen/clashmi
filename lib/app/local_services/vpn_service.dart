// ignore_for_file: unused_catch_stack, empty_catches

import 'dart:convert';
import 'dart:io';

import 'package:clashmi/app/modules/clash_setting_manager.dart';
import 'package:clashmi/app/modules/profile_manager.dart';
import 'package:clashmi/app/modules/profile_patch_manager.dart';
import 'package:clashmi/app/modules/setting_manager.dart';
import 'package:clashmi/app/runtime/return_result.dart';
import 'package:clashmi/app/utils/app_args.dart';
import 'package:clashmi/app/utils/app_utils.dart';
import 'package:clashmi/app/utils/did.dart';
import 'package:clashmi/app/utils/error_reporter_utils.dart';
import 'package:clashmi/app/utils/file_utils.dart';
import 'package:clashmi/app/utils/install_referrer_utils.dart';
import 'package:clashmi/app/utils/log.dart';
import 'package:clashmi/app/utils/network_utils.dart';
import 'package:clashmi/app/utils/path_utils.dart';
import 'package:clashmi/app/utils/platform_utils.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:clashmi_vpn_service/proxy_manager.dart';
import 'package:clashmi_vpn_service/state.dart';
import 'package:clashmi_vpn_service/vpn_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_writer/yaml_writer.dart';

class VPNServiceSetServerOptions {
  String disabledServerError = "";
  String invalidServerError = "";
  String expiredServerError = "";
  Set<String> allOutboundsTags = {};
}

class VPNService {
  static const localhost = "127.0.0.1";
  static bool _runAsAdmin = false;
  static final bool _systemExtension = true;
  static int? _profileMixedPort;
  static List<String> _abis = [];
  static final List<
    void Function(FlutterVpnServiceState state, Map<String, String> params)
  >
  onEventStateChanged = [];

  static Future<void> initABI() async {
    if (Platform.isAndroid) {
      String abisAll = await FlutterVpnService.getABIs();
      _abis = abisAll.replaceAll("[", "").replaceAll("]", "").split(",");
    }
  }

  static Future<void> init() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    if (Platform.isWindows) {
      _runAsAdmin = await FlutterVpnService.isRunAsAdmin();
      if (_runAsAdmin) {
        FlutterVpnService.firewallAddApp(
          Platform.resolvedExecutable,
          PathUtils.getExeName(),
        );
        FlutterVpnService.firewallAddApp(
          PathUtils.serviceExePath(),
          PathUtils.serviceExeName(),
        );
      }
    }

    launchAtStartup.setup(
      appName: packageInfo.appName,
      appPath: Platform.resolvedExecutable,
      args: [AppArgs.launchStartup],
    );

    FlutterVpnService.onStateChanged((
      FlutterVpnServiceState state,
      Map<String, String> params,
    ) async {
      if (getSupportSystemProxy()) {
        if (state == FlutterVpnServiceState.disconnected) {
          bool enable = await getSystemProxyEnable();
          if (enable) {
            await FlutterVpnService.cleanSystemProxy();
          }
        }
      }

      for (var callback in onEventStateChanged) {
        callback(state, params);
      }
    });

    final profile = ProfileManager.getCurrent();
    if (profile != null) {
      final prepareResult = await ProfileManager.prepare(profile);
      if (prepareResult == null) {
        await _prepareConfig(profile);
      }
    }

    if (Platform.isWindows) {
      await stop();
    }
  }

  static Future<void> uninit() async {
    if (PlatformUtils.isPC()) {
      await stop();
    }
  }

  static List<String> getABIs() {
    return _abis;
  }

  static ReturnResultError? convertErr(VpnServiceResultError? err) {
    if (err == null) {
      return null;
    }
    return ReturnResultError(err.message);
  }

  static String durationToString(Duration? duration) {
    if (duration == null) {
      return "";
    }
    var microseconds = duration.inMicroseconds;
    var sign = "";
    var negative = microseconds < 0;

    var hours = microseconds ~/ Duration.microsecondsPerHour;
    microseconds = microseconds.remainder(Duration.microsecondsPerHour);

    // Correcting for being negative after first division, instead of before,
    // to avoid negating min-int, -(2^31-1), of a native int64.
    if (negative) {
      hours = 0 - hours; // Not using `-hours` to avoid creating -0.0 on web.
      microseconds = 0 - microseconds;
      sign = "-";
    }

    var minutes = microseconds ~/ Duration.microsecondsPerMinute;
    microseconds = microseconds.remainder(Duration.microsecondsPerMinute);

    var minutesPadding = minutes < 10 ? "0" : "";

    var seconds = microseconds ~/ Duration.microsecondsPerSecond;
    microseconds = microseconds.remainder(Duration.microsecondsPerSecond);

    var secondsPadding = seconds < 10 ? "0" : "";

    return "$sign$hours:"
        "$minutesPadding$minutes:"
        "$secondsPadding$seconds";
  }

  static Future<bool> _prepareConfig(ProfileSetting profile) async {
    final corePath = await ProfileManager.getProfilePath(profile.id);
    final patch = ProfilePatchManager.getProfilePatch(profile.patch);
    final setting = ClashSettingManager.getConfig();
    final appSetting = SettingManager.getConfig();
    final controlPort = ClashSettingManager.getControlPort();

    final overwriteFinal = patch.appliesBuiltInOverwrite;
    final (patchedCorePath, corePatchPath) = await _getCorePaths(
      corePath,
      patch,
    );
    final profileMixedPort = await _getProfileMixedPort(
      patchedCorePath,
      patch,
      corePatchPath,
    );
    final mixedPort = profileMixedPort ?? ClashSettingManager.getMixedPort();
    final patchError = await ClashSettingManager.saveCorePatchFinal(
      profile,
      patch,
      corePath: patchedCorePath,
      corePatchPath: corePatchPath,
      preserveMixedPort: profileMixedPort != null,
    );
    if (patchError != null) {
      throw StateError(patchError.message);
    }

    final excludePorts = [controlPort, if (mixedPort > 0) mixedPort];

    String name = AppUtils.getName();
    String vpnName = name;
    String configFilePath = await PathUtils.serviceConfigFilePath();
    String installReferrer = await InstallReferrerUtils.getString();

    VpnServiceConfig config = VpnServiceConfig();
    config.control_port = controlPort;
    config.base_dir = await PathUtils.profileDir();
    config.work_dir = PathUtils.appAssetsDir();
    config.cache_dir = await PathUtils.cacheDir();
    config.core_path = await _prepareRuntimeCoreProfile(patchedCorePath);
    if (corePatchPath.isNotEmpty) {
      config.core_path_patch = corePatchPath;
    }

    config.core_path_patch_final = await PathUtils.serviceCorePatchFinalPath();
    config.log_path = await PathUtils.serviceLogFilePath();
    config.err_path = await PathUtils.serviceStdErrorFilePath();
    config.id = await Did.getDid();
    config.version = AppUtils.getBuildinVersion();
    config.name = name;
    config.secret = ClashSettingManager.getConfig().Secret!;
    config.install_refer = installReferrer;
    config.prepare =
        (overwriteFinal &&
            setting.Tun?.OverWrite == true &&
            setting.Tun?.Enable == true) ||
        !overwriteFinal;
    config.wake_lock = appSetting.wakeLock;
    config.auto_connect_at_boot = appSetting.autoConnectAtBoot;
    config.enable_ipv6 = setting.IPv6 == true;
    Log.i(
      "VPNService.prepareConfig ipv6=${setting.IPv6} enable_ipv6=${config.enable_ipv6}",
    );
    var bundleIdentifier = AppUtils.getBundleId(_systemExtension);
    var uiServerAddress = name;
    var uiLocalizedDescription = vpnName;
    if (Platform.isMacOS) {
      if (_systemExtension) {
        uiServerAddress = "$uiServerAddress (system)";
        uiLocalizedDescription = "$uiLocalizedDescription (system)";
      }
    }
    await FlutterVpnService.prepareConfig(
      config: config,
      tunnelServicePath: PathUtils.serviceExePath(),
      configFilePath: configFilePath,
      systemExtension: _systemExtension,
      bundleIdentifier: bundleIdentifier,
      controlKind: AppUtils.getControlKind(),
      uiServerAddress: uiServerAddress,
      uiLocalizedDescription: uiLocalizedDescription,
      excludePorts: excludePorts,
    );
    Log.i(
      "VPNService.prepareConfig ok core=${config.core_path} finalPatch=${config.core_path_patch_final}",
    );
    File confFile = File(configFilePath);
    bool reinstall = false;
    if (Platform.isIOS || Platform.isMacOS) {
      bool exists = await confFile.exists();
      if (exists) {
        try {
          String content = await confFile.readAsString();
          if (content.isNotEmpty) {
            var configJson = jsonDecode(content);
            VpnServiceConfig configOld = VpnServiceConfig();
            configOld.fromJson(configJson);
            if (config.install_refer != configOld.install_refer) {
              reinstall = true;
            }
          }
        } catch (err, stacktrace) {
          Log.w("VPNService.prepareConfig exception ${err.toString()}");
        }
      }
    }

    const JsonEncoder encoder = JsonEncoder.withIndent('  ');
    String content = encoder.convert(config);
    try {
      await confFile.writeAsString(content, flush: true);
    } catch (err) {
      ErrorReporterUtils.tryReportNoSpace(err.toString());
      rethrow;
    }
    _profileMixedPort = profileMixedPort;

    if (Platform.isMacOS) {
      ProxyManager().setExcludeDevices({vpnName});
    }

    return reinstall;
  }

  static Future<(String, String)> _getCorePaths(
    String corePath,
    ProfilePatchSetting patch,
  ) async {
    if (patch.type == ProfilePatchFileType.yaml) {
      return (
        corePath,
        await ProfilePatchManager.getProfilePatchPath(patch.id),
      );
    }
    return (
      await ProfilePatchManager.getProfilePatchScriptPath(corePath, patch.id),
      '',
    );
  }

  static Future<ReturnResult<String>> getFinalPatchPreview() async {
    final profile = ProfileManager.getCurrent();
    final patch = ProfilePatchManager.getProfilePatch(profile?.patch ?? '');
    if (profile == null) {
      return ClashSettingManager.getPatchContent(null, patch);
    }
    final corePath = await ProfileManager.getProfilePath(profile.id);
    final corePatchPath = patch.type == ProfilePatchFileType.yaml
        ? await ProfilePatchManager.getProfilePatchPath(patch.id)
        : '';
    final profileMixedPort = await _getProfileMixedPort(
      corePath,
      patch,
      corePatchPath,
    );
    return ClashSettingManager.getPatchContent(
      profile,
      patch,
      corePath: corePath,
      corePatchPath: corePatchPath,
      preserveMixedPort: profileMixedPort != null,
    );
  }

  static Future<int?> _getProfileMixedPort(
    String corePath,
    ProfilePatchSetting patch,
    String corePatchPath,
  ) async {
    if (patch.id != kProfilePatchBuildinNoOverwrite &&
        patch.appendPatchBuildin != kProfilePatchBuildinNoOverwrite) {
      return null;
    }
    try {
      if (corePatchPath.isNotEmpty) {
        final patchFile = File(corePatchPath);
        if (await patchFile.exists()) {
          final doc = loadYaml(await patchFile.readAsString());
          if (doc is YamlMap && doc.containsKey('mixed-port')) {
            final port = doc['mixed-port'];
            return port is int ? port : null;
          }
        }
      }
      final doc = loadYaml(await File(corePath).readAsString());
      final port = doc is YamlMap ? doc['mixed-port'] : null;
      return port is int ? port : null;
    } on YamlException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  static Future<String> _prepareRuntimeCoreProfile(String corePath) async {
    if (!Platform.isAndroid) {
      return corePath;
    }

    try {
      final file = File(corePath);
      if (!await file.exists()) {
        Log.w("VPNService.prepareRuntimeCoreProfile missing core=$corePath");
        return corePath;
      }

      final content = await file.readAsString();
      if (content.isEmpty) {
        Log.w("VPNService.prepareRuntimeCoreProfile empty core=$corePath");
        return corePath;
      }

      final doc = loadYaml(content);
      if (doc is! YamlMap) {
        Log.w(
          "VPNService.prepareRuntimeCoreProfile invalid yaml core=$corePath",
        );
        return corePath;
      }

      final data = jsonDecode(jsonEncode(doc));
      if (data is! Map<String, dynamic>) {
        Log.w(
          "VPNService.prepareRuntimeCoreProfile invalid map core=$corePath",
        );
        return corePath;
      }

      final proxyProviders = data["proxy-providers"];
      if (proxyProviders is! Map) {
        return corePath;
      }

      final providerProxy = _defaultProxyProviderProxy(data);
      if (providerProxy == null) {
        Log.i(
          "VPNService.prepareRuntimeCoreProfile no default proxy-provider proxy core=$corePath",
        );
        return corePath;
      }

      var updated = 0;
      for (final entry in proxyProviders.entries) {
        final provider = entry.value;
        if (provider is Map &&
            provider["type"] == "http" &&
            (provider["proxy"] == null ||
                provider["proxy"].toString().isEmpty)) {
          provider["proxy"] = providerProxy;
          updated++;
        }
      }

      if (updated == 0) {
        return corePath;
      }

      final runtimePath = await PathUtils.serviceCoreRuntimeProfileFilePath();
      final value = YamlWriter(allowUnquotedStrings: true).write(data);
      await File(runtimePath).writeAsString(value, flush: true);
      Log.i(
        "VPNService.prepareRuntimeCoreProfile proxyProvidersProxy=$providerProxy count=$updated runtime=$runtimePath",
      );
      return runtimePath;
    } catch (err, stacktrace) {
      Log.w("VPNService.prepareRuntimeCoreProfile exception ${err.toString()}");
      return corePath;
    }
  }

  static String? _defaultProxyProviderProxy(Map<String, dynamic> data) {
    final proxyGroups = data["proxy-groups"];
    if (proxyGroups is! List) {
      return null;
    }

    final candidates = <String>[];
    for (final item in proxyGroups) {
      if (item is! Map) {
        continue;
      }
      final name = item["name"]?.toString();
      final proxies = item["proxies"];
      if (name == null || name.isEmpty || proxies is! List || proxies.isEmpty) {
        continue;
      }
      final hasUsableProxy = proxies.any((proxy) {
        final value = proxy.toString();
        return value != "DIRECT" &&
            value != "REJECT" &&
            value != "REJECT-DROP" &&
            value != "PASS";
      });
      if (hasUsableProxy) {
        candidates.add(name);
      }
    }

    if (candidates.isEmpty) {
      return null;
    }

    return candidates.firstWhere(
      (name) => name.toLowerCase().contains("proxy"),
      orElse: () => candidates.first,
    );
  }

  static Future<ReturnResultError?> install() async {
    VpnServiceResultError? err = await FlutterVpnService.installService();
    if (err != null) {
      Log.w("VPNService.install err ${err.message.toString()}");
    }
    return convertErr(err);
  }

  static Future<ReturnResultError?> uninstall() async {
    VpnServiceResultError? err = await FlutterVpnService.uninstallService();
    if (err != null) {
      Log.w("VPNService.uninstall err ${err.message.toString()}");
    }
    return convertErr(err);
  }

  static Future<ReturnResultError?> restart(Duration timeout) async {
    final profile = ProfileManager.getCurrent();
    if (profile == null) {
      return ReturnResultError("current profile is empty");
    }
    final prepareResult = await ProfileManager.prepare(profile);
    if (prepareResult != null) {
      return prepareResult;
    }
    var started = await getStarted();
    if (!started) {
      return null;
    }
    final enable = await getSystemProxyEnable();
    try {
      bool reinstall = await _prepareConfig(profile);
      if (reinstall) {
        await uninstall();
      }
    } catch (err, stacktrace) {
      return ReturnResultError(err.toString());
    }
    var setting = SettingManager.getConfig();
    if (Platform.isWindows && _runAsAdmin) {
      final controlPort = ClashSettingManager.getControlPort();
      final mixedPort = getMixedPort();
      final ports = [controlPort, if (mixedPort > 0) mixedPort];

      FlutterVpnService.firewallAddPorts(ports, PathUtils.serviceExeName());
    }
    if (Platform.isIOS || Platform.isMacOS) {
      await FlutterVpnService.setAlwaysOn(false);
    }
    VpnServiceWaitResult result = await FlutterVpnService.restart(timeout);
    if (result.type == VpnServiceWaitType.timeout) {
      await stop();
      return ReturnResultError("service restart timeout");
    }
    if (result.type != VpnServiceWaitType.done) {
      Log.w(
        "VPNService.restart err ${result.type}:${result.err!.message.toString()}",
      );

      await stop();
      return convertErr(result.err);
    }
    String errorPath = await PathUtils.serviceStdErrorFilePath();
    String? content = await FileUtils.readAndDelete(errorPath);
    if (content != null && content.isNotEmpty) {
      await stop();
      return ReturnResultError(content);
    }
    if (Platform.isIOS || Platform.isMacOS) {
      if (setting.alwayOn) {
        await FlutterVpnService.setAlwaysOn(setting.alwayOn);
      }
    }

    if (enable) {
      if (getMixedPort() == 0) {
        await FlutterVpnService.cleanSystemProxy();
      } else {
        await setSystemProxy(true);
      }
    }
    return null;
  }

  static Future<ReturnResultError?> start(Duration timeout) async {
    final profile = ProfileManager.getCurrent();
    if (profile == null) {
      return ReturnResultError("current profile is empty");
    }
    final prepareResult = await ProfileManager.prepare(profile);
    if (prepareResult != null) {
      return prepareResult;
    }
    try {
      bool reinstall = await _prepareConfig(profile);
      if (reinstall) {
        await uninstall();
      }
    } catch (err, stacktrace) {
      return ReturnResultError(err.toString());
    }
    var setting = SettingManager.getConfig();
    if (Platform.isWindows && _runAsAdmin) {
      final controlPort = ClashSettingManager.getControlPort();
      final mixedPort = getMixedPort();
      final ports = [controlPort, if (mixedPort > 0) mixedPort];

      FlutterVpnService.firewallAddPorts(ports, PathUtils.serviceExeName());
    }
    VpnServiceWaitResult result = await FlutterVpnService.start(timeout);
    if (result.type == VpnServiceWaitType.timeout) {
      await stop();
      return ReturnResultError("service start timeout");
    }

    if (result.err != null) {
      Log.w("VPNService.start err ${result.err!.message.toString()}");
      await stop();
      return convertErr(result.err);
    }
    String errorPath = await PathUtils.serviceStdErrorFilePath();
    String? content = await FileUtils.readAndDelete(errorPath);
    if (content != null && content.isNotEmpty) {
      await stop();
      return ReturnResultError(content);
    }
    if (Platform.isIOS || Platform.isMacOS) {
      if (setting.alwayOn) {
        await FlutterVpnService.setAlwaysOn(setting.alwayOn);
      }
    }

    if (SettingManager.getConfig().autoSetSystemProxy) {
      await setSystemProxy(true);
    }

    return null;
  }

  static Future<void> stop() async {
    if (Platform.isIOS || Platform.isMacOS) {
      await FlutterVpnService.setAlwaysOn(false);
    }
    await setSystemProxy(false);
    // Do not report the switch as off until Android confirms that native
    // listeners and the TUN interface have actually been released.
    final result = await FlutterVpnService.stop(const Duration(seconds: 30));
    if (result.type != VpnServiceWaitType.done) {
      Log.w(
        "VPNService.stop incomplete ${result.type}:${result.err?.message ?? 'unknown error'}",
      );
    }

    if (Platform.isWindows) {
      await uninstall();
    }
  }

  static bool getSupportSystemProxy() {
    return PlatformUtils.isPC();
  }

  static Future<void> setSystemProxy(bool enable) async {
    if (getSupportSystemProxy()) {
      try {
        final options = await getSystemProxyOptions();
        if (options.port == 0) {
          return;
        }
        if (enable) {
          await FlutterVpnService.setSystemProxy(await getSystemProxyOptions());
        } else {
          if (await getSystemProxyEnable()) {
            await FlutterVpnService.cleanSystemProxy();
          }
        }
      } catch (err) {
        Log.w("VPNService setSystemProxy exception:${err.toString()}");
      }
    }
  }

  static Future<bool> getSystemProxyEnable() async {
    if (!getSupportSystemProxy()) {
      return false;
    }
    final hostOptionsLocal = getSystemProxyOptionsLocalhost();
    bool enable = await FlutterVpnService.getSystemProxyEnable(
      hostOptionsLocal,
    );
    if (!enable) {
      final hostOptionsLan = await getSystemProxyOptionsLan();
      if (hostOptionsLan != null) {
        enable |= await FlutterVpnService.getSystemProxyEnable(hostOptionsLan);
      }
    }

    return enable;
  }

  static bool isRunAsAdmin() {
    return _runAsAdmin;
  }

  static Future<FlutterVpnServiceState> getState() async {
    return await FlutterVpnService.currentState;
  }

  static Future<bool> getStarted() async {
    FlutterVpnServiceState newState = await FlutterVpnService.currentState;
    if (newState == FlutterVpnServiceState.connected) {
      return true;
    }

    return false;
  }

  static int getMixedPort() {
    return _profileMixedPort ?? ClashSettingManager.getMixedPort();
  }

  static Future<List<int?>> getPortsByPrefer(bool preferForward) async {
    final port = await getPort();
    if (port == null) {
      return [null];
    }
    return preferForward ? [port, null] : [null, port];
  }

  static Future<int?> getPort() async {
    final started = await getStarted();
    final mixedPort = getMixedPort();
    return started && mixedPort > 0 ? mixedPort : null;
  }

  static Future<ReturnResultError?> reload(Duration timeout) async {
    return restart(timeout);
  }

  static String getLaunchAtStartupTaskName() {
    return "${AppUtils.getName()} Autorun";
  }

  static Future<ReturnResultError?> setLaunchAtStartup(bool enable) async {
    if (PlatformUtils.isPC()) {
      try {
        if (enable) {
          if (Platform.isWindows) {
            bool admin = isRunAsAdmin();
            await FlutterVpnService.autoStartCreate(
              getLaunchAtStartupTaskName(),
              Platform.resolvedExecutable,
              processArgs: AppArgs.launchStartup,
              runElevated: admin,
            );
            return null;
          }
        } else {
          await FlutterVpnService.autoStartDelete(getLaunchAtStartupTaskName());
          await launchAtStartup.disable();
        }
      } catch (err, stacktrace) {
        return ReturnResultError(err.toString());
      }
    }
    return null;
  }

  static Future<bool> getLaunchAtStartup() async {
    if (PlatformUtils.isPC()) {
      try {
        if (Platform.isWindows) {
          if (await FlutterVpnService.autoStartIsActive(
            getLaunchAtStartupTaskName(),
          )) {
            return true;
          }
        }
        return await launchAtStartup.isEnabled();
      } catch (err, stacktrace) {
        return false;
      }
    }
    return false;
  }

  static ProxyOption getSystemProxyOptionsLocalhost() {
    return ProxyOption(
      localhost,
      getMixedPort(),
      SettingManager.getConfig().systemProxyBypassDomain,
    );
  }

  static Future<ProxyOption?> getSystemProxyOptionsLan() async {
    if (!PlatformUtils.isPC()) {
      return null;
    }

    var host = localhost;
    List<NetInterfacesInfo> interfaces = await NetworkUtils.getInterfaces();
    if (interfaces.length == 1) {
      host = interfaces[0].address;
    } else {
      for (var face in interfaces) {
        if (Platform.isMacOS && face.name.startsWith("en")) {
          host = face.address;
          break;
        }
      }
    }

    return ProxyOption(
      host,
      getMixedPort(),
      SettingManager.getConfig().systemProxyBypassDomain,
    );
  }

  static Future<ProxyOption> getSystemProxyOptions() async {
    final bypassDomain = SettingManager.getConfig().systemProxyBypassDomain;
    final mixedPort = getMixedPort();
    if (Platform.isMacOS) {
      List<NetInterfacesInfo> interfaces = await NetworkUtils.getInterfaces(
        addressType: InternetAddressType.IPv4,
      );

      for (var face in interfaces) {
        if (face.name.startsWith("en")) {
          return ProxyOption(face.address, mixedPort, bypassDomain);
        }
      }
    }
    return ProxyOption(localhost, mixedPort, bypassDomain);
  }
}
