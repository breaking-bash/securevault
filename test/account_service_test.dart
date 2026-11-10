import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:securevault/services/account_service.dart';

/// Fake path_provider that points the app-support dir at a temp folder, so
/// AccountService can read/write accounts.json during tests.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String base;
  _FakePathProvider(this.base);

  @override
  Future<String?> getApplicationSupportPath() async => base;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sv_acct');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('duplicate username (case-insensitive, trimmed) is rejected', () async {
    final svc = AccountService.instance;

    // First account creates fine.
    final a = await svc.createAccount(name: 'Alice', masterPassword: 'pw-123456');
    expect(a.name, 'Alice');
    expect((await svc.listAccounts()).length, 1);

    // Same name again -> rejected, no second vault created.
    expect(
      () => svc.createAccount(name: 'Alice', masterPassword: 'other-pw-1'),
      throwsA(isA<AccountExistsException>()),
    );
    expect((await svc.listAccounts()).length, 1);

    // Different case + surrounding whitespace is still a duplicate.
    expect(
      () => svc.createAccount(name: '  alice  ', masterPassword: 'other-pw-2'),
      throwsA(isA<AccountExistsException>()),
    );
    expect((await svc.listAccounts()).length, 1);

    // A genuinely different username is allowed.
    await svc.createAccount(name: 'Bob', masterPassword: 'pw-abcdef');
    expect((await svc.listAccounts()).length, 2);
  });
}
