import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Notifier holding the current search query string.
class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) => state = query;
}

/// Provider holding the current search query string.
final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);
