import 'package:flutter/material.dart';

import 'class_card.dart';

/// Füllfarbe des ausgewählten Buttons – eine flache, etwas hellere
/// Variante des Karten-Hintergrunds, kein Glow, kein Schatten.
const Color _selectedSegmentBg = Color(0xFF4A4F5E);

/// Öffnet das minimale Einstellungs-Sheet mit der Kursgruppen-Auswahl
/// (Regel 5).
Future<void> showGroupSettingsSheet(
  BuildContext context, {
  required String? group,
  required ValueChanged<String?> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: appBackground,
    showDragHandle: true,
    builder: (sheetContext) => GroupSettingsSheet(
      group: group,
      onChanged: onChanged,
    ),
  );
}

/// Flaches, dunkles Einstellungs-Sheet: "Einstellungen" -> "Kursgruppe"
/// mit zwei schlichten Buttons (A/B) auf dem Karten-Hintergrund.
class GroupSettingsSheet extends StatelessWidget {
  const GroupSettingsSheet({
    super.key,
    required this.group,
    required this.onChanged,
  });

  /// Aktuell gespeicherte Gruppe (z. B. "A") oder null.
  final String? group;

  /// Wird mit der gewählten Gruppe (oder null) aufgerufen, nachdem das
  /// Sheet geschlossen wurde.
  final ValueChanged<String?> onChanged;

  void _select(BuildContext context, String? value) {
    Navigator.of(context).pop();
    onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Einstellungen',
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Kursgruppe',
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Zeigt nur die Kurse deiner Gruppe – Gruppen-Präfixe '
              '"A:"/"B:" verschwinden aus den Karten.',
              style: theme.textTheme.bodySmall?.copyWith(color: cardGrey),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _GroupSegment(
                    label: 'A',
                    selected: group?.toUpperCase() == 'A',
                    onTap: () => _select(context, 'A'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _GroupSegment(
                    label: 'B',
                    selected: group?.toUpperCase() == 'B',
                    onTap: () => _select(context, 'B'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Einzelner flacher Auswahl-Button (A oder B) im "Segmented"-Stil.
class _GroupSegment extends StatelessWidget {
  const _GroupSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cardBackground,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? _selectedSegmentBg : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : cardGrey,
              fontSize: 16,
              fontWeight: selected ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}