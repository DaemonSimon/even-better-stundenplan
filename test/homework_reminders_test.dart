import 'package:flutter_test/flutter_test.dart';

import 'package:better_stundenplan/services/app_settings.dart';
import 'package:better_stundenplan/services/homework_reminders.dart';
import 'package:better_stundenplan/services/iserv_calendar.dart';

void main() {
  test('plant die Erinnerung mit Vorlauf und eingestellter Uhrzeit', () {
    final reminder = HomeworkReminders.reminderAt(
      '2026-11-12T08:30',
      const AppSettings(
        reminderDaysBefore: 2,
        reminderHour: 17,
        reminderMinute: 15,
      ),
      now: DateTime(2026, 11, 9),
    );

    expect(reminder, DateTime(2026, 11, 10, 17, 15));
  });

  test('plant bei null Tagen am Fälligkeitstag', () {
    final reminder = HomeworkReminders.reminderAt(
      '2026-11-12',
      const AppSettings(reminderDaysBefore: 0, reminderHour: 18),
      now: DateTime(2026, 11, 11),
    );

    expect(reminder, DateTime(2026, 11, 12, 18));
  });

  test('überspringt verpasste und nach der Abgabe liegende Erinnerungen', () {
    expect(
      HomeworkReminders.reminderAt(
        '2026-11-10T08:00',
        const AppSettings(reminderDaysBefore: 1),
        now: DateTime(2026, 11, 9, 20),
      ),
      isNull,
    );
  });

  test('plant Kalendererinnerung vor einem terminierten Ereignis', () {
    final reminder = HomeworkReminders.calendarReminderAt(
      IservCalendarEvent(
        id: 'event-1',
        title: 'Klassenarbeit',
        start: DateTime(2026, 11, 12, 9),
      ),
      const AppSettings(
        reminderDaysBefore: 1,
        reminderHour: 18,
        reminderMinute: 30,
      ),
      now: DateTime(2026, 11, 10),
    );

    expect(reminder, DateTime(2026, 11, 11, 18, 30));
  });

  test('plant Alltags-Kalendererinnerung am selben Tag', () {
    final reminder = HomeworkReminders.calendarReminderAt(
      IservCalendarEvent(
        id: 'event-2',
        title: 'Wandertag',
        start: DateTime(2026, 11, 12),
      ),
      const AppSettings(reminderDaysBefore: 0, reminderHour: 18),
      now: DateTime(2026, 11, 11),
    );

    expect(reminder, DateTime(2026, 11, 12, 18));
  });

  test('Erinnerungsarten lassen sich unabhängig deaktivieren', () {
    const settings = AppSettings(
      homeworkRemindersEnabled: true,
      remindAboutHomework: false,
      remindAboutCalendar: true,
    );

    expect(settings.remindAboutHomework, isFalse);
    expect(settings.remindAboutCalendar, isTrue);
    expect(
      settings
          .copyWith(remindAboutHomework: true, remindAboutCalendar: false)
          .remindAboutHomework,
      isTrue,
    );
    expect(
      settings
          .copyWith(remindAboutHomework: true, remindAboutCalendar: false)
          .remindAboutCalendar,
      isFalse,
    );
  });
}
