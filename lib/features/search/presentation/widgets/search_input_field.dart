import 'package:flutter/material.dart';

class SearchInputField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final bool autofocus;

  const SearchInputField({
    super.key,
    required this.controller,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.autofocus = true,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return TextField(
          key: const Key('searchQueryInput'),
          controller: controller,
          autofocus: autofocus,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: 'Search tasks, notes, tags...',
            border: InputBorder.none,
            suffixIcon: value.text.isNotEmpty
                ? IconButton(
                    key: const Key('clearSearchQueryButton'),
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: onClear,
                  )
                : null,
          ),
          onChanged: onChanged,
          onSubmitted: onSubmitted,
        );
      },
    );
  }
}
