/// Shared UI utility for formatting and sanitizing tag names for display and input.
library;

/// Formats a tag name for display by ensuring it is prefixed with '#'.
String formatTag(String name) {
  if (name.startsWith('#')) return name;
  return '#$name';
}

/// Strips a single leading '#' from user input if present, returning the trimmed tag name.
String stripTagPrefix(String input) {
  final trimmed = input.trim();
  if (trimmed.startsWith('#')) {
    return trimmed.substring(1).trim();
  }
  return trimmed;
}
