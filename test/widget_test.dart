import 'package:flutter_test/flutter_test.dart';
import 'package:km2apps/main.dart';

void main() {
  group('GitHubService.thumbUrl', () {
    test('returns the original url unchanged while the thumb proxy is disabled', () {
      const url = 'https://raw.githubusercontent.com/owner/repo/main/1.jpg';
      expect(GitHubService.thumbUrl(url), url);
    });

    test('returns the original url for an empty input', () {
      expect(GitHubService.thumbUrl(''), '');
    });
  });

  group('WallpaperModel', () {
    test('isLandscape is true when width exceeds height', () {
      final wallpaper = WallpaperModel(
        id: '1',
        title: 'test',
        imageUrl: 'https://example.com/1.jpg',
        category: '16:9',
        repository: 'imag-16-9',
        width: 1920,
        height: 1080,
        uploadedAt: DateTime(2024),
      );
      expect(wallpaper.isLandscape, isTrue);
    });

    test('isLandscape is false when height exceeds width', () {
      final wallpaper = WallpaperModel(
        id: '2',
        title: 'test',
        imageUrl: 'https://example.com/2.jpg',
        category: 'Nature',
        repository: 'nature',
        width: 1080,
        height: 1920,
        uploadedAt: DateTime(2024),
      );
      expect(wallpaper.isLandscape, isFalse);
    });
  });
}
