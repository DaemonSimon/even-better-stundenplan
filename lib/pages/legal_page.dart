import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Öffnet die in der App mitgelieferte Datenschutzerklärung.
void openPrivacyPolicy(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const PrivacyPolicyPage()),
  );
}

bool _appLicenseRegistered = false;

/// Zeigt die Lizenzen der App und aller verwendeten Pakete.
void openLicenses(BuildContext context) {
  if (!_appLicenseRegistered) {
    _appLicenseRegistered = true;
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks(const [
        'better_stundenplan',
      ], await rootBundle.loadString('LICENSE'));
    });
  }
  showLicensePage(context: context, applicationName: 'Better Stundenplan');
}

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  static const String asset = 'assets/datenschutz.md';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Datenschutzerklärung')),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(asset),
        builder: (context, snapshot) {
          final text = snapshot.data;
          if (text == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return SelectionArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final line in text.split('\n'))
                    // Nur Überschriften und Absätze: mehr nutzt die Datei nicht.
                    if (line.startsWith('#'))
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 4),
                        child: Text(
                          line.replaceFirst(RegExp(r'^#+\s*'), ''),
                          style: theme.textTheme.titleMedium,
                        ),
                      )
                    else if (line.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(line),
                      ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
