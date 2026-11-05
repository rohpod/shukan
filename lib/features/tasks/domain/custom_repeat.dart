import 'package:collection/collection.dart';

/// A user-defined repeat schedule: every [interval] days or weeks.
///
/// Stored in `Task.repeatCustomConfig` as
/// `{unit: 'day' | 'week', interval: 1..365, weekdays: [1..7]}`, with
/// `weekdays` (1 = Monday) only for weeks.
class CustomRepeat {
  const CustomRepeat({
    required this.unit,
    required this.interval,
    this.weekdays = const [],
  });

  static const unitDay = 'day';
  static const unitWeek = 'week';
  static const minInterval = 1;
  static const maxInterval = 365;

  final String unit;
  final int interval;
  final List<int> weekdays;

  bool get isWeekly => unit == unitWeek;

  /// Returns null when [map] is missing or doesn't describe a valid schedule.
  static CustomRepeat? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final unit = map['unit'];
    final interval = map['interval'];
    if (unit != unitDay && unit != unitWeek) return null;
    if (interval is! num || interval != interval.toInt()) return null;
    final n = interval.toInt();
    if (n < minInterval || n > maxInterval) return null;
    if (unit == unitDay) return CustomRepeat(unit: unitDay, interval: n);

    final raw = map['weekdays'];
    if (raw is! List || raw.isEmpty) return null;
    final days = <int>{};
    for (final d in raw) {
      if (d is! num || d != d.toInt() || d < 1 || d > 7) return null;
      days.add(d.toInt());
    }
    return CustomRepeat(
      unit: unitWeek,
      interval: n,
      weekdays: days.toList()..sort(),
    );
  }

  static const _weekdayNames = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  /// e.g. `Daily`, `Every 3 days`, `Every 2 weeks on Mon, Wed`.
  String get summary {
    if (!isWeekly) return interval == 1 ? 'Daily' : 'Every $interval days';
    final days = weekdays.map((d) => _weekdayNames[d - 1]).join(', ');
    final every = interval == 1 ? 'Every week' : 'Every $interval weeks';
    return '$every on $days';
  }

  Map<String, dynamic> toMap() => {
    'unit': unit,
    'interval': interval,
    if (isWeekly) 'weekdays': weekdays,
  };

  @override
  bool operator ==(Object other) =>
      other is CustomRepeat &&
      unit == other.unit &&
      interval == other.interval &&
      const ListEquality<int>().equals(weekdays, other.weekdays);

  @override
  int get hashCode => Object.hash(unit, interval, Object.hashAll(weekdays));
}
