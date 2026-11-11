import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../services/device_link_service.dart';
import '../../state/vault_state.dart';

/// Scans a link QR code from another device and sends the encrypted vault.
class LinkSendScreen extends StatefulWidget {
  const LinkSendScreen({super.key});

  @override
  State<LinkSendScreen> createState() => _LinkSendScreenState();
}

class _LinkSendScreenState extends State<LinkSendScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _busy = false;
  String? _error;
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy || _done) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .where((v) => v.startsWith(DeviceLinkService.scheme))
        .firstOrNull;
    if (raw == null) {
      setState(() => _error = 'That is not a SecureVault link code.');
      return;
    }
    final state = context.read<VaultState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Send vault?'),
        content: Text('Send an encrypted copy of "${state.account?.name}" to '
            'the scanned device? It can only be opened with your master '
            'password.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Send')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await DeviceLinkService.instance
          .send(raw, await state.exportForLink());
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return Scaffold(
        appBar: AppBar(title: const Text('Send vault')),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.check_circle_outline,
                size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            const Text('Vault sent.'),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done')),
          ]),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Scan link code')),
      body: Stack(alignment: Alignment.center, children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        IgnorePointer(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        if (_busy) const CircularProgressIndicator(),
        if (_error != null)
          Positioned(
            bottom: 32,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white)),
            ),
          ),
      ]),
    );
  }
}
