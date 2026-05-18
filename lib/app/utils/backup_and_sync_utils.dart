// ignore_for_file: unused_catch_stack

import 'dart:io';

import 'package:clashmi/app/extension/datetime.dart';
import 'package:clashmi/app/modules/profile_manager.dart';
import 'package:clashmi/app/modules/profile_patch_manager.dart';
import 'package:clashmi/app/runtime/return_result.dart';
import 'package:clashmi/app/utils/app_utils.dart';
import 'package:clashmi/app/utils/path_utils.dart';
import 'package:clashmi/app/utils/zip_utils.dart';
import 'package:path/path.dart' as path;
import 'package:tuple/tuple.dart';

class BackupAndSyncUtils {
  static String getZipExtension() => 'zip';

  static String getZipFileName() {
    final appName = AppUtils.getName();
    final appVersion = AppUtils.getBuildinVersion();
    var name =
        '${appName}_${appVersion}_${Platform.operatingSystem}_${DateTime.now().formatLikeFileNameTimestamp}.backup.${getZipExtension()}';
    name = name.replaceAll(' ', '');
    return name;
  }

  static Future<String> getZipFilePath() async {
    final dir = await PathUtils.cacheDir();
    return path.join(dir, getZipFileName());
  }

  static List<Tuple2<String, bool>> getZipFileNameList() {
    final profiles = ProfileManager.getProfiles();
    final profilePatchs = ProfilePatchManager.getProfilePatchs();
    var list = [
      Tuple2(PathUtils.serviceCoreSettingFileName(), true),
      Tuple2(PathUtils.settingFileName(), true),
      Tuple2(PathUtils.profilesFileName(), true),
      Tuple2(PathUtils.profilePatchsFileName(), true),
      Tuple2(PathUtils.diversionTemplateFileName(), true),
      Tuple2(PathUtils.providersConfigFileName(), true),
      Tuple2(PathUtils.boardSessionFileName(), true),
    ];
    if (profiles.isNotEmpty) {
      list.add(Tuple2(PathUtils.profilesName(), true));
    }
    if (profilePatchs.isNotEmpty) {
      list.add(Tuple2(PathUtils.profilePatchsName(), true));
    }

    return list;
  }

  static List<String> getFileNamesFromList(List<Tuple2<String, bool>> list) {
    return list.map((tuple) => tuple.item1).toList();
  }

  static Future<ReturnResultError?> validZip(String zipPath) async {
    final result = await ZipUtils.list(zipPath);
    if (result.error != null) {
      return result.error;
    }
    if (result.data!.isEmpty) {
      return ReturnResultError('backup zip file is empty');
    }

    final expectedFileNames = getFileNamesFromList(getZipFileNameList());
    final actualFileNames = result.data!;
    final intersection = expectedFileNames.toSet().intersection(
      actualFileNames.toSet(),
    );

    if (intersection.isEmpty) {
      return ReturnResultError('backup zip file is not compatible');
    }
    return null;
  }
}
