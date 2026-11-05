import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Web implementation of text file download using a Blob and an anchor element.
void downloadTextFile(String content, String filename, String mimeType) {
  final bytes = utf8.encode(content);
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  (web.document.createElement('a') as web.HTMLAnchorElement)
    ..href = url
    ..download = filename
    ..click();
  web.URL.revokeObjectURL(url);
}
