import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/biometric_service.dart';
import '../../services/secret_key_service.dart';
import '../../services/settings_service.dart';
import '../../state/vault_state.dart';
import '../widgets/emergency_kit.dart';
import 'home_screen.dart' show FolderManager;
import 'import_screen.dart';
import 'link_send_screen.dart';

const _repoUrl = 'https://github.com/itsnavin/securevault';

/// 1Password-style settings hub: one row per category, each opening a page.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, Color color, String title, Widget page) =>
        _HubTile(
            icon: icon,
            color: color,
            title: title,
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => page)));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop()),
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          row(Icons.person_outline, const Color(0xFF2DD4A7), 'Accounts',
              const _AccountsPage()),
          row(Icons.folder_copy_outlined, const Color(0xFFD9A8F0), 'Collections',
              const _CollectionsPage()),
          row(Icons.tune, const Color(0xFF3FC3EE), 'General',
              const _GeneralPage()),
          row(Icons.lock_outline, const Color(0xFFFFB74D), 'Security',
              const _SecurityPage()),
          row(Icons.privacy_tip_outlined, const Color(0xFF2DD4A7), 'Privacy',
              const _PrivacyPage()),
          if (Platform.isAndroid)
            row(Icons.auto_fix_high_outlined, const Color(0xFFB8B8F0),
                'Autofill', const _AutofillPage()),
          row(Icons.notifications_none_rounded, const Color(0xFFFFB74D),
              'Notifications', const _NotificationsPage()),
          if (Platform.isAndroid)
            row(Icons.science_outlined, const Color(0xFFD9A8F0), 'Labs',
                const _LabsPage()),
          row(Icons.settings_suggest_outlined, const Color(0xFF3FC3EE),
              'Advanced', const _AdvancedPage()),
          row(Icons.info_outline, const Color(0xFF3FC3EE), 'About',
              const _AboutPage()),
        ],
      ),
    );
  }
}

class _HubTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback onTap;
  const _HubTile(
      {required this.icon,
      required this.color,
      required this.title,
      required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(18)),
          child: Icon(icon, size: 20, color: color),
        ),
        title: Text(title),
        onTap: onTap,
      );
}

/// Shared scaffold for every settings sub-page.
class _Page extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Page({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(
            padding: const EdgeInsets.only(bottom: 24), children: children),
      );
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 1,
                fontWeight: FontWeight.bold)),
      );
}

// ------------------------------------------------------------------ Accounts
class _AccountsPage extends StatelessWidget {
  const _AccountsPage();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();
    return _Page(title: 'Accounts', children: [
      ListTile(
        leading: CircleAvatar(
            child: Text((state.account?.name ?? '?')
                .characters
                .first
                .toUpperCase())),
        title: Text(state.account?.name ?? 'SecureVault'),
        subtitle: const Text('Signed in on this device'),
      ),
      const _Header('Sign-in & recovery'),
      ListTile(
        leading: const Icon(Icons.password_outlined),
        title: const Text('Change master password'),
        subtitle: const Text('Re-encrypts the whole vault'),
        onTap: () => _changeMasterPassword(context),
      ),
      ListTile(
        leading: const Icon(Icons.vpn_key_outlined),
        title: Text(state.sessionSecretKey != null
            ? 'Secret Key enabled'
            : 'Enable Secret Key'),
        subtitle: Text(state.sessionSecretKey != null
            ? 'Shown only once. Lost it? Link a new device with a QR code.'
            : 'Required with your password on new devices'),
        onTap: state.sessionSecretKey != null
            ? () => _secretKeyInfo(context)
            : () => _secretKey(context),
      ),
      if (Platform.isAndroid || Platform.isIOS)
        ListTile(
          leading: const Icon(Icons.qr_code_scanner),
          title: const Text('Set up another device'),
          subtitle: const Text('Scan a link code over your local network'),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LinkSendScreen())),
        ),
      const _Header('Session'),
      ListTile(
        leading: const Icon(Icons.switch_account_outlined),
        title: const Text('Switch account'),
        onTap: () {
          state.signOut();
          Navigator.of(context).popUntil((r) => r.isFirst);
        },
      ),
      ListTile(
        leading: const Icon(Icons.lock_outline),
        title: const Text('Lock now'),
        onTap: () {
          state.lock();
          Navigator.of(context).popUntil((r) => r.isFirst);
        },
      ),
    ]);
  }
}

