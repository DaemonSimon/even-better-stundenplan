import 'dart:convert';

import 'package:html/parser.dart' as html;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'iserv_session.dart';

class IservCalendarEvent {
  const IservCalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    this.end,
    this.description = '',
  });

  final String id;
  final String title;
  final DateTime start;
  final DateTime? end;
  final String description;

  bool occursOn(DateTime day) =>
      start.year == day.year &&
      start.month == day.month &&
      start.day == day.day;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'start': start.toIso8601String(),
    'end': end?.toIso8601String(),
    'description': description,
  };

  factory IservCalendarEvent.fromJson(Map<String, dynamic> json) =>
      IservCalendarEvent(
        id: json['id'] as String,
        title: json['title'] as String,
        start: DateTime.parse(json['start'] as String),
        end: (json['end'] as String?) == null
            ? null
            : DateTime.parse(json['end'] as String),
        description: json['description'] as String? ?? '',
      );
}

class IservCalendarStore {
  static const String _prefsKey = 'iserv_calendar_events';

  Future<List<IservCalendarEvent>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return [];
      return [
        for (final item in jsonDecode(raw) as List)
          if (item is Map<String, dynamic>) IservCalendarEvent.fromJson(item),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<IservCalendarEvent> events) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode([for (final event in events) event.toJson()]),
    );
  }
}

Future<List<IservCalendarEvent>> fetchIservCalendar(
  IservSession session,
) async {
  if (!await session.isAuthenticated()) {
    throw const IservLoginException('Bitte zuerst bei IServ anmelden');
  }

  final today = DateTime.now();
  final firstDay = DateFormat(
    'yyyy-MM-dd',
  ).format(today.subtract(const Duration(days: 7)));
  final lastDay = DateFormat(
    'yyyy-MM-dd',
  ).format(today.add(const Duration(days: 120)));
  final sourceEvents = await _fetchCalendarSources(
    session,
    firstDay: firstDay,
    lastDay: lastDay,
  );
  if (sourceEvents != null) return sourceEvents;

  final calendarApiUrl = Uri(
    path: '/calendar/feed/calendar-multi',
    queryParameters: {
      'start': DateFormat(
        'yyyy-MM-dd',
      ).format(DateTime.now().subtract(const Duration(days: 7))),
      'end': DateFormat(
        'yyyy-MM-dd',
      ).format(DateTime.now().add(const Duration(days: 120))),
    },
  );
  final apiResponse = await session.get(calendarApiUrl.toString());
  if (apiResponse.statusCode == 200) {
    try {
      final payload = jsonDecode(apiResponse.body);
      if (payload is List || payload is Map) {
        return parseIservCalendarJson(payload);
      }
    } on FormatException {
      // Older IServ versions return HTML instead of the calendar JSON feed.
    }
  }

  final response = await session.get('/calendar/');
  if (response.statusCode != 200) {
    throw IservException('IServ-Kalender lieferte HTTP ${response.statusCode}');
  }
  final calendarUri =
      response.request?.url ??
      Uri.parse(
        '${session.baseUrl.replaceFirst(RegExp(r'/+$'), '')}/calendar/',
      );

  final events = <String, IservCalendarEvent>{};
  for (final event in parseIservCalendarHtml(response.body)) {
    events[event.id] = event;
  }

  final document = html.parse(response.body);
  final exports = <String>{};
  for (final node in document.querySelectorAll('a[href], link[href]')) {
    final href = (node.attributes['href'] ?? '').trim();
    final lower = href.toLowerCase();
    if (href.isNotEmpty &&
        (lower.endsWith('.ics') ||
            lower.contains('ical') ||
            lower.contains('calendar') && lower.contains('export'))) {
      exports.add(calendarUri.resolve(href).toString());
    }
  }
  for (final exportUrl in exports.take(4)) {
    final export = await session.get(exportUrl);
    if (export.statusCode != 200) continue;
    for (final event in parseIcalendar(export.body)) {
      events[event.id] = event;
    }
  }

  return events.values.toList()..sort((a, b) => a.start.compareTo(b.start));
}

