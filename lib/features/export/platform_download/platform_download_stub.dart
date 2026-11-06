/// Stub download implementation for non-web platforms.
void downloadTextFile(String content, String filename, String mimeType) {
  throw UnsupportedError('File download is only supported on web');
}
