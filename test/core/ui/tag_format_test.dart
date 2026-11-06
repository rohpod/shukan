import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/ui/tag_format.dart';

void main() {
  group('formatTag', () {
    test('prepends # to bare tag name', () {
      expect(formatTag('work'), equals('#work'));
      expect(formatTag('urgent'), equals('#urgent'));
    });

    test('is idempotent when name already has #', () {
      expect(formatTag('#work'), equals('#work'));
      expect(formatTag('#urgent'), equals('#urgent'));
    });
  });

  group('stripTagPrefix', () {
    test('strips single leading # from tag name', () {
      expect(stripTagPrefix('#work'), equals('work'));
      expect(stripTagPrefix('#urgent'), equals('urgent'));
    });

    test('preserves tag name without leading #', () {
      expect(stripTagPrefix('work'), equals('work'));
      expect(stripTagPrefix('urgent'), equals('urgent'));
    });

    test('trims surrounding whitespace while stripping leading #', () {
      expect(stripTagPrefix('  #work  '), equals('work'));
      expect(stripTagPrefix('  urgent  '), equals('urgent'));
      expect(stripTagPrefix('  #  '), equals(''));
      expect(stripTagPrefix('#'), equals(''));
      expect(stripTagPrefix('   '), equals(''));
    });
  });
}
