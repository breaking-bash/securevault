import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/vault_state.dart';
import 'autofill_picker_screen.dart';
import 'autofill_save_screen.dart';
import 'passkey_screen.dart';
import 'home_screen.dart';
import 'unlock_screen.dart';
import 'welcome_screen.dart';

/// Decides which top-level screen to show based on session state.
class GateScreen extends StatelessWidget {
  const GateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();

    final String key;
    final Widget screen;
    if (state.unlocked && !state.unlockAnimating) {
      key = 'home';
      final req = state.autofillRequest;
      screen = req == null
          ? const HomeScreen()
          : req.passkeyMode != null
              ? PasskeyScreen(request: req)
              : req.isSave
              ? AutofillSaveScreen(request: req)
              : AutofillPickerScreen(request: req);
    } else if (!state.hasAccounts) {
      // No accounts on this device yet -> first-run welcome / create flow.
      key = 'welcome';
      screen = const WelcomeScreen();
    } else {
      // Accounts exist -> show account picker + unlock.
      key = 'unlock';
      screen = const UnlockScreen();
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(anim),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(key), child: screen),
    );
  }
}