import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/watchtower_service.dart';
import '../../state/vault_state.dart';
import '../screens/watchtower_screen.dart';

/// Home banners controlled by Settings > Notifications.
class AlertBanners extends StatefulWidget {
  const AlertBanners({super.key});

  @override
  State<AlertBanners> createState() => _AlertBannersState();
}

class _AlertBannersState extends State<AlertBanners>
    with WidgetsBindingObserver {
  static const _ch = MethodChannel('securevault/autofill');
  bool _autofillOn = true;

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
    if (!Platform.isAndroid) return;
    try {
      final v = await _ch.invokeMethod<bool>('isEnabled') ?? true;
      if (mounted) setState(() => _autofillOn = v);
    } catch (_) {}
  }

  Widget _banner(BuildContext context,
      {required IconData icon,
      required Color color,
      required String title,
      required String body,
      required VoidCallback onTap}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(body,
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();
    final s = state.settings;
    final out = <Widget>[];

    if (Platform.isAndroid && s.notifyAutofill && !_autofillOn) {
      out.add(_banner(context,
          icon: Icons.auto_fix_high_rounded,
          color: const Color(0xFF0A72FF),
          title: 'Turn on autofill',
          body: 'Fill logins in other apps and websites.',
          onTap: () => _ch.invokeMethod('openSettings')));
    }

    if (s.notifyWatchtower) {
      final n = WatchtowerService.instance
          .analyze(state.activeEntries)
          .where((f) => !s.ignoredAlerts.contains('${f.entry.id}|${f.issue.name}'))
          .length;
      if (n > 0) {
        out.add(_banner(context,
            icon: Icons.shield_outlined,
            color: const Color(0xFFFFB74D),
            title: '$n Watchtower ${n == 1 ? 'alert' : 'alerts'}',
            body: 'Review weak, reused and other risky items.',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const WatchtowerScreen()))));
      }
    }

    return Column(children: out);
  }
}
