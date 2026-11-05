import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/ui/safe_url.dart';

void main() {
  group('parseWebUrl', () {
    test('accepts http and https URLs', () {
      expect(parseWebUrl('https://example.com/a?b=1')!.host, 'example.com');
      expect(parseWebUrl('http://example.com')!.scheme, 'http');
      expect(parseWebUrl('  https://example.com  ')!.host, 'example.com');
    });

    test('adds https to a bare domain', () {
      expect(
        parseWebUrl('example.com/page')!.toString(),
        'https://example.com/page',
      );
      expect(
        parseWebUrl('localhost:8080/x')!.toString(),
        'https://localhost:8080/x',
      );
    });

    test('rejects other schemes and malformed input', () {
      for (final bad in [
        '',
        '   ',
        'javascript:alert(1)',
        'JavaScript:alert(1)',
        'data:text/html,<b>x</b>',
        'file:///etc/passwd',
        'ftp://example.com',
        'mailto:a@b.com',
        'https://',
        'not a url',
        'https://user:pw@example.com',
      ]) {
        expect(parseWebUrl(bad), isNull, reason: bad);
      }
    });
  });
}
