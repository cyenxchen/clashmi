// ignore_for_file: empty_catches, no_leading_underscores_for_local_identifiers

import 'dart:convert';
import 'dart:io';

import 'package:clashmi/app/local_services/vpn_service.dart';
import 'package:clashmi/app/modules/remote_config.dart';
import 'package:clashmi/app/modules/remote_config_manager.dart';
import 'package:clashmi/app/runtime/return_result.dart';
import 'package:clashmi/app/utils/app_url_utils.dart';
import 'package:clashmi/app/utils/http_utils.dart';
import 'package:clashmi/app/utils/log.dart';
import 'package:clashmi/app/utils/url_launcher_utils.dart';
import 'package:tuple/tuple.dart';

class AutoupdateItem {
  String platform = "";
  List<String> channels = [];
  List<String> abis = [];
  String version = "";
  String url = "";
  String sha256 = "";
  String fileName = "";
  List<String> updateChannel = []; //stable, beta

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) {
      return;
    }
    platform = map["platform"] ?? "";
    var _channels = map["channels"] ?? [];
    for (var i in _channels) {
      channels.add(i as String);
    }
    var _abis = map["abis"] ?? [];
    for (var i in _abis) {
      abis.add(i as String);
    }
    version = map["version"] ?? "";
    url = map["url"] ?? "";
    sha256 = map["sha256"] ?? "";
    fileName = map["file_name"] ?? "";
    var _versionChannel = map["version_channel"] ?? [];
    for (var i in _versionChannel) {
      updateChannel.add(i as String);
    }
  }

  static List<AutoupdateItem> fromGithubReleaseJson(
    Map<String, dynamic> release,
  ) {
    final tagName = release["tag_name"]?.toString() ?? "";
    final version = _normalizeGithubTagVersion(tagName);
    final prerelease = release["prerelease"] == true;
    final productionTag = _isProductionGithubTag(tagName);
    if (!prerelease && !productionTag) {
      Log.i("AutoupdateItem skipped non-production GitHub tag $tagName");
      return [];
    }
    final updateChannel = prerelease ? "beta" : "stable";
    final assets = release["assets"];
    if (version.isEmpty || !_isComparableVersion(version) || assets is! List) {
      if (version.isNotEmpty && !_isComparableVersion(version)) {
        Log.i("AutoupdateItem skipped non-comparable GitHub tag $tagName");
      }
      return [];
    }

    final items = <AutoupdateItem>[];
    for (var asset in assets) {
      if (asset is! Map<String, dynamic>) {
        continue;
      }
      final item = _fromGithubAssetJson(asset, version, updateChannel);
      if (item != null) {
        items.add(item);
      }
    }
    return items;
  }

  static String _normalizeGithubTagVersion(String tagName) {
    var version = tagName.trim();
    if (version.startsWith("v") || version.startsWith("V")) {
      version = version.substring(1);
    }
    final buildParts = version.split("+");
    if (buildParts.length == 2 && buildParts[1].isNotEmpty) {
      version = "${buildParts[0]}.${buildParts[1]}";
    }
    final versionParts = version.split(".");
    if (versionParts.length == 3) {
      version = "$version.0";
    }
    return version;
  }

  static bool _isProductionGithubTag(String tagName) {
    final version = tagName.trim();
    return RegExp(r"^[vV]?\d+\.\d+\.\d+(?:[.+]\d+)?$").hasMatch(version);
  }

  static bool _isComparableVersion(String version) {
    return RegExp(r"^\d+(?:\.\d+)*$").hasMatch(version);
  }

  static AutoupdateItem? _fromGithubAssetJson(
    Map<String, dynamic> asset,
    String version,
    String updateChannel,
  ) {
    final name = asset["name"]?.toString() ?? "";
    final url = asset["browser_download_url"]?.toString() ?? "";
    if (name.isEmpty || url.isEmpty) {
      return null;
    }
    if (name.toLowerCase().endsWith(".appimage")) {
      Log.i("AutoupdateItem skipped unsupported AppImage asset $name");
      return null;
    }

    final platform = _platformFromAssetName(name);
    if (platform.isEmpty) {
      return null;
    }

    final item = AutoupdateItem()
      ..platform = platform
      ..channels = _channelsFromAssetName(name, platform)
      ..abis = _abisFromAssetName(name)
      ..version = version
      ..url = url
      ..fileName = name
      ..updateChannel = [updateChannel];

    final digest = asset["digest"]?.toString() ?? "";
    const sha256Prefix = "sha256:";
    if (digest.startsWith(sha256Prefix)) {
      item.sha256 = digest.substring(sha256Prefix.length);
    }

    return item;
  }

  static String _platformFromAssetName(String name) {
    final lowerName = name.toLowerCase();
    if (lowerName.endsWith(".apk")) {
      return "android";
    }
    if (lowerName.endsWith(".dmg")) {
      return "macos";
    }
    if (lowerName.endsWith(".exe")) {
      return "windows";
    }
    if (lowerName.endsWith(".deb") || lowerName.endsWith(".rpm")) {
      return "linux";
    }
    return "";
  }

  static List<String> _channelsFromAssetName(String name, String platform) {
    if (platform != "linux") {
      return ["*"];
    }

    final lowerName = name.toLowerCase();
    if (lowerName.endsWith(".deb")) {
      return ["deb", "linux-deb", "linux_deb"];
    }
    if (lowerName.endsWith(".rpm")) {
      return ["rpm", "linux-rpm", "linux_rpm"];
    }
    return ["linux"];
  }

  static List<String> _abisFromAssetName(String name) {
    final lowerName = name.toLowerCase();
    if (lowerName.contains("arm64-v8a")) {
      return ["arm64-v8a"];
    }
    if (lowerName.contains("armeabi-v7a")) {
      return ["armeabi-v7a"];
    }
    if (lowerName.contains("x86_64")) {
      return ["x86_64"];
    }
    if (lowerName.contains("universal")) {
      return ["*"];
    }
    return [];
  }
}

