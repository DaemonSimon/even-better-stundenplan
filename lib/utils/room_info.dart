import 'package:flutter/material.dart';

/// Extrahiert Gebäude, Etage und Raumnummer aus einem Raum-Kürzel
/// wie "C119" → Gebäude C, Etage 1, Raum 19.
class RoomInfo {
  const RoomInfo({this.building, this.floor, this.room});

  final String? building;
  final String? floor;
  final String? room;
}

/// Parst ein Raum-Kürzel: führende Buchstaben = Gebäude,
/// erste Ziffer = Etage, restliche Ziffern = Raumnummer.
RoomInfo? parseRoomInfo(String raw) {
  final room = raw.trim();
  if (room.isEmpty) return null;
  final match = RegExp(r'^([A-Za-z]+)?(\d+)$').firstMatch(room);
  if (match == null) return null;
  final building = match.group(1);
  final digits = match.group(2)!;
  if (digits.length >= 2) {
    return RoomInfo(
      building: building,
      floor: digits.substring(0, 1),
      room: digits.substring(1),
    );
  }
  return RoomInfo(building: building, room: digits);
}

/// Öffnet einen Dialog, der Gebäude/Etage/Raum eines Raum-Kürzels erklärt.
void showRoomInfoDialog(BuildContext context, String raw) {
  final info = parseRoomInfo(raw);
  if (info == null) return;
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.meeting_room, size: 22),
          const SizedBox(width: 8),
          Text(raw.trim()),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (info.building != null)
            _RoomInfoRow(
              icon: Icons.apartment,
              label: 'Gebäude',
              value: info.building!,
            ),
          if (info.floor != null)
            _RoomInfoRow(
              icon: Icons.stairs,
              label: 'Etage',
              value: info.floor!,
            ),
          if (info.room != null)
            _RoomInfoRow(
              icon: Icons.door_sliding_outlined,
              label: 'Raum',
              value: info.room!,
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Schließen'),
        ),
      ],
    ),
  );
}

class _RoomInfoRow extends StatelessWidget {
  const _RoomInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}