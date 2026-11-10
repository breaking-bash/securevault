import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/vault_state.dart';
import 'ui/theme.dart';
import 'ui/screens/gate_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = VaultState();
  await state.init();
  runApp(SecureVaultApp(state: state));
}

class SecureVaultApp extends StatefulWidget {
  final VaultState state;
  const SecureVaultApp({super.key, required this.state});

  @override
  State<SecureVaultApp> createState() => _SecureVaultAppState();
}

class _SecureVaultAppState extends State<SecureVaultApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Lock the vault whenever the app leaves the foreground.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      widget.state.onAppBackgrounded();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.state,
      child: Consumer<VaultState>(
        builder: (context, state, _) {
          return MaterialApp(
            title: 'SecureVault',
            debugShowCheckedModeBanner: false,
            theme: buildLightTheme(),
            darkTheme: buildDarkTheme(),
            themeMode: state.settings.themeMode,
            home: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => state.registerActivity(),
              onPointerSignal: (_) => state.registerActivity(),
              child: const GateScreen(),
            ),
          );
        },
      ),
    );
  }
}
