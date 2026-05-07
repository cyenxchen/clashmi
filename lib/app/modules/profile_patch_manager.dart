// ignore_for_file: unused_catch_stack, empty_catches

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ffi' as ffi;

import 'package:clashmi/app/modules/setting_manager.dart';
import 'package:clashmi/app/runtime/return_result.dart';
import 'package:clashmi/app/utils/download_utils.dart';
import 'package:clashmi/app/utils/file_utils.dart';
import 'package:clashmi/app/utils/http_utils.dart';
import 'package:clashmi/app/utils/log.dart';
import 'package:clashmi/app/utils/path_utils.dart';
import 'package:clashmi/i18n/strings.g.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_js/flutter_js.dart';
import 'package:clashmi/app/utils/emoji_utils.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_writer/yaml_writer.dart';

const int kRemarkMaxLength = 32;
const String kProfilePatchBuildinOverwrite = "profile_patch_buildin_overwrite";
const String kProfilePatchBuildinNoOverwrite =
    "profile_patch_buildin_no_overwrite";

enum ProfilePatchFileType {
  yaml(name: "yaml"),
  js(name: "js");

  const ProfilePatchFileType({required this.name});
  final String name;

  static List<String> getTypes() {
    return [yaml.name, js.name];
  }
}

class ProfilePatchSetting {
  ProfilePatchSetting({
    this.id = "",
    this.remark = "",
    this.updateInterval,
    this.update,
    this.url = "",
    this.type = ProfilePatchFileType.yaml,
  });
  String id = "";
  String remark = "";
  Duration? updateInterval;
  DateTime? update;
  String url;
  ProfilePatchFileType type = ProfilePatchFileType.yaml;

  Map<String, dynamic> toJson() => {
    'id': id,
    'remark': remark,
    'update_interval': updateInterval?.inSeconds,
    'update': update.toString(),
    'url': url,
    'type': type.name,
  };
  void fromJson(Map<String, dynamic>? map) {
    if (map == null) {
      return;
    }

    id = map['id'] ?? '';
    remark = map['remark'] ?? '';
    var updateIntervalTime = map['update_interval'];
    if (updateIntervalTime is int) {
      if (updateIntervalTime < 60) {
        updateIntervalTime = 24 * 60;
      }
      updateInterval = Duration(seconds: updateIntervalTime);
    }
    final updateTime = map['update'];
    if (updateTime is String) {
      update = DateTime.tryParse(updateTime);
    }
    url = map['url'] ?? '';
    type = ProfilePatchFileType.values.firstWhere(
      (e) => e.name == map['type'],
      orElse: () => ProfilePatchFileType.yaml,
    );
  }

  String getType() {
    if (id == kProfilePatchBuildinOverwrite ||
        id == kProfilePatchBuildinNoOverwrite) {
      return "Buildin";
    }

    if (url.isNotEmpty) {
      return "URL";
    }
    return "Local";
  }

  bool isRemote() {
    return url.isNotEmpty;
  }

  bool isBuildIn() {
    return id.isEmpty ||
        id == kProfilePatchBuildinOverwrite ||
        id == kProfilePatchBuildinNoOverwrite;
  }

  String getShowName(BuildContext context) {
    final tcontext = Translations.of(context);
    if (id.isEmpty || id == kProfilePatchBuildinOverwrite) {
      return tcontext.profilePatchMode.overwrite;
    }
    if (id == kProfilePatchBuildinNoOverwrite) {
      return tcontext.profilePatchMode.noOverwrite;
    }
    return remark.isEmpty ? id : remark;
  }

  ProfilePatchSetting clone() {
    return ProfilePatchSetting(
      id: id,
      remark: remark,
      updateInterval: updateInterval,
      update: update,
      url: url,
      type: type,
    );
  }
}

class ProfilePatchConfig {
  String _currentId = "";
  List<ProfilePatchSetting> profiles = [];

