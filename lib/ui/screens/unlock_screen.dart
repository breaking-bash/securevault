import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/account.dart';
import '../../services/biometric_service.dart';
import '../../state/vault_state.dart';
import '../widgets/animated_lock.dart';
import 'create_account_screen.dart';
import 'link_receive_screen.dart';

const _successGreen = Color(0xFF2E9E5B);

/// Account picker + master-password unlock screen (shown when ≥1 account exists).
/// The padlock closes when the screen appears, shakes on a wrong password and
/// swings open on success before the vault is revealed.
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen>
    with TickerProviderStateMixin {
  LocalAccount? _selected;
  final _pw = TextEditingController();
  final _sk = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _succeeded = false;
  String? _error;

  bool _bioAvailable = false;
  bool _bioEnabledForSelected = false;
  bool _bioAutoPrompted = false;

  late final AnimationController _open = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 650));
  late final AnimationController _shake = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 450));

  @override
  void initState() {
    super.initState();
    // "Lock" animation: start open and snap shut as the screen appears.
    _open.value = 1;
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) _open.reverse();
    });
    _initBiometric();
  }

  @override
  void dispose() {
    _pw.dispose();
    _sk.dispose();
    _open.dispose();
    _shake.dispose();
    super.dispose();
  }

  Future<void> _initBiometric() async {
    final available = await BiometricService.instance.isAvailable();
    if (!mounted) return;
    setState(() => _bioAvailable = available);
    if (available) await _refreshBioForSelected(autoPrompt: true);
  }

  Future<void> _refreshBioForSelected({bool autoPrompt = false}) async {
    final account = _selected ?? context.read<VaultState>().accountsList.first;
    final enabled = await BiometricService.instance.hasStoredSecret(account.id);
    if (!mounted) return;
    setState(() => _bioEnabledForSelected = enabled);
    // Offer the biometric prompt automatically the first time, if enabled.
    if (enabled && autoPrompt && !_bioAutoPrompted) {
      _bioAutoPrompted = true;
      _unlockBiometric();
    }
  }

  Future<void> _fail(String message) async {
    HapticFeedback.heavyImpact();
    setState(() {
      _busy = false;
      _error = message;
    });
    await _shake.forward(from: 0);
  }

  /// Plays the "unlock" animation, then lets the gate reveal the vault.
  Future<void> _succeed(VaultState state) async {
    HapticFeedback.mediumImpact();
    if (mounted) {
      setState(() {
        _busy = false;
        _succeeded = true;
      });
    }
    if (mounted) await _open.forward();
    await Future.delayed(const Duration(milliseconds: 350));
    state.finishUnlockAnimation();
  }

  Future<void> _unlockBiometric() async {
    final state = context.read<VaultState>();
    final account = _selected ?? state.accountsList.first;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await state.unlockWithBiometrics(account, animate: true);
    if (!mounted && !ok) return;
    if (ok) {
      await _succeed(state);
    } else if (mounted) {
      await _fail('Biometric unlock failed — use your master password');
    }
  }

  Future<void> _unlock() async {
    final state = context.read<VaultState>();
    final account = _selected ?? state.accountsList.first;
    if (_pw.text.isEmpty) {
      await _fail('Enter your master password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final needSk = await state.needsSecretKey(account);
    if (needSk && _sk.text.trim().isEmpty) {
      if (mounted) await _fail('Enter your Secret Key');
      return;
    }
    final ok = await state.unlock(
        account: account,
        masterPassword: _pw.text,
        secretKey: needSk ? _sk.text : null,
        animate: true);
    if (ok) {
      _pw.clear();
      _sk.clear();
      await _succeed(state);
    } else if (mounted) {
      await _fail(needSk
          ? 'Incorrect master password or Secret Key'
          : 'Incorrect master password');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();
    final scheme = Theme.of(context).colorScheme;
    _selected ??= state.accountsList.first;
    final lockColor = _succeeded ? _successGreen : scheme.primary;
    final bioReady = _bioAvailable && _bioEnabledForSelected;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scheme.primary.withValues(alpha: 0.16),
              scheme.surface,
            ],
            stops: const [0, 0.55],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: AnimatedBuilder(
                        animation: _shake,
                        builder: (_, child) => Transform.translate(
                          offset: Offset(
                              math.sin(_shake.value * math.pi * 6) *
                                  14 *
                                  (1 - _shake.value),
                              0),
                          child: child,
                        ),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 1, end: _succeeded ? 1.12 : 1),
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOutBack,
                          builder: (_, s, child) =>
                              Transform.scale(scale: s, child: child),
                          child: AnimatedLock(
                            open: _open,
                            size: 112,
                            color: scheme.onSurface.withValues(alpha: 0.75),
                            bodyColor: lockColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        _succeeded ? 'Unlocked' : 'Unlock your vault',
                        key: ValueKey(_succeeded),
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (state.accountsList.length > 1)
                      DropdownButtonFormField<String>(
                        initialValue: _selected?.id,
                        decoration: const InputDecoration(
                          labelText: 'Account',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        items: state.accountsList
                            .map((a) => DropdownMenuItem(
                                  value: a.id,
                                  child: Text(a.name),
                                ))
                            .toList(),
                        onChanged: (id) {
                          setState(() => _selected = state.accountsList
                              .firstWhere((a) => a.id == id));
                          _refreshBioForSelected();
                        },
                      )
                    else
                      Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                scheme.primary.withValues(alpha: 0.15),
                            child: Icon(Icons.person, color: scheme.primary),
                          ),
                          title: Text(_selected?.name ?? ''),
                        ),
                      ),
                    const SizedBox(height: 16),
                    FutureBuilder<bool>(
                      key: ValueKey(_selected?.id),
                      future: state.needsSecretKey(_selected!),
                      builder: (context, snap) {
                        if (snap.data != true) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: TextFormField(
                            controller: _sk,
                            autocorrect: false,
                            enableSuggestions: false,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Secret Key',
                              hintText: 'SV1-XXXXXX-XXXXXX-...',
                              helperText:
                                  'Required on new devices. Find it in Settings.',
                              prefixIcon: Icon(Icons.vpn_key_outlined),
                            ),
                          ),
                        );
                      },
                    ),
                    TextFormField(
                      controller: _pw,
                      obscureText: _obscure,
                      autofocus: !bioReady,
                      enabled: !_succeeded,
                      onFieldSubmitted: (_) => _unlock(),
                      decoration: InputDecoration(
                        labelText: 'Master password',
                        errorText: _error,
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility
                              : Icons.visibility_off),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _busy || _succeeded ? null : _unlock,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(_succeeded ? Icons.check : Icons.lock_open),
                      label: Text(_succeeded
                          ? 'Unlocked'
                          : _busy
                              ? 'Unlocking…'
                              : 'Unlock'),
                    ),
                    if (bioReady && !_succeeded) ...[
                      const SizedBox(height: 20),
                      Center(
                        child: PulsingFingerprint(
                          busy: _busy,
                          onTap: _unlockBiometric,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('Touch to unlock with biometrics',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    ],
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const CreateAccountScreen()),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Add another account'),
                    ),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const LinkReceiveScreen()),
                      ),
                      icon: const Icon(Icons.qr_code_2),
                      label: const Text('Link from another device'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