Future<List<IservCalendarEvent>?> _fetchCalendarSources(
  IservSession session, {
  required String firstDay,
  required String lastDay,
}) async {
  final response = await session.get('/calendar/api/eventsources');
  if (response.statusCode != 200) return null;

  final dynamic payload;
  try {
    payload = jsonDecode(response.body);
  } on FormatException {
    return null;
  }
  if (payload is! List) return null;

  final base = Uri.parse(session.baseUrl);
  final events = <String, IservCalendarEvent>{};
  var readableSourceCount = 0;
  var successfulFeedCount = 0;
  for (final item in payload) {
    if (item is! Map || item['url'] is! String) continue;
    final rawUrl = (item['url'] as String).trim();
    if (rawUrl.isEmpty) continue;
    final uri = _calendarSourceUri(base, rawUrl);
    if (uri == null) continue;
    readableSourceCount++;
    final feedUri = uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        'start': firstDay,
        'end': lastDay,
      },
    );
    final feed = await session.get(feedUri.toString());
    if (feed.statusCode != 200) continue;
    try {
      final feedPayload = jsonDecode(feed.body);
      final sourceId = (item['id'] ?? item['label'] ?? rawUrl).toString();
      successfulFeedCount++;
      for (final event in parseIservCalendarJson(feedPayload, idPrefix: sourceId)) {
        events[event.id] = event;
      }
    } on FormatException {
      continue;
    }
  }
  if (readableSourceCount == 0 || successfulFeedCount == 0) return null;
  final result = events.values.toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  return result;
}