  Map<String, dynamic> toJson() => {
    'current_id': _currentId,
    'profile_patchs': profiles,
  };

  void fromJson(Map<String, dynamic>? map) {
    if (map == null) {
      return;
    }
    _currentId = map['current_id'] ?? '';
    final p = map['profile_patchs'];
    if (p is List) {
      for (var value in p) {
        ProfilePatchSetting ps = ProfilePatchSetting();
        ps.fromJson(value);
        profiles.add(ps);
      }
    }
  }
}

class ProfilePatchManager {
  static const String yamlExtension = "yaml";
  static const String urlComment = "#url:";

  static final ProfilePatchConfig _config = ProfilePatchConfig();

  static final List<void Function(String)> onEventCurrentChanged = [];
  static final List<void Function(String)> onEventAdd = [];
  static final List<void Function(String)> onEventRemove = [];
  static final List<void Function(String, bool)> onEventUpdate = [];
  static final Set<String> updating = {};
  static bool _saving = false;

  static Future<void> init() async {
    await load();
  }

  static Future<void> uninit() async {}
  static Future<void> reload() async {
    final dir = await PathUtils.profilePatchsDir();
    List<String> ids = [];
    List<String> idsToDelete = [];
    for (var profile in _config.profiles) {
      ids.add(profile.id);
    }
    _config._currentId = kProfilePatchBuildinOverwrite;
    _config.profiles = [];
    await load();
    for (var id in ids) {
      int index = _config.profiles.indexWhere((value) {
        return value.id == id;
      });
      if (index < 0) {
        idsToDelete.add(id);
      }
    }
    for (var id in idsToDelete) {
      final filePath = path.join(dir, id);
      await FileUtils.deletePath(filePath);
    }
  }

  static Future<void> save() async {
    if (_saving) {
      return;
    }
    _saving = true;
    String filePath = await PathUtils.profilePatchsConfigFilePath();
    const JsonEncoder encoder = JsonEncoder.withIndent('  ');
    String content = encoder.convert(_config);
    try {
      await File(filePath).writeAsString(content, flush: true);
    } catch (err, stacktrace) {
      Log.w("ProfilePatchManager.save exception ${err.toString()} ");
    }
    _saving = false;
  }

  static Future<void> load() async {
    String dir = await PathUtils.profilePatchsDir();
    String filePath = await PathUtils.profilePatchsConfigFilePath();
    var file = File(filePath);
    bool exists = await file.exists();
    if (exists) {
      try {
        String content = await file.readAsString();
        if (content.isNotEmpty) {
          var config = jsonDecode(content);
          _config.fromJson(config);
          for (int i = 0; i < _config.profiles.length; ++i) {
            final filePath = path.join(dir, _config.profiles[i].id);
            try {
              if (!await File(filePath).exists()) {
                _config.profiles.removeAt(i);
                --i;
              }
            } catch (err) {
              _config.profiles.removeAt(i);
              --i;
            }
          }
        }
      } catch (err, stacktrace) {
        Log.w("ProfilePatchManager.load exception ${err.toString()} ");
      }
    } else {
      await save();
    }
    Set<String> existProfiles = {};

    var files = FileUtils.recursionFile(
      dir,
      extensionFilter: {".yaml", ".yml", ".js"},
    );
    for (var file in files) {
      existProfiles.add(path.basename(file));
    }
    for (int i = 0; i < _config.profiles.length; ++i) {
      if (!existProfiles.contains(_config.profiles[i].id)) {
        _config.profiles.removeAt(i);
        --i;
      }
    }
    for (var existValue in existProfiles) {
      int index = _config.profiles.indexWhere((value) {
        return value.id == existValue;
      });
      if (index < 0) {
        _config.profiles.add(
          ProfilePatchSetting(
            id: existValue,
            remark: existValue,
            type: path.extension(existValue) == ".js"
                ? ProfilePatchFileType.js
                : ProfilePatchFileType.yaml,
          ),
        );
      }
    }

    if (_config._currentId.isNotEmpty &&
        _config._currentId != kProfilePatchBuildinOverwrite &&
        _config._currentId != kProfilePatchBuildinNoOverwrite) {
      int index = _config.profiles.indexWhere((value) {
        return value.id == _config._currentId;
      });

      if (index < 0) {
        _config._currentId = kProfilePatchBuildinOverwrite;
      }
    }
  }

