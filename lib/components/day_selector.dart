import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Horizontaler Pill-Selector für die fünf Wochentage (Mo–Fr).
/// Ausgewählter Tag ist mit der Primärfarbe gefüllt, der heutige Tag
/// bekommt einen Punkt als Marker.
class DaySelector extends StatelessWidget {
  const DaySelector({
    super.key,
    required this.days,
    required this.selectedIndex,
    required this.onSelected,
    this.todayIndex,
  });

  /// Wochentage (Mo–Fr), die angezeigt werden.
  final List<DateTime> days;

  /// Aktuell ausgewählter Index (0 = Montag).
  final int selectedIndex;

  final ValueChanged<int> onSelected;

  /// Index des heutigen Tages, falls er in der Woche liegt.
  final int? todayIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < days.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _DayPill(
                day: days[i],
                selected: i == selectedIndex,
                isToday: i == todayIndex,
                onTap: () => onSelected(i),
              ),
            ),
          ),
      ],
    );
  }
}

class _DayPill extends StatelessWidget {
  const _DayPill({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.onPrimary : scheme.onSurface;
    final accent = selected ? scheme.onPrimary : scheme.primary;

    return Material(
      color: selected ? scheme.primary : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Text(
                DateFormat('E').format(day),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: isToday ? accent : foreground,
                  fontWeight: isToday || selected
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${day.day}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: foreground,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: isToday ? accent : Colors.transparent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}