import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:better_stundenplan/services/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('lädt sinnvolle Erinnerungs-Defaults', () async {
    final settings = await AppSettingsStore().load();

    expect(settings.homeworkRemindersEnabled, isFalse);
    expect(settings.remindAboutHomework, isTrue);
    expect(settings.remindAboutCalendar, isTrue);
    expect(settings.reminderDaysBefore, 1);
    expect(settings.reminderHour, 18);
    expect(settings.reminderMinute, 0);
    expect(settings.syncIservCalendar, isFalse);
  });

  test('speichert Erinnerungs- und Kalendersync-Einstellungen lokal', () async {
    final store = AppSettingsStore();
    await store.save(
      const AppSettings(
        homeworkRemindersEnabled: false,
        remindAboutHomework: false,
        remindAboutCalendar: true,
        reminderDaysBefore: 3,
        reminderHour: 7,
        reminderMinute: 45,
        syncIservCalendar: true,
      ),
    );

    final loaded = await AppSettingsStore().load();
    expect(loaded.homeworkRemindersEnabled, isFalse);
    expect(loaded.remindAboutHomework, isFalse);
    expect(loaded.remindAboutCalendar, isTrue);
    expect(loaded.reminderDaysBefore, 3);
    expect(loaded.reminderHour, 7);
    expect(loaded.reminderMinute, 45);
    expect(loaded.syncIservCalendar, isTrue);
  });
}