  static ProfilePatchSetting getBuildinOverwrite() {
    return ProfilePatchSetting(
      id: kProfilePatchBuildinOverwrite,
      type: ProfilePatchFileType.yaml,
    );
  }

  static ProfilePatchSetting getBuildinNoOverwrite() {
    return ProfilePatchSetting(
      id: kProfilePatchBuildinNoOverwrite,
      type: ProfilePatchFileType.yaml,
    );
  }

  static ProfilePatchSetting getCurrent() {
    if (_config._currentId.isEmpty ||
        _config._currentId == kProfilePatchBuildinOverwrite) {
      return ProfilePatchSetting(
        id: kProfilePatchBuildinOverwrite,
        remark: "",
        type: ProfilePatchFileType.yaml,
      );
    }
    if (_config._currentId == kProfilePatchBuildinNoOverwrite) {
      return ProfilePatchSetting(
        id: kProfilePatchBuildinNoOverwrite,
        remark: "",
        type: ProfilePatchFileType.yaml,
      );
    }
    int index = _config.profiles.indexWhere((value) {
      return value.id == _config._currentId;
    });
    if (index < 0) {
      return ProfilePatchSetting(
        id: kProfilePatchBuildinOverwrite,
        remark: "",
        type: ProfilePatchFileType.yaml,
      );
    }
    return _config.profiles[index];
  }

  static Future<ReturnResultError?> prepare(ProfilePatchSetting profile) async {
    String dir = await PathUtils.profilePatchsDir();
    final filePath = path.join(dir, profile.id);
    try {
      if (!await File(filePath).exists()) {
        if (profile.isRemote()) {
          return await update(profile.id);
        }
        return ReturnResultError("file not exist: $filePath");
      }
      return await validFileContentFormat(filePath);
    } catch (err) {
      return ReturnResultError(err.toString());
    }
  }

  static void setCurrent(String id) {
    if (_config._currentId == id) {
      return;
    }
    if (kProfilePatchBuildinOverwrite == id ||
        kProfilePatchBuildinNoOverwrite == id) {
      _config._currentId = id;
      return;
    }
    int index = _config.profiles.indexWhere((value) {
      return value.id == id;
    });
    if (index < 0) {
      return;
    }
    _config._currentId = id;
    for (var event in onEventCurrentChanged) {
      event(id);
    }
  }

  static List<ProfilePatchSetting> getProfiles() {
    return _config.profiles;
  }

  static ProfilePatchSetting getProfilePatch(String id) {
    if (id == kProfilePatchBuildinOverwrite) {
      return ProfilePatchSetting(
        id: kProfilePatchBuildinOverwrite,
        remark: "",
        type: ProfilePatchFileType.yaml,
      );
    }
    if (id == kProfilePatchBuildinNoOverwrite) {
      return ProfilePatchSetting(
        id: kProfilePatchBuildinNoOverwrite,
        remark: "",
        type: ProfilePatchFileType.yaml,
      );
    }

    int index = _config.profiles.indexWhere((value) {
      return value.id == id;
    });
    if (index < 0) {
      return getCurrent();
    }
    return _config.profiles[index];
  }

  static bool existProfilePatch(String id) {
    if (id == kProfilePatchBuildinOverwrite) {
      return true;
    }
    if (id == kProfilePatchBuildinNoOverwrite) {
      return true;
    }

    int index = _config.profiles.indexWhere((value) {
      return value.id == id;
    });
    if (index < 0) {
      return false;
    }
    return true;
  }

