import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/iserv_calendar.dart';

class CalendarDayPage extends StatelessWidget {
  const CalendarDayPage({super.key, required this.day, required this.events});

  final DateTime day;
  final List<IservCalendarEvent> events;

  @override
  Widget build(BuildContext context) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final dayEvents = events.where((event) {
      final end = event.end ?? event.start;
      return event.start.isBefore(dayEnd) &&
          (end.isAfter(dayStart) || event.start.isAtSameMomentAs(dayStart));
    }).toList()..sort((a, b) => a.start.compareTo(b.start));

    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat('EEEE, dd.MM.yyyy', 'de_DE').format(day)),
      ),
      body: dayEvents.isEmpty
          ? const Center(child: Text('Keine Kalendereinträge für diesen Tag'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final event in dayEvents)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (event.isExam) ...[
                                Icon(
                                  Icons.assignment_late_outlined,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: Text(
                                  event.title,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(_eventTime(event)),
                          if (event.calendar.trim().isNotEmpty)
                            Text(
                              'Kalender: ${event.calendar.trim()}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          if (event.description.trim().isNotEmpty) ...[
                            const SizedBox(height: 10),
                            SelectableText(event.description.trim()),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  String _eventTime(IservCalendarEvent event) {
    final allDay =
        event.start.hour == 0 &&
        event.start.minute == 0 &&
        (event.end == null || event.end!.difference(event.start).inHours >= 23);
    if (allDay) return 'Ganztägig';
    final start = DateFormat('HH:mm').format(event.start);
    final end = event.end == null
        ? null
        : DateFormat('HH:mm').format(event.end!);
    return end == null ? start : '$start–$end';
  }
}
