import 'package:flutter/material.dart' show TextTheme, Typography;
import 'package:google_fonts/google_fonts.dart';

/// The default text theme for the Pax design system.
///
/// Sen is loaded at runtime via Google Fonts so weight axes resolve correctly.
final TextTheme paxTextTheme = GoogleFonts.senTextTheme(
  Typography.material2021().black,
);
