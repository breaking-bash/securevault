import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/vault_state.dart';

/// Rounded-square coloured icon, as used for item categories in 1Password.
/// When [url] is given (and website icons are enabled) the site's favicon is
/// shown instead, falling back to the category icon.
class TypeTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final String? url;
  const TypeTile(
      {super.key,
      required this.icon,
      required this.color,
      this.size = 40,
      this.url});

  static String? hostOf(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    final u = url.contains('://') ? url : 'https://$url';
    final h = Uri.tryParse(u)?.host.toLowerCase() ?? '';
    return h.contains('.') ? h : null;
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.28);
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, borderRadius: radius),
      child: Icon(icon, color: Colors.white, size: size * 0.55),
    );
    final host = hostOf(url);
    final enabled = context.select<VaultState, bool>((s) => s.settings.fetchIcons);
    if (host == null || !enabled) return fallback;
    return ClipRRect(
      borderRadius: radius,
      child: Container(
        width: size,
        height: size,
        color: Colors.white,
        padding: EdgeInsets.all(size * 0.14),
        child: Image.network(
          'https://icons.duckduckgo.com/ip3/$host.ico',
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => fallback,
          loadingBuilder: (_, child, p) => p == null ? child : fallback,
        ),
      ),
    );
  }
}