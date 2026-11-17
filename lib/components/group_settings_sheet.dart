import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../services/homework_reminders.dart';
import '../services/iserv_logout.dart';
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
  VoidCallback? onSettingsChanged,
  VoidCallback? onLogout,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: appBackground,
    showDragHandle: true,
    builder: (sheetContext) => GroupSettingsSheet(
      group: group,
      onChanged: onChanged,
      onSettingsChanged: onSettingsChanged,
      onLogout: onLogout,
    ),
  );
}

/// Flaches, dunkles Einstellungs-Sheet: "Einstellungen" -> "Kursgruppe"
/// mit zwei schlichten Buttons (A/B) auf dem Karten-Hintergrund.
class GroupSettingsSheet extends StatefulWidget {
  const GroupSettingsSheet({
    super.key,
    required this.group,
    required this.onChanged,
    this.onSettingsChanged,
    this.onLogout,
  });

  /// Aktuell gespeicherte Gruppe (z. B. "A") oder null.
  final String? group;

  /// Wird mit der gewählten Gruppe (oder null) aufgerufen, nachdem das
  /// Sheet geschlossen wurde.
  final ValueChanged<String?> onChanged;
  final VoidCallback? onSettingsChanged;

  /// Abmelden vom Stundenplan-Konto (nach Bestätigung, Sheet ist zu).
  final VoidCallback? onLogout;

  @override
  State<GroupSettingsSheet> createState() => _GroupSettingsSheetState();
}

class _GroupSettingsSheetState extends State<GroupSettingsSheet> {
  AppSettings _settings = const AppSettings();
  bool _loading = true;
  bool _iservLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await AppSettingsStore().load();
    final iservLoggedIn = await isIservLoginStored();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _iservLoggedIn = iservLoggedIn;
      _loading = false;
    });
  }

  Future<void> _saveSettings(AppSettings settings) async {
    if (settings.homeworkRemindersEnabled &&
        !_settings.homeworkRemindersEnabled) {
      final granted = await HomeworkReminders.requestPermissions();
      if (!granted) {
        settings = settings.copyWith(homeworkRemindersEnabled: false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Benachrichtigungen sind nicht freigegeben'),
            ),
          );
        }
      }
    }
    await AppSettingsStore().save(settings);
    if (!mounted) return;
    setState(() => _settings = settings);
    widget.onSettingsChanged?.call();
  }

  void _select(BuildContext context, String? value) {
    Navigator.of(context).pop();
    widget.onChanged(value);
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Abmelden?'),
        content: const Text(
          'Gespeicherte Zugangsdaten für den Stundenplan werden gelöscht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Abmelden'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.of(context).pop();
    widget.onLogout?.call();
  }

  Future<void> _confirmIservLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Von IServ abmelden?'),
        content: const Text(
          'Gespeicherte IServ-Aufgaben und vorab geladene Dateien werden '
          'vom Gerät gelöscht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Abmelden'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await logoutFromIserv();
    if (!mounted) return;
    setState(() => _iservLoggedIn = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Von IServ abgemeldet')));
  }

  Future<void> _chooseReminderTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _settings.reminderHour,
        minute: _settings.reminderMinute,
      ),
    );
    if (time == null) return;
    await _saveSettings(
      _settings.copyWith(reminderHour: time.hour, reminderMinute: time.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
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
                'Zeigt nur die Kurse deiner Gruppe an',
                style: theme.textTheme.bodySmall?.copyWith(color: cardGrey),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _GroupSegment(
                      label: 'A',
                      selected: widget.group?.toUpperCase() == 'A',
                      onTap: () => _select(context, 'A'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _GroupSegment(
                      label: 'B',
                      selected: widget.group?.toUpperCase() == 'B',
                      onTap: () => _select(context, 'B'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Hausaufgabenerinnerung',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator(),
                )
              else ...[
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Erinnerungen aktivieren'),
                  value: _settings.homeworkRemindersEnabled,
                  onChanged: (value) => _saveSettings(
                    _settings.copyWith(homeworkRemindersEnabled: value),
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Hausaufgaben'),
                  value: _settings.remindAboutHomework,
                  onChanged: _settings.homeworkRemindersEnabled
                      ? (value) => _saveSettings(
                          _settings.copyWith(remindAboutHomework: value),
                        )
                      : null,
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Kalendertermine'),
                  subtitle: _settings.syncIservCalendar
                      ? null
                      : const Text(
                          'Aktiviere zuerst die IServ-Kalendersynchronisierung',
                        ),
                  value: _settings.remindAboutCalendar,
                  onChanged:
                      _settings.homeworkRemindersEnabled &&
                          _settings.syncIservCalendar
                      ? (value) => _saveSettings(
                          _settings.copyWith(remindAboutCalendar: value),
                        )
                      : null,
                ),
                Row(
                  children: [
                    const Expanded(child: Text('Erinnern')),
                    DropdownButton<int>(
                      value: _settings.reminderDaysBefore,
                      items: [
                        for (var days = 0; days <= 7; days++)
                          DropdownMenuItem(
                            value: days,
                            child: Text(
                              days == 0 ? 'Am selben Tag' : '$days Tage vorher',
                            ),
                          ),
                      ],
                      onChanged: _settings.homeworkRemindersEnabled
                          ? (days) {
                              if (days == null) return;
                              _saveSettings(
                                _settings.copyWith(reminderDaysBefore: days),
                              );
                            }
                          : null,
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: _settings.homeworkRemindersEnabled
                        ? _chooseReminderTime
                        : null,
                    icon: const Icon(Icons.schedule),
                    label: Text(
                      'Uhrzeit ${_formatTime(_settings.reminderHour, _settings.reminderMinute)}',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Stundenplan',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mit IServ-Kalender synchronisieren'),
                  value: _settings.syncIservCalendar,
                  onChanged: (value) => _saveSettings(
                    _settings.copyWith(syncIservCalendar: value),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'IServ',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aufgaben-Dateien vorab laden'),
                  subtitle: const Text(
                    'Anhänge laufender Aufgaben automatisch speichern, damit '
                    'sie auch offline öffnen. Ausschalten löscht die '
                    'gespeicherten Dateien.',
                  ),
                  value: _settings.preloadIservFiles,
                  onChanged: (value) => _saveSettings(
                    _settings.copyWith(preloadIservFiles: value),
                  ),
                ),
                if (_iservLoggedIn) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _confirmIservLogout,
                    icon: const Icon(Icons.logout),
                    label: const Text('Von IServ abmelden'),
                  ),
                ],
                if (widget.onLogout != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Konto',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _confirmLogout,
                    icon: const Icon(Icons.logout),
                    label: const Text('Vom Stundenplan abmelden'),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
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