Uri? _calendarSourceUri(Uri base, String rawUrl) {
  final candidate = Uri.tryParse(rawUrl);
  if (candidate == null) return null;
  final uri = candidate.hasScheme
      ? candidate
      : candidate.path.startsWith(base.path)
      ? Uri(
          scheme: base.scheme,
          userInfo: base.userInfo,
          host: base.host,
          port: base.hasPort ? base.port : null,
          path: candidate.path,
          query: candidate.hasQuery ? candidate.query : null,
        )
      : Uri.parse(
          '${base.toString().replaceFirst(RegExp(r'/+$'), '')}/'
          '${rawUrl.replaceFirst(RegExp(r'^/+'), '')}',
        );
  if (uri.scheme != base.scheme ||
      uri.host != base.host ||
      uri.port != base.port ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

List<IservCalendarEvent> parseIservCalendarJson(
  dynamic payload, {
  String idPrefix = '',
}) {
  final events = <String, IservCalendarEvent>{};
  _collectJsonEvents(payload, events);
  final values = events.values
      .map(
        (event) => idPrefix.isEmpty
            ? event
            : IservCalendarEvent(
                id: '$idPrefix:${event.id}',
                title: event.title,
                start: event.start,
                end: event.end,
                description: event.description,
              ),
      )
      .toList();
  return values..sort((a, b) => a.start.compareTo(b.start));
}

List<IservCalendarEvent> parseIcalendar(String text) {
  final unfolded = text.replaceAll(RegExp(r'\r?\n[ \t]'), '');
  final events = <IservCalendarEvent>[];
  Map<String, String> fields = {};
  var inEvent = false;

  for (final line in unfolded.split(RegExp(r'\r?\n'))) {
    if (line == 'BEGIN:VEVENT') {
      fields = {};
      inEvent = true;
      continue;
    }
    if (line == 'END:VEVENT') {
      final title = _unescapeIcal(fields['SUMMARY'] ?? '').trim();
      final start = _parseIcalDate(fields['DTSTART'] ?? '');
      if (title.isNotEmpty && start != null) {
        final end = _parseIcalDate(fields['DTEND'] ?? '');
        events.add(
          IservCalendarEvent(
            id: _eventId(title, start),
            title: title,
            start: start,
            end: end,
            description: _unescapeIcal(fields['DESCRIPTION'] ?? ''),
          ),
        );
      }
      inEvent = false;
      continue;
    }
    if (!inEvent) continue;
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    final key = line.substring(0, colon).split(';').first.toUpperCase();
    if (key == 'SUMMARY' ||
        key == 'DTSTART' ||
        key == 'DTEND' ||
        key == 'DESCRIPTION') {
      fields[key] = line.substring(colon + 1);
    }
  }
  return events;
}

List<IservCalendarEvent> parseIservCalendarHtml(String source) {
  final document = html.parse(source);
  final events = <String, IservCalendarEvent>{};

  for (final node in document.querySelectorAll(
    '[data-start], [data-date], .fc-event, .calendar-event, .event',
  )) {
    final startText =
        node.attributes['data-start'] ??
        node.attributes['data-date'] ??
        node.querySelector('time')?.attributes['datetime'] ??
        '';
    final start = _parseIcalDate(startText) ?? _dateFromText(node.text);
    final title =
        (node.attributes['data-title'] ??
                node.querySelector('.fc-event-title, .event-title')?.text ??
                node.text)
            .trim()
            .replaceAll(RegExp(r'\s+'), ' ');
    if (start == null || title.isEmpty) continue;

    final end = _parseIcalDate(
      node.attributes['data-end'] ?? node.attributes['data-end-date'] ?? '',
    );
    final event = IservCalendarEvent(
      id: _eventId(title, start),
      title: title,
      start: start,
      end: end,
    );
    events[event.id] = event;
  }

  for (final script in document.querySelectorAll(
    'script[type="application/json"], script[type="application/ld+json"]',
  )) {
    try {
      _collectJsonEvents(jsonDecode(script.text), events);
    } catch (_) {
      // Other JSON scripts on the calendar page are unrelated.
    }
  }
  return events.values.toList()..sort((a, b) => a.start.compareTo(b.start));
}

void _collectJsonEvents(dynamic value, Map<String, IservCalendarEvent> events) {
  if (value is List) {
    for (final item in value) {
      _collectJsonEvents(item, events);
    }
    return;
  }
  if (value is! Map) return;

  final title = (value['title'] ?? value['summary'] ?? value['name'])
      ?.toString()
      .trim();
  final start = _parseIcalDate(
    (value['start'] ?? value['startDate'] ?? value['date'])?.toString() ?? '',
  );
  if (title != null && title.isNotEmpty && start != null) {
    final end = _parseIcalDate(
      (value['end'] ?? value['endDate'])?.toString() ?? '',
    );
    final id = (value['uid'] ?? value['id'] ?? value['hash'])?.toString();
    final event = IservCalendarEvent(
      id: id == null || id.isEmpty ? _eventId(title, start) : id,
      title: title,
      start: start,
      end: end,
      description: (value['description'] ?? '').toString(),
    );
    events[event.id] = event;
  }
  for (final child in value.values) {
    if (child is Map || child is List) _collectJsonEvents(child, events);
  }
}

DateTime? _parseIcalDate(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final compact = RegExp(
    r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$',
  ).firstMatch(trimmed);
  if (compact != null) {
    final year = int.parse(compact.group(1)!);
    final month = int.parse(compact.group(2)!);
    final day = int.parse(compact.group(3)!);
    final hour = int.tryParse(compact.group(4) ?? '') ?? 0;
    final minute = int.tryParse(compact.group(5) ?? '') ?? 0;
    final second = int.tryParse(compact.group(6) ?? '') ?? 0;
    if (compact.group(7) == 'Z') {
      return DateTime.utc(year, month, day, hour, minute, second).toLocal();
    }
    return DateTime(year, month, day, hour, minute, second);
  }
  return DateTime.tryParse(trimmed)?.toLocal();
}

DateTime? _dateFromText(String text) {
  final match = RegExp(
    r'(\d{1,2})\.(\d{1,2})\.(\d{4})(?:\s+(\d{1,2})[:.](\d{2}))?',
  ).firstMatch(text);
  if (match == null) return null;
  return DateTime(
    int.parse(match.group(3)!),
    int.parse(match.group(2)!),
    int.parse(match.group(1)!),
    int.tryParse(match.group(4) ?? '') ?? 0,
    int.tryParse(match.group(5) ?? '') ?? 0,
  );
}

String _unescapeIcal(String value) => value
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\,', ',')
    .replaceAll(r'\;', ';')
    .replaceAll(r'\\', r'\');

String _eventId(String title, DateTime start) =>
    '${start.toIso8601String()}|${title.toLowerCase()}';
