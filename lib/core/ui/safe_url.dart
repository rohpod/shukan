/// Parses [input] as an http(s) URL, or returns null.
///
/// A bare domain such as `example.com/page` gets `https://`. Any other scheme
/// (`javascript:`, `data:`, `file:` ...) is rejected, so a stored URL can't
/// run script when opened.
Uri? parseWebUrl(String input) {
  final text = input.trim();
  if (text.isEmpty || text.contains(RegExp(r'\s'))) return null;

  final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(text);
  // `host:8080/path` looks like a scheme to the regex above.
  final looksLikeHostPort = RegExp(r'^[^/:?#]+:\d+([/?#]|$)').hasMatch(text);
  final candidate = hasScheme && !looksLikeHostPort ? text : 'https://$text';

  final uri = Uri.tryParse(candidate);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
  return uri;
}
