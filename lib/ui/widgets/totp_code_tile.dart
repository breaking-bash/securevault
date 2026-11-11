import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../services/totp_service.dart';
import '../theme.dart';

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
    if (code.length == 6) return '${code.substring(0, 3)} \u2022 ${code.substring(3)}';
    if (code.length == 8) return '${code.substring(0, 4)} \u2022 ${code.substring(4)}';
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
    final urgent = _remaining <= 5;
    return InkWell(
      onTap: () => widget.onCopy(_code),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('one-time password',
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(color: fieldLabelColor(context))),
                  const SizedBox(height: 2),
                  Text(
                    _spaced(_code),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.5,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    value: _remaining / period,
                    strokeWidth: 3,
                    color: urgent ? Colors.red : const Color(0xFF1E8E3E),
                    backgroundColor: scheme.outlineVariant,
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 18,
                  child: Text('$_remaining',
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                          fontSize: 13,
                          fontFeatures: [FontFeature.tabularFigures()])),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}