abstract final class AutoupdateUtils {
  static const int _githubReleasesPageSize = 100;

  static Future<ReturnResult<List<AutoupdateItem>>> getAutoupdate(
    bool withQueryParams,
  ) async {
    String url = RemoteConfigManager.getConfig().autoUpdate;
    final githubReleasesApi = isGithubReleasesApiUrl(url);
    if (withQueryParams && shouldAppendSignedQueryParams(url)) {
      String queryParams = await AppUrlUtils.getQueryParamsForUrl(bodyLen: 1);
      url = UrlLauncherUtils.reorganizationUrl(url, queryParams) ?? url;
    }

    List<int?> ports = await VPNService.getPortsByPrefer(false);
    if (githubReleasesApi) {
      return _getGithubReleaseAutoupdate(url, ports);
    }

    final response = await _httpGetFirstOk(url, ports);
    List<AutoupdateItem> items = [];
    if (response.error != null) {
      return ReturnResult(error: response.error);
    }
    try {
      if (response.data!.item2.isNotEmpty) {
        var decodedResponse = jsonDecode(response.data!.item2);
        items.addAll(parseAutoupdateItems(decodedResponse));
        Log.i(
          "AutoupdateUtils getAutoupdate parsed ${items.length} items from $url",
        );
      }
    } catch (err, _) {
      Log.i('AutoupdateUtils getAutoupdate exception ${err.toString()}');
    }
    return ReturnResult(data: items);
  }

