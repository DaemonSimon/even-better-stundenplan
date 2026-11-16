import 'package:intl/date_symbol_data_local.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:better_stundenplan/pages/calendar_day_page.dart';
import 'package:better_stundenplan/services/iserv_calendar.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('de_DE');
  });

  testWidgets('zeigt alle Kalendereinträge des Tages samt Beschreibung', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CalendarDayPage(
          day: DateTime(2026, 11, 12),
          events: [
            IservCalendarEvent(
              id: 'one',
              title: 'Klassenarbeit',
              start: DateTime(2026, 11, 12, 9),
              end: DateTime(2026, 11, 12, 10),
              description: 'Kapitel 1 bis 4 lernen',
            ),
            IservCalendarEvent(
              id: 'two',
              title: 'Elternabend',
              start: DateTime(2026, 11, 12, 18),
              description: 'Raum 204',
            ),
            IservCalendarEvent(
              id: 'other-day',
              title: 'Anderer Tag',
              start: DateTime(2026, 11, 13, 9),
            ),
          ],
        ),
      ),
    );

    expect(find.text('Klassenarbeit'), findsOneWidget);
    expect(find.text('Elternabend'), findsOneWidget);
    expect(find.text('Kapitel 1 bis 4 lernen'), findsOneWidget);
    expect(find.text('Raum 204'), findsOneWidget);
    expect(find.text('Anderer Tag'), findsNothing);
  });
}
