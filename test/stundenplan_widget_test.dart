import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:better_stundenplan/components/class_card.dart';
import 'package:better_stundenplan/components/stundenplan_widget.dart';
import 'package:better_stundenplan/models/timetable.dart';
import 'package:better_stundenplan/providers/teacher_directory_provider.dart';
import 'package:better_stundenplan/services/secure_storage.dart';
import 'package:better_stundenplan/services/session_manager.dart';
import 'package:better_stundenplan/services/stundenplan_api.dart';
import 'package:better_stundenplan/services/stundenplan_repository.dart';
import 'package:better_stundenplan/services/teacher_directory.dart';
import 'package:better_stundenplan/services/timetable_cache.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// Plattencache, der path_provider nicht anspricht – path_provider
/// MethodChannel-Aufrufe werden unter Fake-Async nie aufgelöst und
/// würden den Test hängen lassen.
class _NoopDiskCache extends TimetableDiskCache {
  @override
  Future<void> save(String dateKey, DailyTimetable value) async {}

  @override
  Future<DailyTimetable?> load(String dateKey) async => null;
}

class InMemoryCredentialStorage implements CredentialStorage {
  String? sessionId;
  String? email;
  String? password;

  @override
  Future<String?> getSessionId() async => sessionId;

  @override
  Future<String?> getEmail() async => email;

  @override
  Future<String?> getPassword() async => password;

  @override
  Future<void> saveSessionId(String sessionId) async {
    this.sessionId = sessionId;
  }

  @override
  Future<void> saveCredentials({
    required String email,
    required String password,
  }) async {
    this.email = email;
    this.password = password;
  }

  @override
  Future<void> clear() async {
    sessionId = null;
    email = null;
    password = null;
  }
}

/// Wochenstart Montag, 10.08.2026 – Freitag ist der 14.08.2026 (Index 4).
Widget buildTestWidget(
  StundenplanRepository repository, {
  TimetableViewMode mode = TimetableViewMode.daily,
  int day = 4,
  DateTime Function()? clock,
  TeacherDirectoryProvider? teacherDirectory,
}) {
  return MaterialApp(
    home: Scaffold(
      body: StundenplanWidget(
        weekStart: DateTime(2026, 8, 10),
        viewMode: mode,
        selectedDayIndex: day,
        onDaySelected: (_) {},
        repository: repository,
        teacherDirectory: teacherDirectory,
        clock: clock,
      ),
    ),
  );
}

StundenplanRepository fixtureRepository(
  SessionManager manager,
  String fixtureName,
) {
  return StundenplanRepository(
    sessionManager: manager,
    api: StundenplanApi(
      client: MockClient(
        (request) async => http.Response(fixture(fixtureName), 200),
      ),
    ),
    cache: TimetableCache(disk: _NoopDiskCache()),
  );
}

