import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/list.dart';
import '../domain/list_icons.dart';
import '../providers/list_providers.dart';

/// Modal dialog displaying a grid of predefined icons for the user to pick from.
///
/// Tapping an icon immediately updates the list's icon in Firestore and closes the dialog.
class ListIconPickerDialog extends ConsumerWidget {
  final ListModel list;

  const ListIconPickerDialog({super.key, required this.list});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currentKey = resolveListIconKey(list);
    final entries = kListIcons.entries.toList();

    return AlertDialog(
      key: Key('listIconPickerDialog_${list.listId}'),
      title: const Row(
        children: [
          Icon(Icons.palette_outlined, size: 20),
          SizedBox(width: 8),
          Text('Choose Icon', style: TextStyle(fontSize: 18)),
        ],
      ),
      content: SizedBox(
        width: 280,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: GridView.builder(
            shrinkWrap: true,
            itemCount: entries.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              mainAxisExtent: 48,
            ),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final iconKey = entry.key;
              final iconData = entry.value;
              final isSelected = iconKey == currentKey;

              return Tooltip(
                message: iconKey,
                child: InkWell(
                  key: Key('listIconOption_$iconKey'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    Navigator.of(context).pop();
                    ref
                        .read(listRepositoryProvider)
                        .updateListIcon(list.listId, iconKey);
                  },
                  child: Container(
                    key: isSelected
                        ? Key('selectedListIconOption_$iconKey')
                        : null,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? theme.colorScheme.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      iconData,
                      color: isSelected
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                      size: 26,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('cancelListIconPickerButton'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
