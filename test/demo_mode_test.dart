import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:better_stundenplan/services/demo_mode.dart';
import 'package:better_stundenplan/services/iserv_calendar.dart';
import 'package:better_stundenplan/services/iserv_session.dart';
import 'package:better_stundenplan/services/iserv_task_detail.dart';
import 'package:better_stundenplan/services/iserv_tasks.dart';
import 'package:better_stundenplan/services/secure_storage.dart';
import 'package:better_stundenplan/services/session_manager.dart';
import 'package:better_stundenplan/services/stundenplan_api.dart';
import 'package:better_stundenplan/services/stundenplan_parser.dart';
import 'package:better_stundenplan/services/teacher_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    DemoMode.active.value = false;
  });
  tearDown(() => DemoMode.active.value = false);

  test('demo/demo meldet an und liefert Plan und Lehrkräfte', () async {
    final manager = SessionManager(storage: SecureCredentialStorage());

    expect(await manager.login(email: 'demo', password: 'demo'), isTrue);
    expect(DemoMode.active.value, isTrue);
    expect(await manager.checkAuthentication(), isTrue);

    final response = await StundenplanApi().fetchWeek('demo', '23.11.2026');
    final week = StundenplanParser().parseWeeklyTimetable(response.body);
    expect(week, hasLength(5));
    expect(week.every((day) => day.isNotEmpty), isTrue);
    expect(week[1].first.lessons.first.substituteTeacher, 'TESF');
    expect(week[2].any((slot) => slot.lessons.length == 2), isTrue);

    final teachers = await TeacherDirectory().fetch();
    expect(teachers['BEIE']?.fullName, 'Erika Beispiel');

    await manager.logout();
    expect(DemoMode.active.value, isFalse);
  });

  test('IServ im Demo-Modus: Aufgaben, Details, Datei, Kalender', () async {
    await DemoMode.enter();
    final session = IservSession();
    await session.restore();
    expect(await session.isAuthenticated(), isFalse);
    await expectLater(
      session.login('demo', 'falsch'),
      throwsA(isA<IservLoginException>()),
    );

    expect(await session.login('demo', 'demo'), isTrue);
    expect(await session.ensureAuthenticated(), isTrue);

    final open = await fetchTasks(session);
    expect(open.map((t) => t.title), contains('Netzwerkplan zeichnen'));
    expect(open.first.dueDate, isNotNull);
    expect(await fetchPastTasks(session), hasLength(1));

    final detail = parseTaskDetail(
      (await session.get(open.first.links.first)).body,
      baseUrl: session.baseUrl,
    );
    expect(detail.title, 'Netzwerkplan zeichnen');
    expect(detail.dueDate, isNotNull);
    expect(detail.attachments.single.name, 'Arbeitsblatt.txt');
    final file = await session.get(detail.attachments.single.downloadUrl);
    expect(file.statusCode, 200);

    final events = await fetchIservCalendar(session);
    expect(events.where((e) => e.isExam), hasLength(1));
  });

  testWidgets('Demo-Zustand überlebt einen Neustart', (tester) async {
    SharedPreferences.setMockInitialValues({'demo_mode': true});
    await DemoMode.restore();
    expect(DemoMode.active.value, isTrue);
  });
}