  static List<ProfilePatchSetting> getProfilePatchs() {
    return _config.profiles;
  }

  static Future<ReturnResultError?> addLocal(
    String filePath, {
    String remark = "",
    ProfilePatchFileType type = ProfilePatchFileType.yaml,
  }) async {
    final id = type == ProfilePatchFileType.yaml
        ? "${filePath.hashCode}.yaml"
        : "${filePath.hashCode}.js";
    final savePath = path.join(await PathUtils.profilePatchsDir(), id);
    final file = File(filePath);
    if (!await file.exists()) {
      return ReturnResultError("file not exist: $filePath");
    }
    try {
      await file.copy(savePath);
      int index = _config.profiles.indexWhere((value) {
        return value.id == id;
      });
      if (index < 0) {
        _config.profiles.add(
          ProfilePatchSetting(id: id, remark: remark, type: type),
        );
      } else {
        _config.profiles[index] = ProfilePatchSetting(
          id: id,
          remark: remark,
          type: type,
        );
      }

      for (var event in onEventAdd) {
        event(id);
      }

      await save();
      return null;
    } catch (err) {
      return ReturnResultError("addLocalProfile exception: ${err.toString()}");
    }
  }

  static Future<ReturnResultError?> validFileContentFormat(
    String filepath,
  ) async {
    String? content = await FileUtils.readAsStringWithMaxLength(filepath, 100);
    if (content != null) {
      content = content.trimLeft();
      final filename = path.basename(filepath);
      if (content.startsWith("<!DOCTYPE html>") ||
          content.startsWith("<html")) {
        return ReturnResultError(
          "$filename:invalid content format:\n\n$content",
        );
      }
    }
    return null;
  }

  static Future<ReturnResult<String>> addRemote(
    String url, {
    String remark = "",
    ProfilePatchFileType type = ProfilePatchFileType.yaml,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return ReturnResult(error: ReturnResultError("invalid url"));
    }
    final id = type == ProfilePatchFileType.yaml
        ? "${url.hashCode}.yaml"
        : "${url.hashCode}.js";
    final savePath = path.join(await PathUtils.profilePatchsDir(), id);
    final userAgent = SettingManager.getConfig().userAgent();
    final result = await DownloadUtils.downloadWithPort(
      uri,
      savePath,
      userAgent,
      false,
      null,
      timeout: const Duration(seconds: 30),
    );
    if (result.error != null) {
      return ReturnResult(error: result.error);
    }
    if (type == ProfilePatchFileType.yaml) {
      final err = await validFileContentFormat(savePath);
      if (err != null) {
        FileUtils.deletePath(savePath);
        return ReturnResult(error: err);
      }
      await FileUtils.append(savePath, "\n$urlComment$url\n");
    }

    if (remark.isEmpty) {
      final result = await HttpUtils.httpGetTitle(url, userAgent);
      if (result.data == null || result.data!.length > 32) {
        remark = uri.host;
      } else {
        remark = result.data!;
      }
    }

    int index = _config.profiles.indexWhere((value) {
      return value.id == id;
    });
    final profile = ProfilePatchSetting(
      id: id,
      remark: remark,
      updateInterval: const Duration(days: 1),
      update: DateTime.now(),
      url: url,
      type: type,
    );

    if (index < 0) {
      _config.profiles.add(profile);
    } else {
      _config.profiles[index] = profile;
    }

    for (var event in onEventAdd) {
      event(id);
    }

    if (_config._currentId.isEmpty) {
      setCurrent(id);
    }

    await save();
    return ReturnResult(data: id);
  }

  static Future<void> updateAll() async {
    for (var profile in _config.profiles) {
      update(profile.id);
    }
  }

