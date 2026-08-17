import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'pages/details_page.dart';

/// Typisierte Route zur Detailansicht einer Unterrichtsstunde.
class DetailsRoute extends GoRouteData {
  const DetailsRoute({
    required this.lesson,
    required this.teacher,
    required this.room,
    required this.date,
    required this.hour,
  });

  final String lesson;
  final String teacher;
  final String room;
  final String date;
  final String hour;

  @override
  Widget build(BuildContext context, GoRouterState state) => DetailsPage(
    lesson: lesson,
    teacher: teacher,
    room: room,
    date: date,
    hour: hour,
  );

  /// Liest die Query-Parameter zurück (für die Routen-Registrierung).
  static DetailsRoute fromState(GoRouterState state) {
    final query = state.uri.queryParameters;
    return DetailsRoute(
      lesson: query['lesson'] ?? '',
      teacher: query['teacher'] ?? '',
      room: query['room'] ?? '',
      date: query['date'] ?? '',
      hour: query['hour'] ?? '',
    );
  }

  /// Baut die Location-URL für die Navigation.
  String get location => GoRouteData.$location(
    '/details',
    queryParams: {
      'lesson': lesson,
      'teacher': teacher,
      'room': room,
      'date': date,
      'hour': hour,
    },
  );
}