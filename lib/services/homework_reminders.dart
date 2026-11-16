import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'app_settings.dart';
import 'iserv_calendar.dart';

class HomeworkReminders {
  HomeworkReminders._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> _initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Berlin'));
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _initialized = true;
  }

  static DateTime? reminderAt(
    String rawDueDate,
    AppSettings settings, {
    DateTime? now,
  }) {
    final parsed = DateTime.tryParse(rawDueDate.trim());
    if (parsed == null) return null;

    final due = rawDueDate.trim().length <= 10
        ? DateTime(parsed.year, parsed.month, parsed.day, 23, 59)
        : parsed;
    final reminderDay = DateTime(
      due.year,
      due.month,
      due.day,
    ).subtract(Duration(days: settings.reminderDaysBefore));
    final reminder = DateTime(
      reminderDay.year,
      reminderDay.month,
      reminderDay.day,
      settings.reminderHour,
      settings.reminderMinute,
    );
    if (!reminder.isAfter(now ?? DateTime.now()) || !reminder.isBefore(due)) {
      return null;
    }
    return reminder;
  }

  static int _notificationId(String key) {
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  static DateTime? calendarReminderAt(
    IservCalendarEvent event,
    AppSettings settings, {
    DateTime? now,
  }) {
    final isAllDay = event.start.hour == 0 &&
        event.start.minute == 0 &&
        (event.end == null ||
            event.end!.difference(event.start).inHours >= 23);
    final due = isAllDay
        ? DateTime(event.start.year, event.start.month, event.start.day, 23, 59)
        : event.start;
    final reminderDay = DateTime(
      due.year,
      due.month,
      due.day,
    ).subtract(Duration(days: settings.reminderDaysBefore));
    final reminder = DateTime(
      reminderDay.year,
      reminderDay.month,
      reminderDay.day,
      settings.reminderHour,
      settings.reminderMinute,
    );
    if (!reminder.isAfter(now ?? DateTime.now()) || !reminder.isBefore(due)) {
      return null;
    }
    return reminder;
  }

  static Future<bool> requestPermissions() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    await _initialize();
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (await android?.areNotificationsEnabled() == true) return true;
      return await android?.requestNotificationsPermission() ?? true;
    }
    return await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true) ??
        false;
  }

  static Future<void> sync(
    List<Map<String, dynamic>> tasks, {
    List<IservCalendarEvent> calendarEvents = const [],
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await _initialize();
    final settings = await AppSettingsStore().load();
    await _cancelReminderNotifications();
    if (!settings.homeworkRemindersEnabled) return;

    final candidates =
        <({int id, DateTime at, String heading, String title, String key})>[];
    if (settings.remindAboutHomework) {
      for (final task in tasks) {
      final due = task['due_date'] as String?;
      final title = (task['title'] as String? ?? '').trim();
      if (due == null || title.isEmpty) continue;
      final key = task['key']?.toString() ?? title;
      final at = reminderAt(due, settings);
      if (at == null) continue;
      candidates.add((
        id: _notificationId(key),
        at: at,
        heading: 'Hausaufgabe',
        title: title,
        key: 'homework:$key',
      ));
      }
    }
    if (settings.remindAboutCalendar && settings.syncIservCalendar) {
      for (final event in calendarEvents) {
        final title = event.title.trim();
        if (title.isEmpty) continue;
        final at = calendarReminderAt(event, settings);
        if (at == null) continue;
        final key = 'calendar:${event.id}';
        candidates.add((
          id: _notificationId(key),
          at: at,
          heading: 'Kalender',
          title: title,
          key: key,
        ));
      }
    }
    candidates.sort((a, b) => a.at.compareTo(b.at));

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'homework_reminders',
        'Hausaufgaben- und Kalender-Erinnerungen',
        channelDescription: 'Erinnerungen an Hausaufgaben und Kalendereinträge',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    for (final reminder in candidates.take(100)) {
      await _plugin.zonedSchedule(
        reminder.id,
        reminder.heading,
        reminder.title,
        tz.TZDateTime.from(reminder.at, tz.local),
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: reminder.key,
      );
    }
  }

  static Future<void> syncCalendarEvents(
    List<IservCalendarEvent> events,
  ) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await _initialize();
    final settings = await AppSettingsStore().load();
    if (!settings.homeworkRemindersEnabled) {
      await _cancelReminderNotifications();
      return;
    }
    await _cancelReminderNotifications(calendarOnly: true);
    if (!settings.remindAboutHomework) {
      await _cancelReminderNotifications(homeworkOnly: true);
    }
    if (!settings.remindAboutCalendar || !settings.syncIservCalendar) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'homework_reminders',
        'Hausaufgaben- und Kalender-Erinnerungen',
        channelDescription: 'Erinnerungen an Hausaufgaben und Kalendereinträge',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    final candidates = <({int id, DateTime at, String title, String key})>[];
    for (final event in events) {
      final title = event.title.trim();
      if (title.isEmpty) continue;
      final at = calendarReminderAt(event, settings);
      if (at == null) continue;
      final key = 'calendar:${event.id}';
      candidates.add((
        id: _notificationId(key),
        at: at,
        title: title,
        key: key,
      ));
    }
    candidates.sort((a, b) => a.at.compareTo(b.at));
    for (final reminder in candidates.take(100)) {
      await _plugin.zonedSchedule(
        reminder.id,
        'Kalender',
        reminder.title,
        tz.TZDateTime.from(reminder.at, tz.local),
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: reminder.key,
      );
    }
  }

  static Future<void> _cancelReminderNotifications({
    bool calendarOnly = false,
    bool homeworkOnly = false,
  }) async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final notification in pending) {
      final payload = notification.payload ?? '';
      final isHomework = payload.startsWith('homework:');
      final isCalendar = payload.startsWith('calendar:');
      final isLegacy = !isHomework && !isCalendar;
      if (calendarOnly && isCalendar ||
          homeworkOnly && isHomework ||
          !calendarOnly && !homeworkOnly && (isCalendar || isHomework || isLegacy)) {
        await _plugin.cancel(notification.id);
      }
    }
  }
}
