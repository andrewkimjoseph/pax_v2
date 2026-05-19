import 'package:flutter/material.dart' show Colors, FontStyle, FontWeight;
import 'package:google_fonts/google_fonts.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' show Typography;
import 'text_theme.dart';

/// A custom typography implementation for the Pax design system.
///
/// This class extends the shadcn Typography class to provide a consistent
/// typographic system throughout the application. It maps Flutter's TextTheme
/// to shadcn's Typography structure using Google Fonts Sen.
class PaxTypography extends Typography {
  PaxTypography()
    : super(
        sans: GoogleFonts.sen(textStyle: paxTextTheme.bodyMedium),
        mono: GoogleFonts.robotoMono(),

        xSmall: paxTextTheme.labelSmall!,
        small: paxTextTheme.bodySmall!,
        base: paxTextTheme.bodyMedium!,
        large: paxTextTheme.bodyLarge!,
        xLarge: paxTextTheme.titleSmall!,
        x2Large: paxTextTheme.titleMedium!,
        x3Large: paxTextTheme.titleLarge!,
        x4Large: paxTextTheme.headlineSmall!,
        x5Large: paxTextTheme.headlineMedium!,
        x6Large: paxTextTheme.headlineLarge!,
        x7Large: paxTextTheme.displaySmall!,
        x8Large: paxTextTheme.displayMedium!,
        x9Large: paxTextTheme.displayLarge!,

        thin: GoogleFonts.sen(
          textStyle: paxTextTheme.bodyMedium,
          fontWeight: FontWeight.w100,
        ),
        extraLight: GoogleFonts.sen(
          textStyle: paxTextTheme.bodyMedium,
          fontWeight: FontWeight.w200,
        ),
        light: GoogleFonts.sen(
          textStyle: paxTextTheme.bodyMedium,
          fontWeight: FontWeight.w300,
        ),
        normal: GoogleFonts.sen(
          textStyle: paxTextTheme.bodyMedium,
          fontWeight: FontWeight.w400,
        ),
        medium: GoogleFonts.sen(
          textStyle: paxTextTheme.bodyMedium,
          fontWeight: FontWeight.w500,
        ),
        semiBold: GoogleFonts.sen(
          textStyle: paxTextTheme.bodyMedium,
          fontWeight: FontWeight.w600,
        ),
        bold: GoogleFonts.sen(
          textStyle: paxTextTheme.bodyMedium,
          fontWeight: FontWeight.w700,
        ),
        extraBold: GoogleFonts.sen(
          textStyle: paxTextTheme.bodyMedium,
          fontWeight: FontWeight.w800,
        ),
        black: GoogleFonts.sen(
          textStyle: paxTextTheme.bodyMedium,
          fontWeight: FontWeight.w900,
        ),

        italic: GoogleFonts.sen(
          textStyle: paxTextTheme.bodyMedium,
          fontStyle: FontStyle.italic,
        ),

        h1: paxTextTheme.displayLarge!,
        h2: paxTextTheme.displayMedium!,
        h3: paxTextTheme.displaySmall!,
        h4: paxTextTheme.headlineMedium!,
        p: paxTextTheme.bodyMedium!,
        blockQuote: GoogleFonts.sen(
          textStyle: paxTextTheme.bodyLarge,
          fontStyle: FontStyle.italic,
        ),
        inlineCode: GoogleFonts.robotoMono(
          textStyle: paxTextTheme.bodyMedium,
        ),

        lead: GoogleFonts.sen(
          textStyle: paxTextTheme.bodyLarge,
          fontWeight: FontWeight.w500,
        ),
        textLarge: paxTextTheme.bodyLarge!,
        textSmall: paxTextTheme.bodySmall!,
        textMuted: GoogleFonts.sen(
          textStyle: paxTextTheme.bodyMedium!.copyWith(
            color: Colors.grey.shade600,
          ),
        ),
      );
}