/// Collections are the vault's folders.
class _CollectionsPage extends StatelessWidget {
  const _CollectionsPage();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Collections')),
        body: const SingleChildScrollView(child: FolderManager()),
      );
}

// ------------------------------------------------------------------- General
class _GeneralPage extends StatelessWidget {
  const _GeneralPage();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();
    final s = state.settings;
    return _Page(title: 'General', children: [
      const _Header('Appearance'),
      ListTile(
        leading: const Icon(Icons.brightness_6_outlined),
        title: const Text('Theme'),
        trailing: DropdownButton<ThemeMode>(
          value: s.themeMode,
          underline: const SizedBox.shrink(),
          onChanged: (m) {
            if (m == null) return;
            state.updateSettings(s.copyWith(themeMode: m));
          },
          items: const [
            DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
            DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
            DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
          ],
        ),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ Security
class _SecurityPage extends StatefulWidget {
  const _SecurityPage();
  @override
  State<_SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<_SecurityPage> {
  bool _bioAvailable = false;
  bool _bioEnabled = false;
  bool _bioLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBiometric();
  }

  Future<void> _loadBiometric() async {
    final account = context.read<VaultState>().account;
    final available = await BiometricService.instance.isAvailable();
    final enabled = account == null
        ? false
        : await BiometricService.instance.hasStoredSecret(account.id);
    if (!mounted) return;
    setState(() {
      _bioAvailable = available;
      _bioEnabled = enabled;
      _bioLoading = false;
    });
  }

  Future<void> _toggleBiometric(bool value) async {
    final state = context.read<VaultState>();
    final messenger = ScaffoldMessenger.of(context);
    if (value) {
      final ok = await state.enableBiometricForCurrentAccount();
      if (!mounted) return;
      if (ok) setState(() => _bioEnabled = true);
      messenger.showSnackBar(SnackBar(
          content: Text(ok
              ? 'Biometric unlock enabled for this account'
              : 'Could not enable biometric unlock')));
    } else {
      await state.disableBiometricForCurrentAccount();
      if (!mounted) return;
      setState(() => _bioEnabled = false);
      messenger.showSnackBar(const SnackBar(
          content: Text('Biometric unlock disabled; stored secret removed')));
    }
  }

  String _autoLockLabel(AppSettings s) {
    if (s.autoLockImmediate) return 'Immediately when backgrounded';
    if (s.autoLockMinutes == 0) return 'Never (not recommended)';
    return 'After ${s.autoLockMinutes} minute(s) idle';
  }

  Widget _biometricTile() {
    if (_bioLoading) {
      return const ListTile(
        leading: Icon(Icons.fingerprint),
        title: Text('Unlock with biometrics'),
        subtitle: Text('Checking availability…'),
      );
    }
    if (!_bioAvailable) {
      return const ListTile(
        leading: Icon(Icons.fingerprint),
        title: Text('Unlock with biometrics'),
        subtitle: Text('Not available on this device'),
        enabled: false,
      );
    }
    return SwitchListTile(
      secondary: const Icon(Icons.fingerprint),
      title: const Text('Unlock with biometrics'),
      subtitle: const Text(
          'Master password is kept in the biometric-gated OS keystore.'),
      value: _bioEnabled,
      onChanged: _toggleBiometric,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();
    final s = state.settings;
    final autoLockValue = s.autoLockImmediate ? -1 : s.autoLockMinutes;

    return _Page(title: 'Security', children: [
      const _Header('Unlock'),
      _biometricTile(),
      ListTile(
        leading: const Icon(Icons.event_repeat_rounded),
        title: const Text('Require master password'),
        subtitle: const Text('Biometric unlock stops working after this long'),
        trailing: DropdownButton<int>(
          value: s.requirePasswordDays,
          underline: const SizedBox.shrink(),
          onChanged: (v) {
            if (v == null) return;
            state.updateSettings(s.copyWith(requirePasswordDays: v));
          },
          items: const [
            DropdownMenuItem(value: 0, child: Text('Never')),
            DropdownMenuItem(value: 1, child: Text('1 day')),
            DropdownMenuItem(value: 7, child: Text('7 days')),
            DropdownMenuItem(value: 14, child: Text('14 days')),
            DropdownMenuItem(value: 30, child: Text('30 days')),
          ],
        ),
      ),
      const _Header('Auto-lock'),
      SwitchListTile(
        secondary: const Icon(Icons.lock_clock_outlined),
        title: const Text('Lock when app is left'),
        subtitle: const Text('Locks the instant you switch away'),
        value: s.autoLockImmediate,
        onChanged: (v) => state.updateSettings(s.copyWith(
            autoLockImmediate: v,
            autoLockMinutes: v ? 0 : (s.autoLockMinutes == 0 ? 3 : s.autoLockMinutes))),
      ),
      ListTile(
        leading: const Icon(Icons.timer_outlined),
        title: const Text('Auto-lock timer'),
        subtitle: Text(_autoLockLabel(s)),
        trailing: DropdownButton<int>(
          value: autoLockValue,
          underline: const SizedBox.shrink(),
          onChanged: (v) {
            if (v == null) return;
            state.updateSettings(s.copyWith(
                autoLockImmediate: v == -1,
                autoLockMinutes: v == -1 ? 0 : v));
          },
          items: const [
            DropdownMenuItem(value: -1, child: Text('Immediately')),
            DropdownMenuItem(value: 0, child: Text('Never')),
            DropdownMenuItem(value: 1, child: Text('1 min')),
            DropdownMenuItem(value: 3, child: Text('3 min')),
            DropdownMenuItem(value: 5, child: Text('5 min')),
            DropdownMenuItem(value: 15, child: Text('15 min')),
          ],
        ),
      ),
      const _Header('Clipboard'),
      ListTile(
        leading: const Icon(Icons.content_paste_off_outlined),
        title: const Text('Clear clipboard'),
        subtitle: Text(s.clipboardClearSeconds == 0
            ? 'Never'
            : 'Removed ${s.clipboardClearSeconds} seconds after you copy'),
        trailing: DropdownButton<int>(
          value: s.clipboardClearSeconds,
          underline: const SizedBox.shrink(),
          onChanged: (v) {
            if (v == null) return;
            state.updateSettings(s.copyWith(clipboardClearSeconds: v));
          },
          items: const [
            DropdownMenuItem(value: 0, child: Text('Never')),
            DropdownMenuItem(value: 15, child: Text('15 s')),
            DropdownMenuItem(value: 30, child: Text('30 s')),
            DropdownMenuItem(value: 60, child: Text('60 s')),
          ],
        ),
      ),
      const _Header('Concealed fields'),
      SwitchListTile(
        secondary: const Icon(Icons.visibility_outlined),
        title: const Text('Always show passwords'),
        subtitle: const Text('Off keeps passwords hidden until you reveal them'),
        value: s.alwaysShowPasswords,
        onChanged: (v) =>
            state.updateSettings(s.copyWith(alwaysShowPasswords: v)),
      ),
    ]);
  }
}

// ------------------------------------------------------------------- Privacy
class _PrivacyPage extends StatelessWidget {
  const _PrivacyPage();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();
    final s = state.settings;
    return _Page(title: 'Privacy', children: [
      const _Header('Screen'),
      if (Platform.isAndroid)
        SwitchListTile(
          secondary: const Icon(Icons.screenshot_monitor_outlined),
          title: const Text('Block screenshots'),
          subtitle: const Text(
              'Prevents screenshots, screen recording and the app preview in recent apps'),
          value: s.blockScreenshots,
          onChanged: (v) =>
              state.updateSettings(s.copyWith(blockScreenshots: v)),
        )
      else
        const ListTile(
          leading: Icon(Icons.screenshot_monitor_outlined),
          title: Text('Block screenshots'),
          subtitle: Text('Available on Android'),
          enabled: false,
        ),
      const _Header('Website icons'),
      SwitchListTile(
        secondary: const Icon(Icons.language),
        title: const Text('Show website icons'),
        subtitle: const Text(
            'Fetches site icons from the web (the domain is sent to an icon service)'),
        value: s.fetchIcons,
        onChanged: (v) => state.updateSettings(s.copyWith(fetchIcons: v)),
      ),
      const _Header('Data collection'),
      const ListTile(
        leading: Icon(Icons.analytics_outlined),
        title: Text('No analytics or tracking'),
        subtitle: Text('SecureVault does not collect usage data.'),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ Autofill
class _AutofillPage extends StatefulWidget {
  const _AutofillPage();
  @override
  State<_AutofillPage> createState() => _AutofillPageState();
}

class _AutofillPageState extends State<_AutofillPage>
    with WidgetsBindingObserver {
  static const _ch = MethodChannel('securevault/autofill');
  bool _on = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final v = await _ch.invokeMethod<bool>('isEnabled') ?? false;
      if (mounted) setState(() => _on = v);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return _Page(title: 'Autofill', children: [
      ListTile(
        leading: const Icon(Icons.auto_fix_high_outlined),
        title: const Text('Autofill service'),
        subtitle: Text(_on
            ? 'SecureVault suggests logins in other apps and sites'
            : 'Turn on to get login suggestions in other apps'),
        trailing: Text(_on ? 'On' : 'Set up'),
        onTap: _on ? null : () => _ch.invokeMethod('openSettings'),
      ),
      ListTile(
        leading: const Icon(Icons.key_rounded),
        title: const Text('Passkeys'),
        subtitle: const Text('Use SecureVault to create and sign in with passkeys (Android 14+)'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () async {
          final ok = await _ch.invokeMethod<bool>('openPasskeySettings') ?? false;
          if (!ok && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Passkey providers need Android 14 or newer')));
          }
        },
      ),
      SwitchListTile(
        secondary: const Icon(Icons.save_alt_rounded),
        title: const Text('Offer to save logins'),
        subtitle: const Text('Ask to save new logins you type in other apps'),
        value: context.watch<VaultState>().settings.offerSave,
        onChanged: (v) {
          final st = context.read<VaultState>();
          st.updateSettings(st.settings.copyWith(offerSave: v));
        },
      ),
      if (!_on) ...[
        const _Header('To set it up'),
        const ListTile(
            leading: CircleAvatar(radius: 12, child: Text('1')),
            title: Text('Tap "Autofill service" above')),
        const ListTile(
            leading: CircleAvatar(radius: 12, child: Text('2')),
            title: Text('Select SecureVault from the list')),
        const ListTile(
            leading: CircleAvatar(radius: 12, child: Text('3')),
            title: Text('Come back to SecureVault')),
      ],
    ]);
  }
}

class _NotificationsPage extends StatelessWidget {
  const _NotificationsPage();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();
    final s = state.settings;
    return _Page(title: 'Notifications', children: [
      SwitchListTile(
        secondary: const Icon(Icons.shield_outlined),
        title: const Text('Watchtower alerts'),
        subtitle: const Text('Show a banner on Home when items need attention'),
        value: s.notifyWatchtower,
        onChanged: (v) => state.updateSettings(s.copyWith(notifyWatchtower: v)),
      ),
      if (Platform.isAndroid)
        SwitchListTile(
          secondary: const Icon(Icons.auto_fix_high_rounded),
          title: const Text('Autofill reminder'),
          subtitle: const Text('Remind me when the autofill service is off'),
          value: s.notifyAutofill,
          onChanged: (v) => state.updateSettings(s.copyWith(notifyAutofill: v)),
        ),
    ]);
  }
}

class _LabsPage extends StatelessWidget {
  const _LabsPage();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();
    final s = state.settings;
    return _Page(title: 'Labs', children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Text('Experimental features. They may change or be removed.'),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.keyboard_alt_outlined),
        title: const Text('Inline autofill suggestions'),
        subtitle: const Text('Show suggestions on the keyboard (Android 11+)'),
        value: s.inlineSuggestions,
        onChanged: (v) => state.updateSettings(s.copyWith(inlineSuggestions: v)),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ Advanced
class _AdvancedPage extends StatelessWidget {
  const _AdvancedPage();

  @override
  Widget build(BuildContext context) {
    return _Page(title: 'Advanced', children: [
      const _Header('Data'),
      ListTile(
        leading: const Icon(Icons.file_download_outlined),
        title: const Text('Import from another password manager'),
        subtitle: const Text(
            '1Password, Bitwarden, LastPass, Chrome, Dashlane, KeePass, CSV'),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const ImportScreen())),
      ),
      if (Platform.isAndroid || Platform.isIOS)
        ListTile(
          leading: const Icon(Icons.qr_code_scanner),
          title: const Text('Send vault to another device'),
          subtitle: const Text('Scan a link code over your local network'),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LinkSendScreen())),
        ),
    ]);
  }
}

// --------------------------------------------------------------------- About
class _AboutPage extends StatelessWidget {
  const _AboutPage();

  @override
  Widget build(BuildContext context) {
    return _Page(title: 'About', children: [
      const ListTile(
        leading: Icon(Icons.shield_outlined),
        title: Text('SecureVault'),
        subtitle: Text('Your passwords, secured on your device.'),
      ),
      const ListTile(
        leading: Icon(Icons.person_outline),
        title: Text('Developer'),
        subtitle: Text('@itsnavin'),
      ),
      ListTile(
        leading: const Icon(Icons.code),
        title: const Text('Source code'),
        subtitle: const Text('github.com/itsnavin/securevault'),
        trailing: const Icon(Icons.copy, size: 18),
        onTap: () async {
          await Clipboard.setData(const ClipboardData(text: _repoUrl));
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Link copied')));
          }
        },
      ),
    ]);
  }
}

// ------------------------------------------------------------------- Actions
Future<void> _secretKeyInfo(BuildContext context) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Secret Key'),
        content: const Text(
            'Your Secret Key was shown once when it was created and is not '
            'displayed again. If you lost your Emergency Kit PDF, sign in on '
            'a new device by scanning a QR code from a device that is '
            'already signed in (Link from another device).'),
        actions: [
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK')),
        ],
      ),
    );

Future<void> _secretKey(BuildContext context) async {
  final state = context.read<VaultState>();
  final pw = state.sessionMasterPassword;
  if (pw == null) return;
  final fresh = SecretKeyService.instance.generate();
  final ok = await state.changeMasterPassword(
      currentPassword: pw, newPassword: pw, newSecretKey: fresh);
  if (!ok || !context.mounted) return;
  await showEmergencyKitDialog(context,
      accountName: state.account?.name ?? 'SecureVault', secretKey: fresh);
}

Future<void> _changeMasterPassword(BuildContext context) async {
  final current = TextEditingController();
  final next = TextEditingController();
  final confirm = TextEditingController();
  final formKey = GlobalKey<FormState>();
  String? error;
  bool busy = false;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Future<void> submit() async {
          if (!formKey.currentState!.validate()) return;
          setLocal(() => busy = true);
          final ok = await ctx.read<VaultState>().changeMasterPassword(
                currentPassword: current.text,
                newPassword: next.text,
              );
          if (!ctx.mounted) return;
          if (ok) {
            Navigator.pop(ctx);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content:
                      Text('Master password changed & vault re-encrypted')));
            }
          } else {
            setLocal(() {
              busy = false;
              error = 'Current password is incorrect';
            });
          }
        }

        return AlertDialog(
          title: const Text('Change master password'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: current,
                  obscureText: true,
                  decoration: InputDecoration(
                      labelText: 'Current password', errorText: error),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: next,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password'),
                  validator: (v) =>
                      (v == null || v.length < 8) ? 'At least 8 characters' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: confirm,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'Confirm new password'),
                  validator: (v) =>
                      v != next.text ? 'Passwords do not match' : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: busy ? null : submit,
              child: Text(busy ? 'Working…' : 'Change'),
            ),
          ],
        );
      },
    ),
  );
}
