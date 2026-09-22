import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Completion filter modes for global task search.
enum SearchCompletionFilter { all, active, completed }

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

/// Notifier holding the selected completion filter.
class SearchCompletionFilterNotifier extends Notifier<SearchCompletionFilter> {
  @override
  SearchCompletionFilter build() => SearchCompletionFilter.active;

  void setFilter(SearchCompletionFilter filter) => state = filter;
}

/// Provider holding the selected completion filter.
/// Defaults to [SearchCompletionFilter.active] (hide completed by default).
final searchCompletionFilterProvider =
    NotifierProvider<SearchCompletionFilterNotifier, SearchCompletionFilter>(
      SearchCompletionFilterNotifier.new,
    );
