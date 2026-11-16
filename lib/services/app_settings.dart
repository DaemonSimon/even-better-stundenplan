import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class AppSettings {
  const AppSettings({
    this.homeworkRemindersEnabled = false,
    this.remindAboutHomework = true,
    this.remindAboutCalendar = true,
    this.reminderDaysBefore = 1,
    this.reminderHour = 18,
    this.reminderMinute = 0,
    this.syncIservCalendar = false,
  });

  final bool homeworkRemindersEnabled;
  final bool remindAboutHomework;
  final bool remindAboutCalendar;
  final int reminderDaysBefore;
  final int reminderHour;
  final int reminderMinute;
  final bool syncIservCalendar;

  AppSettings copyWith({
    bool? homeworkRemindersEnabled,
    bool? remindAboutHomework,
    bool? remindAboutCalendar,
    int? reminderDaysBefore,
    int? reminderHour,
    int? reminderMinute,
    bool? syncIservCalendar,
  }) => AppSettings(
    homeworkRemindersEnabled:
        homeworkRemindersEnabled ?? this.homeworkRemindersEnabled,
    remindAboutHomework: remindAboutHomework ?? this.remindAboutHomework,
    remindAboutCalendar: remindAboutCalendar ?? this.remindAboutCalendar,
    reminderDaysBefore: reminderDaysBefore ?? this.reminderDaysBefore,
    reminderHour: reminderHour ?? this.reminderHour,
    reminderMinute: reminderMinute ?? this.reminderMinute,
    syncIservCalendar: syncIservCalendar ?? this.syncIservCalendar,
  );
}

class AppSettingsStore {
  AppSettingsStore();

  static const _remindersEnabledKey = 'homework_reminders_enabled';
  static const _remindAboutHomeworkKey = 'remind_about_homework';
  static const _remindAboutCalendarKey = 'remind_about_calendar';
  static const _reminderDaysKey = 'homework_reminder_days_before';
  static const _reminderHourKey = 'homework_reminder_hour';
  static const _reminderMinuteKey = 'homework_reminder_minute';
  static const _calendarSyncKey = 'iserv_calendar_sync_enabled';

  static final ValueNotifier<int> revision = ValueNotifier(0);

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      homeworkRemindersEnabled: prefs.getBool(_remindersEnabledKey) ?? false,
      remindAboutHomework: prefs.getBool(_remindAboutHomeworkKey) ?? true,
      remindAboutCalendar: prefs.getBool(_remindAboutCalendarKey) ?? true,
      reminderDaysBefore: (prefs.getInt(_reminderDaysKey) ?? 1).clamp(0, 7),
      reminderHour: (prefs.getInt(_reminderHourKey) ?? 18).clamp(0, 23),
      reminderMinute: (prefs.getInt(_reminderMinuteKey) ?? 0).clamp(0, 59),
      syncIservCalendar: prefs.getBool(_calendarSyncKey) ?? false,
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      _remindersEnabledKey,
      settings.homeworkRemindersEnabled,
    );
    await prefs.setBool(
      _remindAboutHomeworkKey,
      settings.remindAboutHomework,
    );
    await prefs.setBool(
      _remindAboutCalendarKey,
      settings.remindAboutCalendar,
    );
    await prefs.setInt(
      _reminderDaysKey,
      settings.reminderDaysBefore.clamp(0, 7),
    );
    await prefs.setInt(_reminderHourKey, settings.reminderHour.clamp(0, 23));
    await prefs.setInt(
      _reminderMinuteKey,
      settings.reminderMinute.clamp(0, 59),
    );
    await prefs.setBool(_calendarSyncKey, settings.syncIservCalendar);
    revision.value++;
  }
}
