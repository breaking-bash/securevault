import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/device_link_service.dart';
import '../../state/vault_state.dart';

/// Shows a QR code and waits for another device to send its vault.
class LinkReceiveScreen extends StatefulWidget {
  const LinkReceiveScreen({super.key});

  @override
  State<LinkReceiveScreen> createState() => _LinkReceiveScreenState();
}

class _LinkReceiveScreenState extends State<LinkReceiveScreen> {
  LinkReceiver? _receiver;
  String? _error;
  String? _imported;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _receiver?.cancel().catchError((_) {});
    super.dispose();
  }

  Future<void> _start() async {
    final state = context.read<VaultState>();
    try {
      final r = await DeviceLinkService.instance.startReceiver();
      if (!mounted) {
        await r.cancel();
        return;
      }
      setState(() => _receiver = r);
      final data = await r.result;
      final account = await state.importFromLink(data);
      if (mounted) setState(() => _imported = account.name);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget body;
    if (_imported != null) {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle_outline, size: 64, color: scheme.primary),
        const SizedBox(height: 16),
        Text('"$_imported" was linked.',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text('Unlock it with the same master password you use on the '
            'other device.'),
        const SizedBox(height: 24),
        FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done')),
      ]);
    } else if (_error != null) {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline, size: 64, color: scheme.error),
        const SizedBox(height: 16),
        Text(_error!, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close')),
      ]);
    } else if (_receiver == null) {
      body = const CircularProgressIndicator();
    } else {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          child: QrImageView(
              data: _receiver!.qrPayload, size: 260, backgroundColor: Colors.white),
        ),
        const SizedBox(height: 24),
        const Text(
          'On your other device, open Settings → "Send vault to another '
          'device" and scan this code. Both devices must be on the same '
          'network.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const Text('Waiting…'),
      ]);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Link from another device')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420), child: body),
        ),
      ),
    );
  }
}
