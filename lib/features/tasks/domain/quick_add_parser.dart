class QuickAddParseResult {
  final String strippedTitle;
  final DateTime? dueDate;
  final String? dueTime; // "HH:mm" 24-hour format
  final String? matchedPhrase; // raw substring that was recognized

  const QuickAddParseResult({
    required this.strippedTitle,
    this.dueDate,
    this.dueTime,
    this.matchedPhrase,
  });

  @override
  String toString() =>
      'QuickAddParseResult(title: "$strippedTitle", dueDate: $dueDate, dueTime: $dueTime, matched: "$matchedPhrase")';
}

class _SpanMatch {
  final int start;
  final int end;
  final String text;

  const _SpanMatch(this.start, this.end, this.text);
}

/// Parses free-form text input to extract natural-language date and time phrases.
///
/// Strips recognized date/time phrases from [input] to produce [QuickAddParseResult.strippedTitle].
/// Supports:
/// - Relative days: "today", "tomorrow", "tmrw", "yesterday"
/// - Weekdays: optional "this"/"next" + weekday name/abbreviation (e.g. "mon", "monday", "next friday")
/// - Relative offsets: "in N day(s)", "in N week(s)"
/// - Times: "5pm", "9am", "5:30pm", "17:00", "noon", "midnight", optionally preceded by "at"
/// - Combinations: date + time in either order (e.g. "tomorrow 5pm", "5pm tomorrow", "next monday at 9am")
/// - Optional prepositions: "on", "by", "due", "at"
QuickAddParseResult parseQuickAdd(String input, {DateTime? now}) {
  final clock = now ?? DateTime.now();
  final today = DateTime(clock.year, clock.month, clock.day);

  if (input.trim().isEmpty) {
    return const QuickAddParseResult(strippedTitle: '');
  }

  DateTime? parsedDate;
  _SpanMatch? dateSpan;

  String? parsedTime;
  _SpanMatch? timeSpan;

  final text = input;

  // 1. Extract time
  // Times:
  // a) "noon" / "midnight"
  // b) 12hr: (\d{1,2})(?::(\d{2}))?\s*(am|pm)
  // c) 24hr: ([01]?\d|2[0-3]):([0-5]\d)
  // Optionally preceded by (at\s+)

  final timeRegex = RegExp(
    r'\b(?:at\s+)?(?:(noon|midnight)|(\d{1,2})(?::(\d{2}))?\s*(am|pm)|([01]?\d|2[0-3]):([0-5]\d))\b',
    caseSensitive: false,
  );

  for (final match in timeRegex.allMatches(text)) {
    final noonMidnight = match.group(1)?.toLowerCase();
    final h12 = match.group(2);
    final m12 = match.group(3);
    final ampm = match.group(4)?.toLowerCase();
    final h24 = match.group(5);
    final m24 = match.group(6);

    int hour = 0;
    int minute = 0;
    bool valid = false;

    if (noonMidnight != null) {
      if (noonMidnight == 'noon') {
        hour = 12;
        minute = 0;
      } else {
        hour = 0;
        minute = 0;
      }
      valid = true;
    } else if (h12 != null && ampm != null) {
      final parsedH = int.tryParse(h12);
      final parsedM = m12 != null ? int.tryParse(m12) : 0;
      if (parsedH != null &&
          parsedH >= 1 &&
          parsedH <= 12 &&
          parsedM != null &&
          parsedM >= 0 &&
          parsedM <= 59) {
        if (ampm == 'pm' && parsedH < 12) {
          hour = parsedH + 12;
        } else if (ampm == 'am' && parsedH == 12) {
          hour = 0;
        } else {
          hour = parsedH;
        }
        minute = parsedM;
        valid = true;
      }
    } else if (h24 != null && m24 != null) {
      final parsedH = int.tryParse(h24);
      final parsedM = int.tryParse(m24);
      if (parsedH != null &&
          parsedH >= 0 &&
          parsedH <= 23 &&
          parsedM != null &&
          parsedM >= 0 &&
          parsedM <= 59) {
        hour = parsedH;
        minute = parsedM;
        valid = true;
      }
    }

    if (valid) {
      parsedTime =
          '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
      timeSpan = _SpanMatch(match.start, match.end, match.group(0)!);
      break; // take first valid time match
    }
  }

  // 2. Check for date phrases:
  // a) Relative days: "today", "tomorrow", "tmrw", "yesterday"
  // b) Offsets: "in \d+ day(s)", "in \d+ week(s)"
  // c) Weekdays: (this|next)?\s*(mon|monday|tue|tuesday|wed|wednesday|thu|thursday|fri|friday|sat|saturday|sun|sunday)
  // Optionally preceded by (on|by|due\s+)?

  final relativeDayRegex = RegExp(
    r'\b(?:(?:on|by|due)\s+)?(today|tomorrow|tmrw|yesterday)\b',
    caseSensitive: false,
  );

  final offsetRegex = RegExp(
    r'\b(?:(?:on|by|due)\s+)?in\s+(\d+)\s+(days?|weeks?)\b',
    caseSensitive: false,
  );

  final weekdayRegex = RegExp(
    r'\b(?:(?:on|by|due)\s+)?(?:(this|next)\s+)?(mondays?|mon|tuesdays?|tues?|wednesdays?|wed|thursdays?|thurs?|thu|fridays?|fri|saturdays?|sat|sundays?|sun)\b',
    caseSensitive: false,
  );

  // Check relative days
  final relMatch = relativeDayRegex.firstMatch(text);
  if (relMatch != null) {
    final word = relMatch.group(1)!.toLowerCase();
    if (word == 'today') {
      parsedDate = today;
    } else if (word == 'tomorrow' || word == 'tmrw') {
      parsedDate = today.add(const Duration(days: 1));
    } else if (word == 'yesterday') {
      parsedDate = today.subtract(const Duration(days: 1));
    }
    dateSpan = _SpanMatch(relMatch.start, relMatch.end, relMatch.group(0)!);
  }

  // If no relative day, check offsets
  if (parsedDate == null) {
    final offMatch = offsetRegex.firstMatch(text);
    if (offMatch != null) {
      final amount = int.tryParse(offMatch.group(1)!) ?? 0;
      final unit = offMatch.group(2)!.toLowerCase();
      if (unit.startsWith('day')) {
        parsedDate = today.add(Duration(days: amount));
      } else if (unit.startsWith('week')) {
        parsedDate = today.add(Duration(days: amount * 7));
      }
      dateSpan = _SpanMatch(offMatch.start, offMatch.end, offMatch.group(0)!);
    }
  }

  // If no offset, check weekdays
  if (parsedDate == null) {
    final wkMatches = weekdayRegex.allMatches(text);
    for (final wkMatch in wkMatches) {
      final prefix = wkMatch.group(1)?.toLowerCase();
      final dayStr = wkMatch.group(2)!.toLowerCase();

      final targetWeekday = _weekdayToInt(dayStr);
      if (targetWeekday != null) {
        int daysToAdd;
        if (prefix == 'next') {
          // Following week's target weekday:
          // Start of this week (Monday) = today - (today.weekday - 1)
          // Next week Monday = Start of this week + 7 days
          // Target day = Next week Monday + (targetWeekday - 1)
          final startOfThisWeek = today.subtract(
            Duration(days: today.weekday - 1),
          );
          final nextWeekTarget = startOfThisWeek.add(
            Duration(days: 7 + (targetWeekday - 1)),
          );
          daysToAdd = nextWeekTarget.difference(today).inDays;
        } else if (prefix == 'this') {
          final startOfThisWeek = today.subtract(
            Duration(days: today.weekday - 1),
          );
          final thisWeekTarget = startOfThisWeek.add(
            Duration(days: targetWeekday - 1),
          );
          // If this week's target is in the past, move forward by 7 days
          if (thisWeekTarget.isBefore(today)) {
            daysToAdd = (targetWeekday - today.weekday + 7) % 7;
            if (daysToAdd == 0) daysToAdd = 7;
          } else {
            daysToAdd = thisWeekTarget.difference(today).inDays;
          }
        } else {
          // Plain weekday (e.g. "friday"): upcoming occurrence
          var diff = (targetWeekday - today.weekday) % 7;
          if (diff <= 0) diff += 7;
          daysToAdd = diff;
        }

        parsedDate = today.add(Duration(days: daysToAdd));
        dateSpan = _SpanMatch(wkMatch.start, wkMatch.end, wkMatch.group(0)!);
        break;
      }
    }
  }

  // If time was specified but no date was specified, default date to today
  if (parsedTime != null && parsedDate == null) {
    parsedDate = today;
  }

  // If nothing was parsed, return unmodified title
  if (parsedDate == null && parsedTime == null) {
    return QuickAddParseResult(
      strippedTitle: input.trim(),
      dueDate: null,
      dueTime: null,
      matchedPhrase: null,
    );
  }

  // Determine spans to remove from title
  final spansToRemove = <_SpanMatch>[];
  if (dateSpan != null) spansToRemove.add(dateSpan);
  if (timeSpan != null) spansToRemove.add(timeSpan);

  // Sort spans in descending order of start position so we can remove them cleanly
  spansToRemove.sort((a, b) => b.start.compareTo(a.start));

  var stripped = text;
  final matchedTexts = <String>[];

  // Also check if spans overlap or are contiguous
  if (dateSpan != null && timeSpan != null) {
    final first = dateSpan.start < timeSpan.start ? dateSpan : timeSpan;
    final second = dateSpan.start < timeSpan.start ? timeSpan : dateSpan;

    // If separated only by whitespace or "at", treat as single contiguous span
    final gap = text.substring(first.end, second.start);
    if (RegExp(r'^(?:\s*|\s*at\s*)$', caseSensitive: false).hasMatch(gap)) {
      final combinedStart = first.start;
      final combinedEnd = second.end;
      final fullMatched = text.substring(combinedStart, combinedEnd).trim();
      stripped = text.replaceRange(combinedStart, combinedEnd, ' ');
      matchedTexts.add(fullMatched);
    } else {
      // Remove separately
      for (final span in spansToRemove) {
        stripped = stripped.replaceRange(span.start, span.end, ' ');
        matchedTexts.add(span.text.trim());
      }
      matchedTexts.sort(); // consistent ordering
    }
  } else {
    for (final span in spansToRemove) {
      stripped = stripped.replaceRange(span.start, span.end, ' ');
      matchedTexts.add(span.text.trim());
    }
  }

  // Clean up any dangling prepositions (e.g. "by", "on", "at", "due") left at the boundaries
  stripped = stripped
      .replaceAll(RegExp(r'\b(?:on|by|due|at)\s*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'^\s*(?:on|by|due|at)\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // Combine matched phrases
  String? matchedPhrase;
  if (matchedTexts.isNotEmpty) {
    matchedPhrase = matchedTexts.join(' ').trim();
  }

  return QuickAddParseResult(
    strippedTitle: stripped,
    dueDate: parsedDate,
    dueTime: parsedTime,
    matchedPhrase: matchedPhrase,
  );
}

int? _weekdayToInt(String str) {
  if (str.startsWith('mon')) return DateTime.monday;
  if (str.startsWith('tue')) return DateTime.tuesday;
  if (str.startsWith('wed')) return DateTime.wednesday;
  if (str.startsWith('thu')) return DateTime.thursday;
  if (str.startsWith('fri')) return DateTime.friday;
  if (str.startsWith('sat')) return DateTime.saturday;
  if (str.startsWith('sun')) return DateTime.sunday;
  return null;
}
