import 'package:flutter/material.dart';
import 'package:flutter_custom_tabs/flutter_custom_tabs.dart';
import 'package:flutter_custom_tabs_platform_interface/flutter_custom_tabs_platform_interface.dart';

import '../services/teacher_directory.dart';

/// Adresse der Lehrkraft auf der öffentlichen Kollegiumsseite. Die
/// Sprungmarke `kuerzel-<KÜRZEL>` scrollt zur Person, das Text-Fragment
/// lässt den Browser den Namen farbig markieren.
///
/// Bewusst ein String: [Uri] würde das nötige `%2D` (Bindestrich in
/// Doppelnamen) zurückverwandeln, und die Markierung fiele weg.
String teacherPageUrl(String kuerzel, String fullName) {
  String text(String value) =>
      Uri.encodeComponent(value).replaceAll('-', '%2D');
  return 'https://start.bbs-papenburg.de/kollegium.php'
      '#kuerzel-${Uri.encodeComponent(kuerzel.toUpperCase())}'
      ':~:text=${text(fullName)}';
}

/// Öffnet die Seite als Custom Tab: Der Browser zeigt sie unverändert als
/// Blatt über der App, nur die Leiste bekommt die App-Farbe. Browser ohne
/// Teilansicht zeigen sie bildschirmfüllend.
///
/// Über die Plattform-Schnittstelle, weil sie die Adresse als String
/// annimmt (siehe [teacherPageUrl]).
Future<void> _openCustomTab(String url, double height, Color toolbarColor) =>
    CustomTabsPlatform.instance.launch(
      url,
      customTabsOptions: CustomTabsOptions.partial(
        configuration: PartialCustomTabsConfiguration(initialHeight: height),
        colorSchemes: CustomTabsColorSchemes.defaults(
          toolbarColor: toolbarColor,
        ),
        showTitle: true,
      ),
    );

/// Dialog mit einem Link zur Lehrkraft auf der Schulwebsite.
void showTeacherPhotoDialog(
  BuildContext context,
  String teacherDisplay,
  TeacherEntry teacher,
) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(teacherDisplay),
      content: const Text(
        'Das Foto steht auf der Website der Schule. Der Name ist dort '
        'farbig markiert.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.open_in_new),
          label: const Text('Foto ansehen'),
          onPressed: () async {
            final messenger = ScaffoldMessenger.maybeOf(context);
            final height = MediaQuery.sizeOf(context).height * 0.8;
            final color = Theme.of(context).colorScheme.primaryContainer;
            Navigator.of(dialogContext).pop();
            try {
              await _openCustomTab(
                teacherPageUrl(teacher.kuerzel, teacher.fullName),
                height,
                color,
              );
            } on Exception {
              messenger?.showSnackBar(
                const SnackBar(
                  content: Text('Browser konnte nicht geöffnet werden.'),
                ),
              );
            }
          },
        ),
      ],
    ),
  );
}
