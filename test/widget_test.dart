import 'package:flutter_test/flutter_test.dart';
import 'package:km2apps/main.dart';

void main() {
  group('GitHubService.thumbUrl', () {
    test('returns the original url unchanged while the thumb proxy is disabled',
        () {
      const url = 'https://raw.githubusercontent.com/owner/repo/main/1.jpg';
      expect(GitHubService.thumbUrl(url), url);
    });

    test('returns the original url for an empty input', () {
      expect(GitHubService.thumbUrl(''), '');
    });
  });

  group('GitHubService.resolveRepositoryName', () {
    test('falls back to All-images for unknown categories', () {
      expect(GitHubService.resolveRepositoryName('Unknown Category'),
          'All-images');
    });

    test('keeps the mapped repository for known categories', () {
      expect(GitHubService.resolveRepositoryName('Nature'), 'nature');
      expect(GitHubService.resolveRepositoryName('All-images'), 'All-images');
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
