import 'package:flutter/material.dart';

/// Rounded-square coloured icon, as used for item categories in 1Password.
class TypeTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const TypeTile(
      {super.key, required this.icon, required this.color, this.size = 40});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(size * 0.28),
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.55),
      );
}