void main() {
  late SessionManager sessionManager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final storage = InMemoryCredentialStorage()..sessionId = 'valid-session';
    sessionManager = SessionManager(
      storage: storage,
      client: MockClient((request) async => http.Response('', 200)),
    );
    await sessionManager.checkAuthentication();
  });

  testWidgets('double hours are one card, parallel courses stay side by side',
      (tester) async {
    final repository =
        fixtureRepository(sessionManager, 'day_with_double_hours.html');

    await tester.pumpWidget(buildTestWidget(repository));
    await tester.pumpAndSettle();

    // Block 1 = Doppelstunde Ma (Stunde 1+2) -> EINE Karte, 90 Minuten.
    expect(find.text('Ma'), findsOneWidget);
    expect(find.text('Müller'), findsWidgets);
    expect(find.text('101'), findsOneWidget);
    expect(find.text('1+2'), findsOneWidget);
    expect(find.text('08:10'), findsOneWidget);
    expect(find.text('09:40'), findsOneWidget);

    // Einzelstunden 3 (De) und 4 (En) mit eigenen 45-Minuten-Zeiten.
    expect(find.text('De'), findsNWidgets(2)); // Stunde 3 und 8
    expect(find.text('102'), findsNWidgets(2));
    expect(find.text('En'), findsNWidgets(2)); // Stunde 4 und Doppelstunde 5+6
    expect(find.text('3'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);
    expect(find.text('10:45'), findsNWidgets(2)); // Ende Stunde 3, Beginn Stunde 4

    // Block 3 = Doppelstunde mit Parallelkursen (En + PO) -> eine Zeile.
    expect(find.text('5+6'), findsOneWidget);
    expect(find.textContaining('PO'), findsOneWidget);
    expect(find.text('201'), findsNWidgets(2));
    expect(find.text('202'), findsOneWidget);

    // Stunde 7 ist frei -> gestrichelte Free-Period-Karte.
    expect(find.text('Freie Stunde'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);

    // Mittagspause zwischen 6. und 7. Stunde.
    expect(find.textContaining('Mittagspause'), findsOneWidget);
  });

  testWidgets('teacher shortcuts are replaced with full names from the directory',
      (tester) async {
    final repository =
        fixtureRepository(sessionManager, 'day_with_double_hours.html');
    final teacherDirectory = TeacherDirectoryProvider(
      initialEntries: const {
        'MÜLLER': TeacherEntry(kuerzel: 'Müller', fullName: 'Helga Müller'),
        'SCHMIDT': TeacherEntry(kuerzel: 'Schmidt', fullName: 'Peter Schmidt'),
        'WEBER': TeacherEntry(kuerzel: 'Weber', fullName: 'Klaus Weber'),
      },
    );

    await tester.pumpWidget(
      buildTestWidget(repository, teacherDirectory: teacherDirectory),
    );
    await tester.pumpAndSettle();

    // Ma (Block 1) und PO (Block 3) haben Müller -> 2 volle Namen.
    expect(find.text('Helga Müller'), findsNWidgets(2));
    expect(find.text('Müller'), findsNothing);
    expect(find.text('Peter Schmidt'), findsNWidgets(2));
    expect(find.text('Schmidt'), findsNothing);
    expect(find.text('Klaus Weber'), findsNWidgets(2));
    expect(find.text('Weber'), findsNothing);

    // Detail-Modal: voller Name mit Kürzel in Klammern.
    await tester.tap(find.text('Ma'));
    await tester.pumpAndSettle();

    expect(find.text('Helga Müller (Müller)'), findsOneWidget);
  });

  testWidgets('keeps raw shortcuts when the directory has no entry',
      (tester) async {
    final repository =
        fixtureRepository(sessionManager, 'day_with_double_hours.html');

    await tester.pumpWidget(buildTestWidget(repository));
    await tester.pumpAndSettle();

    expect(find.text('Müller'), findsNWidgets(2));
    expect(find.text('Schmidt'), findsNWidgets(2));
    expect(find.text('Weber'), findsNWidgets(2));
  });

  testWidgets('prefixed shortcuts keep the prefix and resolve the name',
      (tester) async {
    final repository =
        fixtureRepository(sessionManager, 'day_with_prefixed_teacher.html');
    final teacherDirectory = TeacherDirectoryProvider(
      initialEntries: const {
        'KREP': TeacherEntry(kuerzel: 'KREP', fullName: 'Maren Krep'),
        'MÜLLER': TeacherEntry(kuerzel: 'Müller', fullName: 'Helga Müller'),
      },
    );

    await tester.pumpWidget(
      buildTestWidget(repository, teacherDirectory: teacherDirectory),
    );
    await tester.pumpAndSettle();

    // Präfix "A:" bleibt erhalten, Kürzel wird zum vollen Namen aufgelöst.
    expect(find.text('A: Maren Krep'), findsOneWidget);
    expect(find.text('A:KREP'), findsNothing);
    expect(find.text('Helga Müller'), findsOneWidget);

    // Detail-Modal zeigt Präfix + vollen Namen (Kürzel ohne Präfix).
    await tester.tap(find.text('Ma'));
    await tester.pumpAndSettle();
    expect(find.text('A: Maren Krep (KREP)'), findsOneWidget);
  });

  testWidgets('tapping the teacher name opens the teacher photo dialog',
      (tester) async {
    final repository =
        fixtureRepository(sessionManager, 'day_with_double_hours.html');
    final teacherDirectory = TeacherDirectoryProvider(
      initialEntries: const {
        'MÜLLER': TeacherEntry(
          kuerzel: 'Müller',
          fullName: 'Helga Müller',
          photoUrl: 'https://start.bbs-papenburg.de/images/mueller.jpg',
        ),
      },
    );

    await tester.pumpWidget(
      buildTestWidget(repository, teacherDirectory: teacherDirectory),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ma'));
    await tester.pumpAndSettle();

    expect(find.text('Helga Müller (Müller)'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);

    // Name antippen -> Foto-Dialog (Bild-Laden ist im Test gesperrt,
    // daher erscheint der errorBuilder).
    await tester.tap(find.text('Helga Müller (Müller)'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byIcon(Icons.person_off), findsOneWidget);
  });

  testWidgets('teacher row is not tappable without a photo', (tester) async {
    final repository =
        fixtureRepository(sessionManager, 'day_with_double_hours.html');
    final teacherDirectory = TeacherDirectoryProvider(
      initialEntries: const {
        'MÜLLER': TeacherEntry(kuerzel: 'Müller', fullName: 'Helga Müller'),
      },
    );

    await tester.pumpWidget(
      buildTestWidget(repository, teacherDirectory: teacherDirectory),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ma'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Helga Müller (Müller)'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('shows the network error state', (tester) async {
    final repository = StundenplanRepository(
      sessionManager: sessionManager,
      api: StundenplanApi(
        client: MockClient(
          (_) async => throw http.ClientException('boom'),
        ),
      ),
      cache: TimetableCache(disk: _NoopDiskCache()),
    );

    await tester.pumpWidget(buildTestWidget(repository));
    await tester.pumpAndSettle();

    expect(find.textContaining('Netzwerkfehler'), findsOneWidget);
  });

  testWidgets('shows the expired-session state with a login button', (tester) async {
    final repository = StundenplanRepository(
      sessionManager: sessionManager,
      api: StundenplanApi(
        client: MockClient(
          (_) async => http.Response(
            '',
            302,
            headers: {'location': '/'},
            isRedirect: true,
          ),
        ),
      ),
      cache: TimetableCache(disk: _NoopDiskCache()),
    );

    await tester.pumpWidget(buildTestWidget(repository));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sitzung abgelaufen'), findsOneWidget);
    // Der Retry-Button führt zur erneuten Anmeldung (/authenticate)
    expect(find.textContaining('Erneut versuchen'), findsOneWidget);
  });

  testWidgets('weekly mode shows the IServ tasks view', (tester) async {
    final repository =
        fixtureRepository(sessionManager, 'day_with_double_hours.html');

    await tester.pumpWidget(
      buildTestWidget(repository, mode: TimetableViewMode.weekly),
    );
    await tester.pumpAndSettle();

    // Ohne angemeldete Session zeigt die Ansicht das Login-Formular.
    expect(find.text('IServ-Anmeldung'), findsOneWidget);
    expect(find.text('Ma'), findsNothing);
  });

  testWidgets('live double hour gets the live frame, no JETZT badge',
      (tester) async {
    final repository =
        fixtureRepository(sessionManager, 'day_with_double_hours.html');

    // 08:30 -> Block 1 (08:10–09:40) läuft.
    await tester.pumpWidget(
      buildTestWidget(
        repository,
        clock: () => DateTime(2026, 8, 14, 8, 30),
      ),
    );
    await tester.pumpAndSettle();

    // Das "JETZT"-Badge existiert nicht mehr; die Zeit zeigt die rote Linie.
    expect(find.text('JETZT'), findsNothing);
    // Kein Minuten-Badge/Fortschrittsleiste an Live-Karten.
    expect(find.textContaining('MIN'), findsNothing);
  });

  testWidgets('single-hour lessons track their own 45-minute window',
      (tester) async {
    final repository =
        fixtureRepository(sessionManager, 'day_with_double_hours.html');

    // 10:30 -> Stunde 3 (10:00–10:45) läuft; Stunde 4 (10:45) ist
    // dringend -> Puls-Glow animiert endlos, daher kein pumpAndSettle.
    await tester.pumpWidget(
      buildTestWidget(
        repository,
        clock: () => DateTime(2026, 8, 14, 10, 30),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Kein "JETZT"-Badge, kein Minuten-Badge/Fortschrittsleiste.
    expect(find.text('JETZT'), findsNothing);
    expect(find.textContaining('MIN'), findsNothing);
  });

  testWidgets('no live badge outside school hours', (tester) async {
    final repository =
        fixtureRepository(sessionManager, 'day_with_double_hours.html');

    // 15:30 -> nach Stunde 8, kein Unterricht mehr.
    await tester.pumpWidget(
      buildTestWidget(
        repository,
        clock: () => DateTime(2026, 8, 14, 15, 30),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('JETZT'), findsNothing);
  });

  testWidgets('red now line marks the current position in the day',
      (tester) async {
    final repository =
        fixtureRepository(sessionManager, 'day_with_double_hours.html');
    var clock = DateTime(2026, 8, 14, 9, 0); // Freitag, Block 1 läuft

    await tester.pumpWidget(buildTestWidget(repository, clock: () => clock));
    await tester.pumpAndSettle();

    // Linie sichtbar, mit Uhrzeit-Pille der aktuellen Zeit.
    expect(find.byKey(const Key('now-line')), findsOneWidget);
    expect(find.text('09:00'), findsOneWidget);
    final top1 = tester.getTopLeft(find.byKey(const Key('now-line'))).dy;
    expect(top1, greaterThan(0));

    // 12:50 -> Block 3 (5+6) läuft: Linie ist weiter unten.
    clock = DateTime(2026, 8, 14, 12, 50);
    await tester.pumpWidget(buildTestWidget(repository, clock: () => clock));
    await tester.pumpAndSettle();

    final top2 = tester.getTopLeft(find.byKey(const Key('now-line'))).dy;
    expect(top2, greaterThan(top1));
    expect(find.text('12:50'), findsOneWidget);
  });

  testWidgets('no now line before the school day starts', (tester) async {
    final repository =
        fixtureRepository(sessionManager, 'day_with_double_hours.html');

    // 07:30 -> vor Block 1 (08:10): keine Linie, keine Uhrzeit-Pille.
    await tester.pumpWidget(
      buildTestWidget(
        repository,
        clock: () => DateTime(2026, 8, 14, 7, 30),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('now-line')), findsNothing);
    expect(find.text('07:30'), findsNothing);
  });

  testWidgets('now line appears exactly at the start of the first lesson',
      (tester) async {
    final repository =
        fixtureRepository(sessionManager, 'day_with_double_hours.html');

    // 08:10 -> Block 1 beginnt: Linie wird sichtbar (oben).
    await tester.pumpWidget(
      buildTestWidget(
        repository,
        clock: () => DateTime(2026, 8, 14, 8, 10),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('now-line')), findsOneWidget);
  });

  testWidgets('no now line after the school day ends', (tester) async {
    final repository =
        fixtureRepository(sessionManager, 'day_with_double_hours.html');

    // 15:30 -> nach Stunde 8 (15:00): keine Linie, keine Uhrzeit-Pille.
    await tester.pumpWidget(
      buildTestWidget(
        repository,
        clock: () => DateTime(2026, 8, 14, 15, 30),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('now-line')), findsNothing);
    expect(find.text('15:30'), findsNothing);
  });

  testWidgets('no now line on a day that is not today', (tester) async {
    final repository =
        fixtureRepository(sessionManager, 'day_with_double_hours.html');

    // Dienstag gewählt (Index 1), Uhrzeit am Freitag -> nicht "heute".
    await tester.pumpWidget(
      buildTestWidget(
        repository,
        day: 1,
        clock: () => DateTime(2026, 8, 14, 9, 0),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('now-line')), findsNothing);
    expect(find.text('09:00'), findsNothing);
  });

  testWidgets('a day without afternoon shows no Mittagspause and ends at lunch',
      (tester) async {
    final repository =
        fixtureRepository(sessionManager, 'day_ends_at_lunch.html');

    await tester.pumpWidget(buildTestWidget(repository));
    await tester.pumpAndSettle();

    // Kein Nachmittagsunterricht: die Mittagspause entfällt komplett,
    // nach der letzten Stunde endet der Tag: keine "Freie Stunde"-Karten,
    // keine 7./8. Stunde.
    expect(find.textContaining('Mittagspause'), findsNothing);
    expect(find.text('Freie Stunde'), findsNothing);
    expect(find.text('7'), findsNothing);
    expect(find.text('8'), findsNothing);
    expect(find.text('En'), findsOneWidget); // Block 3 (5+6) noch da
  });

  testWidgets('now line hides during the Mittagspause, countdown pill appears',
      (tester) async {
    // Tag MIT Nachmittagsunterricht (8. Stunde): Mittagspause sichtbar.
    final repository =
        fixtureRepository(sessionManager, 'day_with_double_hours.html');

    // Block 3 läuft noch (12:50) -> Linie sichtbar, kein Countdown.
    await tester.pumpWidget(
      buildTestWidget(
        repository,
        clock: () => DateTime(2026, 8, 14, 12, 50),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('now-line')), findsOneWidget);
    expect(find.textContaining('Endet in'), findsNothing);

    // Während der Mittagspause: Linie weg, Countdown zeigt Restzeit.
    await tester.pumpWidget(
      buildTestWidget(
        repository,
        clock: () => DateTime(2026, 8, 14, 13, 25),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('now-line')), findsNothing);
    expect(find.text('Endet in 20m'), findsOneWidget);

    await tester.pumpWidget(
      buildTestWidget(
        repository,
        clock: () => DateTime(2026, 8, 14, 13, 40),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('now-line')), findsNothing);
    expect(find.text('Endet in 5m'), findsOneWidget);

    // Nach der Pause läuft die 8. Stunde (14:30):
    // Linie wieder da, Countdown verschwunden.
    await tester.pumpWidget(
      buildTestWidget(
        repository,
        clock: () => DateTime(2026, 8, 14, 14, 30),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('now-line')), findsOneWidget);
    expect(find.textContaining('Endet in'), findsNothing);
  });

  testWidgets('now line sits exactly on the card top at block start',
      (tester) async {
    final repository =
        fixtureRepository(sessionManager, 'day_with_double_hours.html');

    // Exakt 08:10 -> Block 1 beginnt: Linie auf der Oberkante der Karte.
    await tester.pumpWidget(
      buildTestWidget(
        repository,
        clock: () => DateTime(2026, 8, 14, 8, 10),
      ),
    );
    await tester.pumpAndSettle();

    final lineDy = tester.getTopLeft(find.byKey(const Key('now-line'))).dy;
    // Exakte Ausrichtung mit der Oberkante der Karte.
    final cardTop = tester.getRect(find.byType(ClassCard).first).top;
    expect(lineDy, closeTo(cardTop, 0.5));
  });

  testWidgets('now line moves proportionally to the elapsed minutes',
      (tester) async {
    final repository =
        fixtureRepository(sessionManager, 'day_with_double_hours.html');

    double lineAt(DateTime t) {
      return tester.getTopLeft(find.byKey(const Key('now-line'))).dy;
    }

    Future<void> pumpAt(DateTime t) async {
      await tester.pumpWidget(buildTestWidget(repository, clock: () => t));
      await tester.pumpAndSettle();
    }

    // Block 1: 08:10 – 09:40 (90 min). 08:25 = 15/90, 08:55 = 45/90.
    await pumpAt(DateTime(2026, 8, 14, 8, 10));
    final atStart = lineAt(DateTime(2026, 8, 14, 8, 10));

    await pumpAt(DateTime(2026, 8, 14, 8, 25));
    final atQuarter = lineAt(DateTime(2026, 8, 14, 8, 25));

    await pumpAt(DateTime(2026, 8, 14, 8, 55));
    final atHalf = lineAt(DateTime(2026, 8, 14, 8, 55));

    // 15 min ist genau 1/3 der ersten 45 Minuten.
    expect(
      (atQuarter - atStart) * 3,
      closeTo(atHalf - atStart, 2),
    );
  });

  testWidgets('Mittagspause text has a solid background to mask the now line',
      (tester) async {
    final repository =
        fixtureRepository(sessionManager, 'day_with_double_hours.html');

    await tester.pumpWidget(buildTestWidget(repository));
    await tester.pumpAndSettle();

    // Der Text liegt in einem Container mit deckender App-Hintergrundfarbe
    // (plus Innenabstand), damit die rote Jetzt-Linie ihn nicht kreuzt.
    final lunchText = find.text('Mittagspause 13:15 – 13:45');
    expect(lunchText, findsOneWidget);
    final mask = find.ancestor(
      of: lunchText,
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.color != null && w.padding != null,
      ),
    );
    expect(mask, findsOneWidget);
  });

  testWidgets('left column times have a solid background to mask the now line',
      (tester) async {
    final repository =
        fixtureRepository(sessionManager, 'day_with_double_hours.html');

    await tester.pumpWidget(buildTestWidget(repository));
    await tester.pumpAndSettle();

    // Die statischen Uhrzeiten der linken Spalte liegen in Containern
    // mit deckender App-Hintergrundfarbe + Innenabstand.
    for (final time in ['08:10', '09:40']) {
      final mask = find.ancestor(
        of: find.text(time),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.color != null && w.padding != null,
        ),
      );
      expect(mask, findsOneWidget, reason: '$time muss maskiert sein');
    }
  });

  testWidgets('now line time pill sits on the right side', (tester) async {
    final repository =
        fixtureRepository(sessionManager, 'day_with_double_hours.html');

    await tester.pumpWidget(
      buildTestWidget(
        repository,
        clock: () => DateTime(2026, 8, 14, 9, 0),
      ),
    );
    await tester.pumpAndSettle();

    // Pille nicht mehr über der linken Zeit-Spalte (Breite 76), sondern
    // im rechten Kartenbereich.
    final pillLeft = tester.getTopLeft(find.text('09:00')).dx;
    expect(pillLeft, greaterThan(76));
  });

  testWidgets('swiping right goes from Friday to Thursday, left back to Friday',
      (tester) async {
    final repository =
        fixtureRepository(sessionManager, 'day_with_double_hours.html');
    int? selectedIndex;
    late StateSetter setState;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setter) {
              setState = setter;
              return StundenplanWidget(
                weekStart: DateTime(2026, 8, 10),
                viewMode: TimetableViewMode.daily,
                selectedDayIndex: selectedIndex ?? 4,
                onDaySelected: (index) {
                  setState(() => selectedIndex = index);
                },
                repository: repository,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ma'), findsOneWidget); // Freitag

    // Nach rechts wischen -> Donnerstag (vorheriger Tag).
    await tester.drag(find.byType(PageView), const Offset(600, 0));
    await tester.pumpAndSettle();

    expect(selectedIndex, 3);
    expect(find.text('Ma'), findsOneWidget); // Fixture zeigt jeden Tag

    // Nach links wischen -> zurück zu Freitag.
    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(selectedIndex, 4);
  });

  testWidgets('tapping a day pill jumps the page view', (tester) async {
    final repository =
        fixtureRepository(sessionManager, 'day_with_double_hours.html');
    int? selectedIndex;
    late StateSetter setState;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setter) {
              setState = setter;
              return StundenplanWidget(
                weekStart: DateTime(2026, 8, 10),
                viewMode: TimetableViewMode.daily,
                selectedDayIndex: selectedIndex ?? 4,
                onDaySelected: (index) {
                  setState(() => selectedIndex = index);
                },
                repository: repository,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Montag-Pille antippen (Tag "10" der Woche; Locale-neutral).
    await tester.tap(find.text('10'));
    await tester.pumpAndSettle();

    expect(selectedIndex, 0);
  });

  testWidgets('upcoming classes get an urgency badge with countdown',
      (tester) async {
    final repository =
        fixtureRepository(sessionManager, 'day_with_double_hours.html');

    // 08:00 -> Block 1 beginnt in 10 Minuten (08:10).
    await tester.pumpWidget(
      buildTestWidget(
        repository,
        clock: () => DateTime(2026, 8, 14, 8, 6),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Beginnt in 4m'), findsOneWidget);
    expect(find.byIcon(Icons.directions_run), findsOneWidget);
    expect(_urgentCardCount(tester), 1);
    expect(find.text('JETZT'), findsNothing);

    // Kurz vor Beginn zählt der Countdown herunter.
    await tester.pumpWidget(
      buildTestWidget(
        repository,
        clock: () => DateTime(2026, 8, 14, 8, 9),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Beginnt in 1m'), findsOneWidget);
  });

  testWidgets('urgency applies only in the 5 minutes before a class',
      (tester) async {
    final repository =
        fixtureRepository(sessionManager, 'day_with_double_hours.html');

    // 08:05 -> exakt 5 Minuten vorher: urgent.
    await tester.pumpWidget(
      buildTestWidget(
        repository,
        clock: () => DateTime(2026, 8, 14, 8, 5),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Beginnt in 5m'), findsOneWidget);

    // 08:04 -> außerhalb des Fensters: kein Badge, kein Urgency-Balken.
    await tester.pumpWidget(
      buildTestWidget(
        repository,
        clock: () => DateTime(2026, 8, 14, 8, 4),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Beginnt in'), findsNothing);
    expect(_urgentCardCount(tester), 0);

    // 08:10 -> Unterricht läuft: kein Urgency-Badge mehr.
    await tester.pumpWidget(
      buildTestWidget(
        repository,
        clock: () => DateTime(2026, 8, 14, 8, 10),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Beginnt in'), findsNothing);
  });

  testWidgets('split classes both get the urgency state', (tester) async {
    final repository =
        fixtureRepository(sessionManager, 'day_with_double_hours.html');

    // 11:40 -> Block 3 (11:45) mit En + PO [Kl. 10] als Split.
    await tester.pumpWidget(
      buildTestWidget(
        repository,
        clock: () => DateTime(2026, 8, 14, 11, 40),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Beginnt in 5m'), findsNWidgets(2));
    expect(find.byIcon(Icons.directions_run), findsNWidgets(2));
    expect(_urgentCardCount(tester), 2);
  });

  testWidgets('no urgency badge on days that are not today', (tester) async {
    final repository =
        fixtureRepository(sessionManager, 'day_with_double_hours.html');

    // Dienstag gewählt, Uhrzeit Freitag 08:00 -> nicht "heute".
    await tester.pumpWidget(
      buildTestWidget(
        repository,
        day: 1,
        clock: () => DateTime(2026, 8, 14, 8, 0),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Beginnt in'), findsNothing);
    expect(find.byIcon(Icons.directions_run), findsNothing);
  });

  testWidgets('a day without any lessons shows the empty state', (tester) async {
    final repository = fixtureRepository(sessionManager, 'day_empty.html');

    await tester.pumpWidget(buildTestWidget(repository));
    await tester.pumpAndSettle();

    expect(find.text('Kein Unterricht an diesem Tag'), findsOneWidget);
  });
}

/// Anzahl der Karten im Urgency-Zustand (Amber-Balken links).
int _urgentCardCount(WidgetTester tester) {
  return tester
      .widgetList<ClassCard>(find.byType(ClassCard))
      .where((card) => card.isUrgent)
      .length;
}
