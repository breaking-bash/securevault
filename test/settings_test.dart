import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:securevault/services/settings_service.dart';

/// Fake path_provider pointing the app-support dir at a temp folder.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String base;
  _FakePathProvider(this.base);

  @override
  Future<String?> getApplicationSupportPath() async => base;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSettings auto-lock serialization', () {
    test('round-trips the "Immediately" auto-lock flag', () {
      final s = AppSettings(
        themeMode: ThemeMode.dark,
        autoLockMinutes: 0,
        autoLockImmediate: true,
        clipboardClearSeconds: 15,
      );
      final restored = AppSettings.fromJson(s.toJson());
      expect(restored.autoLockImmediate, isTrue);
      expect(restored.autoLockMinutes, 0);
      expect(restored.clipboardClearSeconds, 15);
      expect(restored.themeMode, ThemeMode.dark);
    });

    test('round-trips a normal idle timeout (not immediate)', () {
      final s = AppSettings(autoLockMinutes: 5, autoLockImmediate: false);
      final restored = AppSettings.fromJson(s.toJson());
      expect(restored.autoLockImmediate, isFalse);
      expect(restored.autoLockMinutes, 5);
    });

    test('defaults autoLockImmediate to false for legacy settings JSON', () {
      // Old settings files written before the feature have no key.
      final restored = AppSettings.fromJson({
        'themeMode': 'system',
        'autoLockMinutes': 3,
        'clipboardClearSeconds': 30,
      });
      expect(restored.autoLockImmediate, isFalse);
      expect(restored.autoLockMinutes, 3);
    });
  });

  group('SettingsService persistence', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('sv_settings');
      PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('saves and reloads the Immediately auto-lock option', () async {
      final s = AppSettings(autoLockImmediate: true, autoLockMinutes: 0);
      await SettingsService.instance.save(s);

      final loaded = await SettingsService.instance.load();
      expect(loaded.autoLockImmediate, isTrue);
      expect(loaded.autoLockMinutes, 0);
    });

    test('load() returns defaults when no file exists', () async {
      final loaded = await SettingsService.instance.load();
      expect(loaded.autoLockImmediate, isFalse);
      expect(loaded.autoLockMinutes, 3);
    });
  });
}
