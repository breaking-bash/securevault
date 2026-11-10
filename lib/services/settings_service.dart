import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// App-wide, non-secret preferences persisted as a small JSON file.
class AppSettings {
  ThemeMode themeMode;
  int autoLockMinutes; // 0 = never
  // When true, the vault locks the instant the app is backgrounded/loses focus
  // (zero idle grace). Takes precedence over [autoLockMinutes].
  bool autoLockImmediate;
  int clipboardClearSeconds; // 0 = never auto-clear

  AppSettings({
    this.themeMode = ThemeMode.system,
    this.autoLockMinutes = 3,
    this.autoLockImmediate = false,
    this.clipboardClearSeconds = 30,
  });

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'autoLockMinutes': autoLockMinutes,
        'autoLockImmediate': autoLockImmediate,
        'clipboardClearSeconds': clipboardClearSeconds,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        themeMode: ThemeMode.values.firstWhere(
          (m) => m.name == j['themeMode'],
          orElse: () => ThemeMode.system,
        ),
        autoLockMinutes: (j['autoLockMinutes'] ?? 3) as int,
        autoLockImmediate: (j['autoLockImmediate'] ?? false) as bool,
        clipboardClearSeconds: (j['clipboardClearSeconds'] ?? 30) as int,
      );
}

class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  Future<File> _file() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'securevault'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return File(p.join(dir.path, 'settings.json'));
  }

  Future<AppSettings> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return AppSettings();
      return AppSettings.fromJson(
          jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return AppSettings();
    }
  }

  Future<void> save(AppSettings s) async {
    final f = await _file();
    await f.writeAsString(jsonEncode(s.toJson()));
  }
}