  static Future<ReturnResultError?> update(String id) async {
    if (updating.contains(id)) {
      return null;
    }
    int index = _config.profiles.indexWhere((value) {
      return value.id == id;
    });
    if (index < 0) {
      return null;
    }
    ProfilePatchSetting profile = _config.profiles[index];
    if (!profile.isRemote()) {
      return null;
    }
    final uri = Uri.tryParse(profile.url);
    if (uri == null) {
      return null;
    }
    updating.add(id);
    Future.delayed(const Duration(milliseconds: 10), () async {
      for (var event in onEventUpdate) {
        event(id, false);
      }
    });

    final userAgent = SettingManager.getConfig().userAgent();
    final savePath = path.join(await PathUtils.profilePatchsDir(), id);
    final savePathTmp = "$savePath.tmp";
    final result = await DownloadUtils.downloadWithPort(
      uri,
      savePathTmp,
      userAgent,
      false,
      null,
      timeout: const Duration(seconds: 30),
    );
    profile.update = DateTime.now();
    if (result.error == null) {
      if (profile.type == ProfilePatchFileType.yaml) {
        final err = await validFileContentFormat(savePathTmp);
        if (err != null) {
          updating.remove(id);
          await FileUtils.deletePath(savePathTmp);

          Future.delayed(const Duration(milliseconds: 10), () async {
            for (var event in onEventUpdate) {
              event(id, true);
            }
          });
          return err;
        }
      }

      String renameError = "";
      for (var i = 0; i < 3; ++i) {
        try {
          await File(savePathTmp).rename(savePath);
          renameError = "";
          break;
        } catch (err) {
          renameError = err.toString();
          await Future.delayed(const Duration(seconds: 1));
        }
      }
      if (renameError.isNotEmpty) {
        updating.remove(id);
        await FileUtils.deletePath(savePathTmp);

        Future.delayed(const Duration(milliseconds: 10), () async {
          for (var event in onEventUpdate) {
            event(id, true);
          }
        });
        return ReturnResultError(
          "Rename file from [$savePathTmp] to [$savePath] failed: $renameError",
        );
      }
      if (profile.type == ProfilePatchFileType.yaml) {
        await FileUtils.append(savePath, "\n$urlComment${profile.url}\n");
      }
      if (profile.remark.isEmpty) {
        final result = await HttpUtils.httpGetTitle(profile.url, userAgent);
        if (result.data == null || result.data!.length > 32) {
          profile.remark = uri.host;
        } else {
          profile.remark = result.data!;
        }
      }
    }
    await save();
    updating.remove(id);
    Future.delayed(const Duration(milliseconds: 10), () async {
      for (var event in onEventUpdate) {
        event(id, true);
      }
    });
    return result.error;
  }

  static Future<void> updateByTicker() async {
    DateTime now = DateTime.now();
    for (var profile in _config.profiles) {
      if (!profile.isRemote() || profile.updateInterval == null) {
        continue;
      }
      if (profile.update == null ||
          now.difference(profile.update!).inSeconds >=
              profile.updateInterval!.inSeconds) {
        update(profile.id);
      }
    }
  }

  static Future<void> remove(String id) async {
    for (int i = 0; i < _config.profiles.length; ++i) {
      if (id == _config.profiles[i].id) {
        _config.profiles.removeAt(i);
        --i;
      }
    }

    for (var event in onEventRemove) {
      event(id);
    }
    if (_config._currentId == id) {
      _config._currentId = _config.profiles.isEmpty
          ? kProfilePatchBuildinOverwrite
          : _config.profiles.first.id;

      for (var event in onEventCurrentChanged) {
        event(_config._currentId);
      }
    }

    final filePath = path.join(await PathUtils.profilePatchsDir(), id);
    await FileUtils.deletePath(filePath);
    await save();
  }

