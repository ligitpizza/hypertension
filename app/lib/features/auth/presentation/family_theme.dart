import 'package:flutter/material.dart';

/// D-63: the family side of the Harvey app uses a teal scheme (as in Figs 4.3.16.1-3)
/// so a family sign-in or registration is easy to tell apart from a patient one.
const familySeed = Color(0xFF00695C);

ThemeData familyTheme(ThemeData base) => base.copyWith(
  colorScheme: ColorScheme.fromSeed(seedColor: familySeed, brightness: base.brightness),
);
