import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/vault_state.dart';
import 'home_screen.dart';
import 'unlock_screen.dart';
import 'welcome_screen.dart';

/// Decides which top-level screen to show based on session state.
class GateScreen extends StatelessWidget {
  const GateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();

    if (state.unlocked) {
      return const HomeScreen();
    }
    if (!state.hasAccounts) {
      // No accounts on this device yet -> first-run welcome / create flow.
      return const WelcomeScreen();
    }
    // Accounts exist -> show account picker + unlock.
    return const UnlockScreen();
  }
}
