import 'package:flutter/material.dart';

import '../../domain/custom_repeat.dart';

const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Interval, unit and weekday inputs for a custom repeat.
///
/// Reports a new [CustomRepeat] through [onChanged] only while the interval is
/// valid. The form validators block saving otherwise.
class CustomRepeatFields extends StatefulWidget {
  const CustomRepeatFields({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final CustomRepeat value;
  final ValueChanged<CustomRepeat> onChanged;

  @override
  State<CustomRepeatFields> createState() => _CustomRepeatFieldsState();
}

class _CustomRepeatFieldsState extends State<CustomRepeatFields> {
  late final TextEditingController _intervalController;

  @override
  void initState() {
    super.initState();
    _intervalController = TextEditingController(
      text: widget.value.interval.toString(),
    );
  }

  @override
  void dispose() {
    _intervalController.dispose();
    super.dispose();
  }

  CustomRepeat get _value => widget.value;

  String? _validateInterval(String? text) {
    final n = int.tryParse((text ?? '').trim());
    if (n == null ||
        n < CustomRepeat.minInterval ||
        n > CustomRepeat.maxInterval) {
      return 'Enter a number from ${CustomRepeat.minInterval} '
          'to ${CustomRepeat.maxInterval}.';
    }
    return null;
  }

  void _emit({String? unit, int? interval, List<int>? weekdays}) {
    widget.onChanged(
      CustomRepeat(
        unit: unit ?? _value.unit,
        interval: interval ?? _value.interval,
        weekdays: weekdays ?? _value.weekdays,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plural = _value.interval == 1 ? '' : 's';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 90,
              child: TextFormField(
                key: const Key('customRepeatIntervalInput'),
                controller: _intervalController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Every'),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: _validateInterval,
                onChanged: (text) {
                  if (_validateInterval(text) == null) {
                    _emit(interval: int.parse(text.trim()));
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                key: const Key('customRepeatUnitInput'),
                initialValue: _value.unit,
                decoration: const InputDecoration(labelText: 'Unit'),
                items: [
                  DropdownMenuItem(
                    value: CustomRepeat.unitDay,
                    child: Text('day$plural'),
                  ),
                  DropdownMenuItem(
                    value: CustomRepeat.unitWeek,
                    child: Text('week$plural'),
                  ),
                ],
                onChanged: (unit) {
                  if (unit != null) _emit(unit: unit);
                },
              ),
            ),
          ],
        ),
        if (_value.isWeekly)
          FormField<List<int>>(
            key: ValueKey('customRepeatWeekdays_${_value.weekdays.join()}'),
            initialValue: _value.weekdays,
            validator: (days) => (days == null || days.isEmpty)
                ? 'Pick at least one day.'
                : null,
            builder: (field) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (var n = 1; n <= 7; n++)
                      FilterChip(
                        key: Key('customRepeatWeekday_$n'),
                        label: Text(_weekdayLabels[n - 1]),
                        selected: _value.weekdays.contains(n),
                        onSelected: (selected) {
                          final days = {..._value.weekdays};
                          selected ? days.add(n) : days.remove(n);
                          _emit(weekdays: days.toList()..sort());
                        },
                      ),
                  ],
                ),
                if (field.hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      field.errorText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
