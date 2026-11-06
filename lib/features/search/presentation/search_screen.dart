import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../../lists/providers/list_providers.dart';
import 'search_logic_mixin.dart';
import 'widgets/search_input_field.dart';
import 'widgets/search_results_view.dart';

export 'search_logic_mixin.dart';
export 'widgets/search_input_field.dart';
export 'widgets/search_results_view.dart';

class SearchScreen extends ConsumerStatefulWidget {
  final VoidCallback? onCollapse;
  const SearchScreen({super.key, this.onCollapse});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with SearchLogicMixin {
  @override
  void initState() {
    super.initState();
    initSearchLogic();
  }

  @override
  void dispose() {
    disposeSearchLogic();
    super.dispose();
  }

  void _handleCollapse() {
    if (widget.onCollapse != null) {
      widget.onCollapse!();
    } else {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);
    final effectiveList = ref.watch(effectiveDefaultListProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: SearchInputField(
          controller: searchController,
          onChanged: onSearchQueryChanged,
          onClear: clearSearchQuery,
          onSubmitted: (trimmed) {
            if (uid != null && effectiveList != null && trimmed.isNotEmpty) {
              handleAddTaskAction(
                uid: uid,
                list: effectiveList,
                trimmedQuery: trimmed,
                onCollapse: _handleCollapse,
              );
            }
          },
        ),
      ),
      body: SearchResultsView(
        searchController: searchController,
        hasParsedAdd: hasParsedAdd,
        parsedTitle: parsedTitle,
        parsedAddDueDate: parsedAddDueDate,
        parsedAddDueTime: parsedAddDueTime,
        isCreatingTask: isCreatingTask,
        onDismissAddChip: dismissAddChip,
        onAddTaskAction: (ctx, actionUid, actionList, query) =>
            handleAddTaskAction(
              uid: actionUid,
              list: actionList,
              trimmedQuery: query,
              onCollapse: _handleCollapse,
            ),
        onClearSearch: clearSearchQuery,
        onCollapse: _handleCollapse,
      ),
    );
  }
}
