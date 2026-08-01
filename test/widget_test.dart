import 'package:flutter_test/flutter_test.dart';
import 'package:km2apps/main.dart';

void main() {
  group('Responsive banner layout', () {
    test('uses a compact banner config on small screens', () {
      final config = ResponsiveBannerConfig.fromScreenWidth(280);

      expect(config.height, 50);
      expect(config.useCompactLayout, isTrue);
    });

    test('uses a wider banner config on larger screens', () {
      final config = ResponsiveBannerConfig.fromScreenWidth(420);

      expect(config.height, 90);
      expect(config.useCompactLayout, isFalse);
    });
  });
}
