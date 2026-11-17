import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Willkommensbildschirm beim allerersten Start: erklärt kurz, was die
/// App kann und welche Anmeldungen es gibt.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  static const String _prefsKey = 'welcome_done';

  /// Wurde der Willkommensbildschirm schon einmal abgeschlossen?
  static Future<bool> isDone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefsKey) ?? false;
    } catch (_) {
      return true; // Im Zweifel nicht blockieren.
    }
  }

  static Future<void> _markDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
  }

  Future<void> _finish(BuildContext context, String location) async {
    await _markDone();
    if (context.mounted) context.go(location);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.calendar_view_day_rounded,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Willkommen bei Better Stundenplan',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 32),
              const _Point(
                icon: Icons.view_agenda_outlined,
                title: 'Dein Stundenplan',
                text:
                    'Melde dich mit deiner E-Mail und deinem Schülercode von '
                    'virtueller-stundenplan.org an. Vertretungen werden rot '
                    'markiert.',
              ),
              const _Point(
                icon: Icons.assignment_outlined,
                title: 'Hausaufgaben & Klausuren',
                text:
                    'Trage Hausaufgaben direkt in einer Stunde ein. Optional '
                    'kannst du dich bei IServ anmelden – dann siehst du auch '
                    'deine IServ-Aufgaben und Klausuren.',
              ),
              const _Point(
                icon: Icons.lock_outline,
                title: 'Deine Daten bleiben bei dir',
                text:
                    'Zugangsdaten werden verschlüsselt nur auf diesem Gerät '
                    'gespeichert. Dein Passwortmanager kann sie ausfüllen.',
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => _finish(context, '/authenticate'),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text("Los geht's – anmelden"),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => _finish(context, '/'),
                child: const Text('Erst mal umsehen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(text, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
