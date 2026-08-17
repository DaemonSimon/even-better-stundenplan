import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../utils/simulated_clock.dart';

/// Debug-Menü für die simulierte Uhr: aktuelle Zeit und Datum setzen,
/// Geschwindigkeit wählen (z. B. x60, um die Live-Effekte zu sehen),
/// zurück zur Echtzeit.
class DebugClockSheet extends StatefulWidget {
  const DebugClockSheet({
    super.key,
    required this.clock,
    this.onDatePicked,
  });

  final SimulatedClock clock;

  /// Wird aufgerufen, wenn der Nutzer ein Datum wählt (damit die
  /// Tagesansicht zur simulierten Woche springt).
  final ValueChanged<DateTime>? onDatePicked;

  @override
  State<DebugClockSheet> createState() => _DebugClockSheetState();
}

class _DebugClockSheetState extends State<DebugClockSheet> {
  static final _presetTimes = <TimeOfDay>[
    const TimeOfDay(hour: 8, minute: 10),
    const TimeOfDay(hour: 9, minute: 40),
    const TimeOfDay(hour: 10, minute: 0),
    const TimeOfDay(hour: 11, minute: 45),
    const TimeOfDay(hour: 12, minute: 30),
    const TimeOfDay(hour: 13, minute: 15),
    const TimeOfDay(hour: 13, minute: 45),
    const TimeOfDay(hour: 14, minute: 30),
  ];

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final now = widget.clock.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (picked == null || !mounted) return;
    widget.clock.setTime(
      DateTime(now.year, now.month, now.day, picked.hour, picked.minute),
    );
  }

  Future<void> _pickDate() async {
    final now = widget.clock.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1, now.month, now.day),
      lastDate: DateTime(now.year + 1, now.month, now.day),
    );
    if (picked == null || !mounted) return;
    widget.clock.setTime(
      DateTime(picked.year, picked.month, picked.day, now.hour, now.minute),
    );
    widget.onDatePicked?.call(picked);
  }

  void _setPreset(TimeOfDay time) {
    final now = widget.clock.now();
    widget.clock.setTime(
      DateTime(now.year, now.month, now.day, time.hour, time.minute),
    );
  }

  void _setCurrentTime() => widget.clock.setTime(DateTime.now());

  int _speedIndex(double speed) {
    var best = 0;
    for (var i = 0; i < SimulatedClock.speedSteps.length; i++) {
      if ((SimulatedClock.speedSteps[i] - speed).abs() <
          (SimulatedClock.speedSteps[best] - speed).abs()) {
        best = i;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clock = widget.clock;
    final sim = clock.now();

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Debug-Uhr',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
              DateFormat('HH:mm:ss').format(sim),
              textAlign: TextAlign.center,
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              DateFormat('EEEE, dd.MM.yyyy').format(sim),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule),
                    label: const Text('Uhrzeit'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_month),
                    label: const Text('Datum'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final time in _presetTimes)
                  ActionChip(
                    label: Text(
                      DateFormat('HH:mm').format(
                        DateTime(0, 1, 1, time.hour, time.minute),
                      ),
                    ),
                    onPressed: () => _setPreset(time),
                  ),
                ActionChip(
                  label: const Text('Aktuell'),
                  onPressed: _setCurrentTime,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Geschwindigkeit', style: theme.textTheme.bodyMedium),
                const Spacer(),
                Text(
                  'x${clock.speed.round()}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Slider(
              value: _speedIndex(clock.speed).toDouble(),
              min: 0,
              max: (SimulatedClock.speedSteps.length - 1).toDouble(),
              divisions: SimulatedClock.speedSteps.length - 1,
              label: 'x${clock.speed.round()}',
              onChanged: (value) =>
                  clock.setSpeed(SimulatedClock.speedSteps[value.round()]),
            ),
            const SizedBox(height: 4),
            FilledButton.tonalIcon(
              onPressed: clock.reset,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Auf Echtzeit zurücksetzen'),
            ),
          ],
        ),
        ),
      ),
    );
  }
}