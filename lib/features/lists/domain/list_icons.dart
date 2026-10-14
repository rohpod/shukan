import 'package:flutter/material.dart';

import '../data/list.dart';

const Map<String, IconData> kListIcons = {
  'folder': Icons.folder_outlined,
  'inbox': Icons.inbox_outlined,
  'star': Icons.star_outline,
  'bookmark': Icons.bookmark_outline,
  'checklist': Icons.checklist_outlined,
  'work': Icons.work_outline,
  'assignment': Icons.assignment_outlined,
  'code': Icons.code_outlined,
  'home': Icons.home_outlined,
  'shopping': Icons.shopping_cart_outlined,
  'favorite': Icons.favorite_outline,
  'people': Icons.people_outline,
  'fitness': Icons.fitness_center_outlined,
  'self_improvement': Icons.self_improvement_outlined,
  'book': Icons.book_outlined,
  'school': Icons.school_outlined,
  'lightbulb': Icons.lightbulb_outlined,
  'payments': Icons.payments_outlined,
  'flight': Icons.flight_outlined,
};

/// Resolves the display icon for a list, falling back to inbox for default lists
/// and folder for custom lists if no custom icon key is set or found in [kListIcons].
IconData resolveListIcon(ListModel list) =>
    kListIcons[list.icon] ??
    (list.isDefault ? Icons.inbox : Icons.folder_outlined);

/// Resolves the string key identifying the current icon of a list, falling back
/// to 'inbox' for default lists and 'folder' for custom lists if no icon is set.
String resolveListIconKey(ListModel list) =>
    list.icon ?? (list.isDefault ? 'inbox' : 'folder');
