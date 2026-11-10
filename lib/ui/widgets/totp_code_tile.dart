import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/totp_service.dart';

/// Shows a live RFC 6238 TOTP code with a countdown ring that refreshes each
/// period. [stored] is the saved TOTP value (a bare base32 secret or a full
/// `otpauth://` URI). Tapping the copy button copies the current code.
class TotpCodeTile extends StatefulWidget {
  final String stored;
  final void Function(String code) onCopy;

  const TotpCodeTile({super.key, required this.stored, required this.onCopy});

  @override
  State<TotpCodeTile> createState() => _TotpCodeTileState();
}

class _TotpCodeTileState extends State<TotpCodeTile> {
  Timer? _timer;
  TotpConfig? _config;
  String _code = '';
  int _remaining = 30;

  @override
  void initState() {
    super.initState();
    _config = TotpService.fromStored(widget.stored);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refresh() {
    final cfg = _config;
    if (cfg == null) return;
    final code = TotpService.generate(cfg);
    final remaining = TotpService.secondsRemaining(cfg.period);
    if (!mounted) return;
    setState(() {
      _code = code;
      _remaining = remaining;
    });
  }

  String _spaced(String code) {
    if (code.length == 6) return '${code.substring(0, 3)} ${code.substring(3)}';
    if (code.length == 8) return '${code.substring(0, 4)} ${code.substring(4)}';
    return code;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_config == null) {
      // Invalid secret: show it as a plain (masked) value instead of a code.
      return ListTile(
        leading: Icon(Icons.timer_outlined, color: scheme.primary),
        title: const Text('Verification code (TOTP)'),
        subtitle: const Text('Invalid TOTP secret'),
      );
    }
    final period = _config!.period;
    return ListTile(
      leading: Icon(Icons.timer_outlined, color: scheme.primary),
      title: Text(
        _spaced(_code),
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: 2,
        ),
      ),
      subtitle: const Text('Verification code (TOTP)'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: _remaining / period,
                  strokeWidth: 3,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
                Text('$_remaining', style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy code',
            icon: const Icon(Icons.copy),
            onPressed: () => widget.onCopy(_code),
          ),
        ],
      ),
    );
  }
}