  static bool isGithubReleasesApiUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.toLowerCase() != "api.github.com") {
      return false;
    }
    return RegExp(r"^/repos/[^/]+/[^/]+/releases/?$").hasMatch(uri.path);
  }

  static bool shouldAppendSignedQueryParams(String url) {
    return !isGithubReleasesApiUrl(url);
  }

  static String githubReleasesPageUrl(String url, int page) {
    final uri = Uri.parse(url);
    final queryParameters = Map<String, String>.from(uri.queryParameters)
      ..["per_page"] = _githubReleasesPageSize.toString()
      ..["page"] = page.toString();
    return uri.replace(queryParameters: queryParameters).toString();
  }

  static Future<ReturnResult<List<AutoupdateItem>>> _getGithubReleaseAutoupdate(
    String url,
    List<int?> ports,
  ) async {
    final items = <AutoupdateItem>[];
    var fetchedPages = 0;
    for (var page = 1; ; page++) {
      final pageUrl = githubReleasesPageUrl(url, page);
      final response = await _httpGetFirstOk(
        pageUrl,
        ports,
        headers: {HttpHeaders.acceptHeader: "application/vnd.github+json"},
      );
      if (response.error != null) {
        return ReturnResult(error: response.error);
      }
      try {
        final decodedResponse = jsonDecode(response.data?.item2 ?? "");
        if (decodedResponse is! List) {
          Log.i("AutoupdateUtils GitHub releases page $page is not a list");
          break;
        }
        fetchedPages = page;
        items.addAll(parseAutoupdateItems(decodedResponse));
        if (decodedResponse.length < _githubReleasesPageSize) {
          break;
        }
      } catch (err, _) {
        Log.i(
          "AutoupdateUtils GitHub releases page $page parse exception ${err.toString()}",
        );
        break;
      }
    }
    Log.i(
      "AutoupdateUtils getAutoupdate parsed ${items.length} items from $url across $fetchedPages GitHub release pages",
    );
    return ReturnResult(data: items);
  }

  static Future<ReturnResult<Tuple2<int, String>>> _httpGetFirstOk(
    String url,
    List<int?> ports, {
    Map<String, String>? headers,
  }) async {
    late ReturnResult<Tuple2<int, String>> response;
    for (var port in ports) {
      response = await HttpUtils.httpGetRequest(
        url,
        port,
        headers,
        const Duration(seconds: 10),
        null,
        null,
      );
      if (response.error == null) {
        break;
      }
    }
    return response;
  }

  static List<AutoupdateItem> parseAutoupdateItems(
    dynamic decodedResponse, {
    String? operatingSystem,
  }) {
    final items = <AutoupdateItem>[];
    if (decodedResponse is List) {
      for (var itemJson in decodedResponse) {
        items.addAll(_parseAutoupdateItem(itemJson));
      }
    } else {
      items.addAll(_parseAutoupdateItem(decodedResponse));
    }
    final targetPlatform = operatingSystem ?? Platform.operatingSystem;
    return items.where((item) => item.platform == targetPlatform).toList();
  }

  static List<AutoupdateItem> _parseAutoupdateItem(dynamic itemJson) {
    if (itemJson is! Map<String, dynamic>) {
      return [];
    }
    if (itemJson.containsKey("tag_name") && itemJson.containsKey("assets")) {
      return AutoupdateItem.fromGithubReleaseJson(itemJson);
    }

    AutoupdateItem item = AutoupdateItem();
    item.fromJson(itemJson);
    return [item];
  }

  static Future<ReturnResult<RemoteConfig>> getRemoteConfig() async {
    RemoteConfig rc = RemoteConfig();
    String url = RemoteConfigManager.getConfig().config;
    late ReturnResult<Tuple2<int, String>> response;
    List<int?> ports = await VPNService.getPortsByPrefer(true);
    for (var port in ports) {
      response = await HttpUtils.httpGetRequest(
        url,
        port,
        null,
        const Duration(seconds: 10),
        null,
        null,
      );
      if (response.error == null) {
        break;
      }
    }

    if (response.error != null) {
      return ReturnResult(error: response.error);
    }
    try {
      if (response.data!.item2.isNotEmpty) {
        var decodedResponse = jsonDecode(response.data!.item2);
        rc.fromJson(decodedResponse);
      }
    } catch (err, _) {
      Log.i('AutoupdateUtils getRemoteConfig exception ${err.toString()}');
    }
    return ReturnResult(data: rc);
  }
}
