import 'package:flutter/material.dart';

/// Deterministische Fach-Farben: Ein Fach bekommt immer dieselbe Farbe,
/// ohne dass eine Speicherung nötig wäre.
///
/// Statt eines Regenbogens über alle Fächer wird nur nach Fächergruppen
/// unterschieden (MINT, Sprachen, Gesellschaft, …) – bewusst gedeckte,
/// harmonische Töne statt eines bunten Palettes.
class SubjectColors {
  /// MINT: Mathematik, Physik, Chemie, Biologie, Informatik …
  static const Color _mint = Color(0xFF3D6B8E);

  /// Sprachen: Deutsch, Englisch, Französisch, Spanisch, Latein …
  static const Color _languages = Color(0xFFA65A42);

  /// Gesellschaftswissenschaften: Politik, Geschichte, Erdkunde …
  static const Color _society = Color(0xFF8A7A3B);

  /// Religion / Ethik.
  static const Color _religion = Color(0xFF8F6D52);

  /// Kunst / Musik.
  static const Color _arts = Color(0xFF7C5C8C);

  /// Sport.
  static const Color _sport = Color(0xFF4F7A52);

  static const Color _fallback = Color(0xFF9E9E9E);

  /// Kürzel, die exakt (lowercase) auf eine Gruppe fallen.
  static const Map<String, Color> _codes = {
    'ma': _mint, 'ph': _mint, 'ch': _mint, 'bi': _mint,
    'in': _mint, 'if': _mint, 'nw': _mint,
    'de': _languages, 'en': _languages, 'fr': _languages,
    'la': _languages, 'gr': _languages, 'ru': _languages,
    'po': _society, 'pw': _society, 'gs': _society,
    'ek': _society, 'ge': _society, 'so': _society,
    're': _religion, 'et': _religion, 'ev': _religion, 'ka': _religion,
    'ku': _arts, 'mu': _arts,
    'sp': _sport, 'spo': _sport,
  };

  /// Vollnamen (Teilstring reicht), die auf eine Gruppe fallen.
  static const Map<String, Color> _names = {
    'mathe': _mint, 'mathematik': _mint, 'physik': _mint, 'chemie': _mint,
    'biologie': _mint, 'informatik': _mint, 'naturwissenschaft': _mint,
    'deutsch': _languages, 'englisch': _languages, 'französisch': _languages,
    'spanisch': _languages, 'latein': _languages, 'italienisch': _languages,
    'russisch': _languages,
    'politik': _society, 'geschichte': _society, 'erdkunde': _society,
    'geografie': _society, 'sozialkunde': _society,
    'religion': _religion, 'ethik': _religion, 'evangelisch': _religion,
    'katholisch': _religion,
    'kunst': _arts, 'musik': _arts, 'chor': _arts, 'orchester': _arts,
    'sport': _sport, 'bewegung': _sport,
  };

  static Color forSubject(String subject) {
    final normalized = subject.toLowerCase().trim();
    if (normalized.isEmpty) return _fallback;

    final byCode = _codes[normalized];
    if (byCode != null) return byCode;

    for (final entry in _names.entries) {
      if (normalized.contains(entry.key)) return entry.value;
    }
    return _fallback;
  }

  /// Weicher Pastell-Hintergrund für eine Fach-Karte, abgestimmt auf das
  /// aktuelle Farb-Theme (hell/dunkel). Text darauf: `scheme.onSurface`.
  static Color pastelBackgroundFor(String subject, ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    final base = isDark ? scheme.surfaceContainerHighest : scheme.surface;
    final tint = forSubject(subject).withValues(alpha: isDark ? 0.30 : 0.14);
    return Color.alphaBlend(tint, base);
  }
}