  static Future<void> removeAllProfile() async {
    var dir = await PathUtils.profilePatchsDir();
    for (var profile in _config.profiles) {
      final filePath = path.join(dir, profile.id);
      await FileUtils.deletePath(filePath);
    }
    _config.profiles.clear();
    _config._currentId = "";
    for (var event in onEventCurrentChanged) {
      event(_config._currentId);
    }
    await save();
  }

  static Future<String> getProfilePatchPath(String id) async {
    if (id.isEmpty) {
      id = _config._currentId;
    }
    if (id == kProfilePatchBuildinOverwrite ||
        id == kProfilePatchBuildinNoOverwrite) {
      return "";
    }
    int index = _config.profiles.indexWhere((value) {
      return value.id == id;
    });
    if (index < 0) {
      return "";
    }

    final filePath = path.join(await PathUtils.profilePatchsDir(), id);
    return filePath;
  }

  static Future<String> getProfilePatchScriptPath(
    String corePath,
    String id,
  ) async {
    if (id.isEmpty) {
      id = _config._currentId;
    }
    if (id == kProfilePatchBuildinOverwrite ||
        id == kProfilePatchBuildinNoOverwrite) {
      return corePath;
    }
    int index = _config.profiles.indexWhere((value) {
      return value.id == id;
    });
    if (index < 0) {
      return corePath;
    }
    final patch = _config.profiles[index];

    final fileCore = File(corePath);
    if (!await fileCore.exists()) {
      return corePath;
    }

    final fileScriptPath = path.join(await PathUtils.profilePatchsDir(), id);
    final fileScript = File(fileScriptPath);
    if (!await fileScript.exists()) {
      Log.w("evaluate ${patch.remark} filecontent($fileScriptPath) not exists");
      return corePath;
    }
    String fileCoreContent = await fileCore.readAsString();
    final fileScriptContent = await fileScript.readAsString();
    if (fileCoreContent.isEmpty) {
      Log.w("evaluate ${patch.remark} filecontent($corePath) is empty");
      return corePath;
    }
    if (fileScriptContent.isEmpty) {
      Log.w("evaluate ${patch.remark} filecontent($fileScriptPath) is empty");
      return corePath;
    }
    JavascriptRuntime flutterJs = getJavascriptRuntime();
    try {
      fileCoreContent = EmojiUtils.unemojify(fileCoreContent);
      var doc = loadYaml(fileCoreContent);
      if (doc == null) {
        Log.w("evaluate ${patch.remark} loadYaml from $corePath failed");
        return corePath;
      }

      final fileCoreContentArg = json.encode(doc);
      final res = await flutterJs.evaluateAsync('''
      $fileScriptContent
      main($fileCoreContentArg)
    ''');
      if (res.isError) {
        throw res.stringResult;
      }
      if (res.rawResult == null) {
        Log.w("evaluate ${patch.remark} rawResult is null");
        return corePath;
      }

      String value = "";
      if (res.rawResult is String) {
        value = res.rawResult;
      } else if (res.rawResult is Map) {
        value = YamlWriter(allowUnquotedStrings: true).write(res.rawResult);
      } else if (res.rawResult is ffi.Pointer) {
        final data = flutterJs.convertValue<Map<String, dynamic>>(res);
        value = YamlWriter(allowUnquotedStrings: true).write(data);
      } else {
        Log.w(
          "evaluate ${patch.remark} rawResult type unsupport: ${res.rawResult.runtimeType}",
        );
        return corePath;
      }

      String newCorePath = await PathUtils.serviceCorePatchPath();
      await File(newCorePath).writeAsString(value);
      return newCorePath;
    } catch (e) {
      throw 'evaluate ${patch.remark} exception: ${e.toString()}';
    }
  }

  static void reorder(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    if (oldIndex >= _config.profiles.length ||
        newIndex >= _config.profiles.length) {
      return;
    }
    var item = _config.profiles.removeAt(oldIndex);
    _config.profiles.insert(newIndex, item);
  }

  static void reset() {
    _config._currentId = "";
  }
}
