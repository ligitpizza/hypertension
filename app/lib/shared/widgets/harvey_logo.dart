import 'package:flutter/material.dart';

/// D-75: the Harvey brand mark (the H) and full logo (H + wordmark).
class HarveyLogo extends StatelessWidget {
  const HarveyLogo.mark({super.key, this.size = 40}) : full = false;
  const HarveyLogo.full({super.key, this.size = 120}) : full = true;

  final bool full;

  /// Height of the image.
  final double size;

  static const markAsset = 'assets/branding/harvey_mark.png';
  static const fullAsset = 'assets/branding/harvey_logo.png';

  @override
  Widget build(BuildContext context) => Image.asset(
    full ? fullAsset : markAsset,
    height: size,
    fit: BoxFit.contain,
    semanticLabel: 'Harvey',
    // Tests and very old devices: fall back to the name rather than a broken image.
    errorBuilder: (_, _, _) => Text(
      'Harvey',
      style: TextStyle(fontSize: size * 0.35, fontWeight: FontWeight.w800),
    ),
  );
}
