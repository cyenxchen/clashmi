import 'dart:io';

import 'package:protocol_handler/protocol_handler.dart';
import 'package:win32_registry/win32_registry.dart';

class SystemSchemeUtils {
  static const String _kClashScheme = "clash";
  static const String _kClashMiScheme = "clashmi";
  static String getClashScheme() => _kClashScheme;
  static String getClashMiScheme() => _kClashMiScheme;
  static String getClashSchemeWith() => "$_kClashScheme://";
  static String getClashMiSchemeWith() => "$_kClashMiScheme://";
  static bool isRegistered(String scheme) {
    return _isRegistered(scheme);
  }

  static Future<String?> register(String scheme) async {
    if (Platform.isLinux) {
      return await _registerLinuxScheme(scheme);
    }
    try {
      await protocolHandler.register(scheme);
    } catch (err) {
      return err.toString();
    }
    return null;
  }

  static String? unregister(String scheme) {
    if (!Platform.isWindows) {
      return null;
    }
    String path = 'Software\\Classes\\$scheme\\shell\\open\\command';
    try {
      Registry.currentUser.deleteKey(path);
    } catch (err) {
      return err.toString();
    }

    return null;
  }

  static bool _isRegistered(String scheme) {
    if (!Platform.isWindows) {
      return false;
    }
    String appPath = Platform.resolvedExecutable.toLowerCase();
    String path = 'Software\\Classes\\$scheme\\shell\\open\\command';
    RegistryValue? value = Registry.currentUser.getValue("", path: path);
    if (value == null || value.type != RegistryValueType.string) {
      return false;
    }
    String file = value.data as String;
    return file.toLowerCase().indexOf(appPath) == 0;
  }

  static Future<String?> _registerLinuxScheme(String scheme) async {
    const desktopCandidates = ["com.nebula.clashmi.desktop", "clashmi.desktop"];

    final customDesktop = (Platform.environment["CLASHMI_DESKTOP_FILE"] ?? "")
        .trim();
    final candidates = [
      if (customDesktop.isNotEmpty) customDesktop,
      ...desktopCandidates,
    ];

    final handler = "x-scheme-handler/$scheme";
    final before = await _queryLinuxDefaultHandler(handler);
    if (before != null && candidates.contains(before)) {
      return null;
    }

    String? lastError;
    for (final candidate in candidates) {
      final err = await _setLinuxDefaultHandler(handler, candidate);
      if (err != null) {
        lastError = err;
        continue;
      }
      final after = await _queryLinuxDefaultHandler(handler);
      if (after == candidate) {
        return null;
      }
    }

    return lastError ??
        "linux scheme register failed: handler=$handler candidates=$candidates";
  }

  static Future<String?> _queryLinuxDefaultHandler(String handler) async {
    try {
      final result = await Process.run("xdg-mime", [
        "query",
        "default",
        handler,
      ]);
      if (result.exitCode != 0) {
        return null;
      }
      final desktopFile = (result.stdout ?? "").toString().trim();
      return desktopFile.isEmpty ? null : desktopFile;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _setLinuxDefaultHandler(
    String handler,
    String desktopFile,
  ) async {
    try {
      final result = await Process.run("xdg-mime", [
        "default",
        desktopFile,
        handler,
      ]);
      if (result.exitCode != 0) {
        return "xdg-mime default failed($desktopFile, $handler): ${result.stderr}";
      }
      return null;
    } catch (err) {
      return "xdg-mime not available: $err";
    }
  }
}
