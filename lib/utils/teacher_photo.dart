import 'package:flutter/material.dart';

/// Zeigt das Portrait-Foto einer Lehrkraft in einem Dialog.
///
/// Nutzt [teacherDisplay] (voller Name, ggf. mit Kürzel) als Titel; lädt das
/// Bild über [photoUrl] und zeigt bei einem Fehler ein Platzhalter-Icon.
void showTeacherPhotoDialog(
  BuildContext context,
  String teacherDisplay,
  String photoUrl,
) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                photoUrl,
                width: 240,
                height: 240,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => SizedBox(
                  width: 240,
                  height: 240,
                  child: Icon(
                    Icons.person_off,
                    size: 64,
                    color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              teacherDisplay,
              style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}