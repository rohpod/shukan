/// Stub download implementation for non-web platforms.
void downloadMarkdownFile(String content, String filename) {
  throw UnsupportedError('File download is only supported on web');
}
