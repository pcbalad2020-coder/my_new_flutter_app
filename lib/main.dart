import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// =============================================================================
// 🔔 NOTIFICATION SERVICE — 1خدمة الإشعارات
// =============================================================================

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
}

class NotificationService {
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static Future<void> initialize() async {
    try {
      // 1. معالجة رسائل الخلفية
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);

      // ✅ التصحيح #1: هيّئ flutter_local_notifications أولاً قبل طلب أي إذن
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/launcher_icon');
      const DarwinInitializationSettings iosSettings =
          DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onLocalNotificationTap,
      );

      // قناة إشعارات أندرويد
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'high_importance_channel',
        'High Importance Notifications',
        description: 'This channel is used for important notifications.',
        importance: Importance.high,
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
      await _fcm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // الاستماع للإشعارات في المقدمة (Foreground)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        try {
          RemoteNotification? notification = message.notification;
          AppLogger.info(
              '📩 Foreground message received: ${message.messageId}');
          if (notification != null) {
            _localNotifications.show(
              notification.hashCode,
              notification.title,
              notification.body,
              NotificationDetails(
                android: AndroidNotificationDetails(
                  channel.id,
                  channel.name,
                  channelDescription: channel.description,
                  icon: '@mipmap/launcher_icon',
                ),
                iOS: const DarwinNotificationDetails(
                  presentAlert: true,
                  presentBadge: true,
                  presentSound: true,
                ),
              ),
              payload: jsonEncode(message.data),
            );
          }
        } catch (e) {
          AppLogger.error('❌ Error handling foreground message: $e');
        }
      });

      // عند الضغط على الإشعار (والتطبيق في الخلفية)
      FirebaseMessaging.onMessageOpenedApp
          .listen(_handleNotificationNavigation);

      // التحقق إذا فُتح التطبيق من خلال إشعار (والتطبيق مغلق تماماً)
      try {
        RemoteMessage? initialMessage = await _fcm.getInitialMessage();
        if (initialMessage != null) {
          _handleNotificationNavigation(initialMessage);
        }
      } catch (e) {
        AppLogger.error('❌ Error handling initial notification: $e');
      }
    } catch (e) {
      AppLogger.error(
          '❌ Critical error in NotificationService.initialize(): $e');
      rethrow;
    }
  }

  static Future<void> requestPermissionAndSubscribe() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyAsked =
        prefs.getBool('notification_permission_asked') ?? false;

    if (alreadyAsked) {
      if (await _hasNotificationPermission()) {
        unawaited(_subscribeAndLogToken());
      }
      return;
    }

    final granted = await _requestPermissions();
    AppLogger.info('🔔 Notification permission granted: $granted');
    await prefs.setBool('notification_permission_asked', true);

    if (granted) {
      unawaited(_subscribeAndLogToken());
    }
  }

  static Future<bool> _hasNotificationPermission() async {
    if (Platform.isAndroid) {
      final sdkInt = await _androidSdkInt();
      if (sdkInt < 33) return true;
      final status = await Permission.notification.status;
      return status.isGranted;
    }

    if (Platform.isIOS) {
      final settings = await _fcm.getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    }

    return true;
  }

  static Future<void> _subscribeAndLogToken() async {
    try {
      await _fcm.subscribeToTopic('all_users');
      String? token = await _fcm.getToken();
      AppLogger.success('🔥 FCM Token: $token');
    } catch (e) {
      AppLogger.error('❌ Failed to subscribe/get token: $e');
    }
  }

  // ✅ التصحيح #8: معالج جديد لضغطات الإشعار المحلي (كان غائباً)
  static void _onLocalNotificationTap(NotificationResponse response) {
    if (response.payload == null) return;
    try {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      _handleNotificationNavigation(RemoteMessage(
          data: data.map(
        (key, value) => MapEntry(key, value.toString()),
      )));
    } catch (e) {
      AppLogger.error('❌ Failed to parse notification payload: $e');
    }
  }

  static void _handleNotificationNavigation(RemoteMessage message) {
    try {
      print('Message clicked! ${message.data}');
      final data = message.data;

      // ✅ تحقق من أن navigator جاهز قبل الاستخدام
      if (navigatorKey.currentState == null) {
        AppLogger.warning(
            '⚠️ Navigator not ready yet, skipping notification navigation');
        return;
      }

      if (data['action'] == 'open_category' && data['category'] != null) {
        String category = data['category'];
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (context) =>
                CategoryWallpapersScreen(categoryName: category),
          ),
        );
      } else if (data['action'] == 'open_wallpaper' &&
          data['wallpaper_id'] != null) {
        String wallpaperId = data['wallpaper_id'];
        // يمكن إضافة منطق فتح الخلفية المحددة هنا لاحقاً
        AppLogger.info('📸 Opening wallpaper: $wallpaperId');
      }
    } catch (e) {
      AppLogger.error('❌ Error in _handleNotificationNavigation: $e');
    }
  }

  // ✅ التصحيح #9: ترجع bool الآن لمعرفة هل سُمح بالإذن فعلاً أم لا
  static Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      final sdkInt = await _androidSdkInt();
      if (sdkInt >= 33) {
        final status = await Permission.notification.status;
        if (status.isPermanentlyDenied) {
          await openAppSettings();
          return false;
        }
        if (!status.isGranted) {
          final requested = await Permission.notification.request();
          if (!requested.isGranted) {
            AppLogger.warning(
                '⚠️ Android notification permission not granted: $requested');
            return false;
          }
        }
      }
    }

    if (Platform.isIOS) {
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
        announcement: false,
        carPlay: false,
        criticalAlert: false,
      );
      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;

      if (!granted) {
        AppLogger.warning(
            '⚠️ User declined or has not accepted notification permissions: '
            '${settings.authorizationStatus}');
      }

      return granted;
    }

    return true;
  }

  static Future<int> _androidSdkInt() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    return androidInfo.version.sdkInt;
  }
}

// =============================================================================
// 📝 App Logger — نظام الـ logging
// =============================================================================
class AppLogger {
  static void info(String msg) => debugPrint('ℹ️  $msg');
  static void success(String msg) => debugPrint('✅ $msg');
  static void warning(String msg) => debugPrint('⚠️  $msg');
  static void error(String msg) => debugPrint('❌ $msg');
}

// =============================================================================
// 🔐 GALLERY PERMISSION HELPER — منطق موحّد لإذن حفظ الصور
// =============================================================================

class GalleryPermission {
  static Future<bool> isGranted() async {
    if (Platform.isIOS) {
      final status = await Permission.photos.status;
      return status.isGranted || status.isLimited;
    }
    final sdkInt = await _androidSdkInt();
    if (sdkInt >= 33) {
      return (await Permission.photos.status).isGranted;
    }
    if (sdkInt >= 29) {
      // Scoped Storage: لا حاجة لإذن لحفظ ملف جديد ينشئه التطبيق.
      return true;
    }
    return (await Permission.storage.status).isGranted;
  }

  /// يطلب الإذن إذا كان مطلوباً، ويرجع true عند النجاح (أو عدم الحاجة لإذن).
  static Future<bool> request() async {
    if (Platform.isIOS) {
      final status = await Permission.photos.request();
      return status.isGranted || status.isLimited;
    }
    final sdkInt = await _androidSdkInt();
    if (sdkInt >= 33) {
      final status = await Permission.photos.request();
      return status.isGranted;
    }
    if (sdkInt >= 29) {
      return true;
    }
    final status = await Permission.storage.request();
    return status.isGranted;
  }

  static Future<bool> isPermanentlyDenied() async {
    if (Platform.isIOS) {
      return (await Permission.photos.status).isPermanentlyDenied;
    }
    final sdkInt = await _androidSdkInt();
    if (sdkInt >= 33) {
      return (await Permission.photos.status).isPermanentlyDenied;
    }
    if (sdkInt >= 29) return false; // لا إذن مطلوب أصلاً
    return (await Permission.storage.status).isPermanentlyDenied;
  }

  static Future<int> _androidSdkInt() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    return androidInfo.version.sdkInt;
  }
}

// =============================================================================
// 0. ADMOB SERVICE — خدمة إدارة جميع أنواع الإعلانات
// =============================================================================
class AdMobIds {
  static String get bannerAdUnitId {
    if (Platform.isAndroid) return 'ca-app-pub-4756404048214956/3103410719';
    return 'ca-app-pub-3940256099942544/2934735716';
  }

  static String get interstitialAdUnitId {
    if (Platform.isAndroid) return 'ca-app-pub-4756404048214956/7589450639';
    return 'ca-app-pub-3940256099942544/4411468910';
  }

  static String get rewardedAdUnitId {
    if (Platform.isAndroid) return 'ca-app-pub-4756404048214956/8168076692';
    return 'ca-app-pub-3940256099942544/1712485313';
  }

  static String get nativeAdUnitId {
    if (Platform.isAndroid) return 'ca-app-pub-4756404048214956/2620236541';
    return 'ca-app-pub-3940256099942544/3986624511';
  }

  static String get appOpenAdUnitId {
    if (Platform.isAndroid) return 'ca-app-pub-4756404048214956/7070617440';
    return 'ca-app-pub-3940256099942544/5575463023';
  }
}

class AdMobManager {
  static final AdMobManager _instance = AdMobManager._internal();
  factory AdMobManager() => _instance;
  AdMobManager._internal();

  InterstitialAd? _interstitialAd;
  int _interstitialLoadAttempts = 0;
  static const int _maxFailedLoadAttempts = 3;
  RewardedAd? _rewardedAd;
  int _rewardedLoadAttempts = 0;
  AppOpenAd? _appOpenAd;
  bool _isShowingAd = false;
  DateTime? _appOpenLoadTime;
  int _viewCount = 0;
  static const int _interstitialInterval = 5;
  static const String _viewCountKey = 'admob_wallpaper_view_count';

  Future<void> initialize() async {
    await MobileAds.instance.initialize();
    try {
      final prefs = await SharedPreferences.getInstance();
      _viewCount = prefs.getInt(_viewCountKey) ?? 0;
    } catch (e) {
      AppLogger.error('Failed to load persisted ad view count: $e');
    }
    _loadInterstitialAd();
    _loadRewardedAd();
    _loadAppOpenAd();
  }

  BannerAd createBannerAd() {
    return BannerAd(
      adUnitId: AdMobIds.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) => AppLogger.success('Banner ad loaded'),
        onAdFailedToLoad: (ad, error) {
          AppLogger.error('Banner ad failed: $error');
          ad.dispose();
        },
      ),
    );
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: AdMobIds.interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _interstitialLoadAttempts = 0;
          _interstitialAd!.setImmersiveMode(true);
        },
        onAdFailedToLoad: (error) {
          _interstitialLoadAttempts++;
          _interstitialAd = null;
          if (_interstitialLoadAttempts < _maxFailedLoadAttempts)
            _loadInterstitialAd();
        },
      ),
    );
  }

  void showInterstitialAd({VoidCallback? onComplete}) {
    if (_interstitialAd == null) {
      onComplete?.call();
      _loadInterstitialAd();
      return;
    }
    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
        _loadInterstitialAd();
        onComplete?.call();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _interstitialAd = null;
        _loadInterstitialAd();
        onComplete?.call();
      },
    );
    _interstitialAd!.show();
  }

  void trackWallpaperView({VoidCallback? onAdComplete}) {
    _viewCount++;
    unawaited(_persistViewCount());
    if (_viewCount % _interstitialInterval == 0) {
      showInterstitialAd(onComplete: onAdComplete);
    } else {
      onAdComplete?.call();
    }
  }

  Future<void> _persistViewCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_viewCountKey, _viewCount);
    } catch (e) {
      AppLogger.error('Failed to persist ad view count: $e');
    }
  }

  void _loadRewardedAd() {
    RewardedAd.load(
      adUnitId: AdMobIds.rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _rewardedLoadAttempts = 0;
        },
        onAdFailedToLoad: (error) {
          _rewardedLoadAttempts++;
          _rewardedAd = null;
          if (_rewardedLoadAttempts < _maxFailedLoadAttempts) _loadRewardedAd();
        },
      ),
    );
  }

  void showRewardedAd({
    required Function(AdWithoutView, RewardItem) onUserEarnedReward,
    VoidCallback? onAdDismissed,
  }) {
    if (_rewardedAd == null) return;
    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        _loadRewardedAd();
        onAdDismissed?.call();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _rewardedAd = null;
        _loadRewardedAd();
      },
    );
    _rewardedAd!.show(onUserEarnedReward: onUserEarnedReward);
  }

  bool get isRewardedAdReady => _rewardedAd != null;

  void _loadAppOpenAd() {
    AppOpenAd.load(
      adUnitId: AdMobIds.appOpenAdUnitId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpenAd = ad;
          _appOpenLoadTime = DateTime.now();
        },
        onAdFailedToLoad: (error) => _appOpenAd = null,
      ),
    );
  }

  bool get _isAppOpenAdAvailable {
    if (_appOpenAd == null) return false;
    if (_appOpenLoadTime != null) {
      final diff = DateTime.now().difference(_appOpenLoadTime!);
      return diff.inHours < 4;
    }
    return false;
  }

  void showAppOpenAd({VoidCallback? onComplete}) {
    if (!_isAppOpenAdAvailable || _isShowingAd) {
      _loadAppOpenAd();
      onComplete?.call();
      return;
    }
    _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) => _isShowingAd = true,
      onAdDismissedFullScreenContent: (ad) {
        _isShowingAd = false;
        ad.dispose();
        _appOpenAd = null;
        _loadAppOpenAd();
        onComplete?.call();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        _isShowingAd = false;
        ad.dispose();
        _appOpenAd = null;
        _loadAppOpenAd();
        onComplete?.call();
      },
    );
    _appOpenAd!.show();
  }

  void dispose() {
    _interstitialAd?.dispose();
    _rewardedAd?.dispose();
    _appOpenAd?.dispose();
  }
}

// ─── Banner Ad Widget ─────────────────────────────────────────────────────────
class BannerAdWidget extends StatefulWidget {
  final AdSize adSize;
  const BannerAdWidget({super.key, this.adSize = AdSize.banner});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    _bannerAd = BannerAd(
      adUnitId: AdMobIds.bannerAdUnitId,
      size: widget.adSize,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) => ad.dispose(),
      ),
    );
    _bannerAd!.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _bannerAd == null) return const SizedBox.shrink();
    return Container(
      alignment: Alignment.center,
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}

class SmartBannerAdWidget extends StatefulWidget {
  const SmartBannerAdWidget({super.key});

  @override
  State<SmartBannerAdWidget> createState() => _SmartBannerAdWidgetState();
}

class _SmartBannerAdWidgetState extends State<SmartBannerAdWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bannerAd == null) _loadSmartBanner();
  }

  Future<void> _loadSmartBanner() async {
    final size = await AdSize.getAnchoredAdaptiveBannerAdSize(
      Orientation.portrait,
      MediaQuery.of(context).size.width.truncate(),
    );
    if (size == null) return;
    _bannerAd = BannerAd(
      adUnitId: AdMobIds.bannerAdUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) => ad.dispose(),
      ),
    );
    await _bannerAd!.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _bannerAd == null) return const SizedBox.shrink();
    return SizedBox(
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}

// =============================================================================
// 1. MODELS
// =============================================================================
class WallpaperModel {
  final String id;
  final String title;
  final String imageUrl;
  final String thumbnailUrl;
  final String category;
  final String repository;
  final int width;
  final int height;
  final DateTime uploadedAt;

  const WallpaperModel({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.thumbnailUrl,
    required this.category,
    required this.repository,
    required this.width,
    required this.height,
    required this.uploadedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'imageUrl': imageUrl,
        'thumbnailUrl': thumbnailUrl,
        'category': category,
        'repository': repository,
        'width': width,
        'height': height,
        'uploadedAt': uploadedAt.toIso8601String(),
      };

  factory WallpaperModel.fromJson(Map<String, dynamic> json) => WallpaperModel(
        id: json['id'],
        title: json['title'],
        imageUrl: json['imageUrl'],
        thumbnailUrl: json['thumbnailUrl'],
        category: json['category'],
        repository: json['repository'],
        width: json['width'],
        height: json['height'],
        uploadedAt: DateTime.parse(json['uploadedAt']),
      );

  bool get isLandscape => width > height;
}

class CategoryModel {
  final String name;
  final String repository;
  final IconData icon;
  final Color accentColor;

  const CategoryModel({
    required this.name,
    required this.repository,
    required this.icon,
    this.accentColor = Colors.blueAccent,
  });
}

// =============================================================================
// 2. GITHUB SERVICE
// =============================================================================
class GitHubService {
  static const String _owner = 'pcbalad2020-coder';
  static const String _branch = 'main';
  static const String _token =
      String.fromEnvironment('GITHUB_TOKEN', defaultValue: '');

  static const Map<String, String> repositories = {
    'All Images': 'All-images',
    'New': 'All-images',
    'Best': 'All-images',
    'Sport': 'sport',
    'Anime': 'anime_wallpapers',
    'anime': 'anime_wallpapers',
    'Cars': 'cars',
    'Nature': 'nature',
    'Space': 'space',
    '16:9': 'imag-16-9',
    '16:9 Ratio': 'imag-16-9',
  };

  static final Map<String, List<WallpaperModel>> _cache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheDuration = Duration(hours: 2);

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://api.github.com',
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'Accept': 'application/vnd.github.v3+json',
      'User-Agent': 'KM2-Wallpaper-App/1.1.0',
      if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
    },
  ));

  static Future<List<Map<String, dynamic>>> _fetchFromRepo(
      String repoName) async {
    try {
      AppLogger.info('📥 Fetching: $repoName');
      final response = await _dio.get(
        '/repos/$_owner/$repoName/contents',
        queryParameters: {'ref': _branch, 'per_page': 100},
      );
      if (response.statusCode == 200 && response.data is List) {
        final data = response.data as List;
        return data
            .where((item) => item['type'] == 'file')
            .where((item) {
              final name = (item['name'] as String).toLowerCase();
              return name.endsWith('.jpg') ||
                  name.endsWith('.jpeg') ||
                  name.endsWith('.png') ||
                  name.endsWith('.webp');
            })
            .map((item) => item as Map<String, dynamic>)
            .toList();
      }
      return [];
    } on DioException catch (e) {
      AppLogger.warning('⚠️ DioException fetching $repoName: ${e.message}');
      try {
        return await _fetchViaTrees(repoName);
      } catch (err) {
        AppLogger.error('❌ Fallback _fetchViaTrees also failed: $err');
        return [];
      }
    } catch (e) {
      AppLogger.error('❌ Error fetching wallpapers from $repoName: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> _fetchViaTrees(
      String repoName) async {
    final response = await _dio.get(
      '/repos/$_owner/$repoName/git/trees/$_branch',
      queryParameters: {'recursive': 1},
    );
    if (response.statusCode == 200 && response.data != null) {
      final tree = response.data['tree'] as List? ?? [];
      return tree.where((f) {
        final path = (f['path'] as String).toLowerCase();
        return f['type'] == 'blob' &&
            (path.endsWith('.jpg') ||
                path.endsWith('.jpeg') ||
                path.endsWith('.png') ||
                path.endsWith('.webp'));
      }).map((f) {
        final path = f['path'] as String;
        final filename = path.split('/').last;
        return {
          'name': filename,
          'download_url':
              'https://raw.githubusercontent.com/$_owner/$repoName/$_branch/$path',
          'type': 'file',
        };
      }).toList();
    }
    return [];
  }

  static Future<List<WallpaperModel>> getWallpapers(String categoryName) async {
    if (_cache.containsKey(categoryName) &&
        _cacheTimestamps.containsKey(categoryName)) {
      final age = DateTime.now().difference(_cacheTimestamps[categoryName]!);
      if (age < _cacheDuration) return _cache[categoryName]!;
    }

    final repoName = repositories[categoryName];
    if (repoName == null) return [];

    final files = await _fetchFromRepo(repoName);
    final is169 = categoryName == '16:9' || categoryName == '16:9 Ratio';
    final wallpapers = files.map((file) {
      final name = file['name'] as String? ?? 'unnamed';
      final downloadUrl = file['download_url'] as String? ?? '';
      return WallpaperModel(
        id: '${repoName}_$name',
        title: name.replaceAll(
            RegExp(r'\.(jpg|jpeg|png|webp)$', caseSensitive: false), ''),
        imageUrl: downloadUrl,
        thumbnailUrl: downloadUrl,
        category: categoryName,
        repository: repoName,
        width: is169 ? 1920 : 1080,
        height: is169 ? 1080 : 1920,
        uploadedAt: DateTime.now(),
      );
    }).toList()
      ..shuffle(Random());

    _cache[categoryName] = wallpapers;
    _cacheTimestamps[categoryName] = DateTime.now();
    return wallpapers;
  }

  static void clearCache() {
    _cache.clear();
    _cacheTimestamps.clear();
  }

  static Future<bool> testConnection() async {
    try {
      final response = await _dio.get('/rate_limit');
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}

// =============================================================================
// 3. COINS PROVIDER (نظام العملات)
// =============================================================================
class CoinsProvider with ChangeNotifier {
  int _coins = 0;
  bool _hasReceivedWelcomeBonus = false;

  int get coins => _coins;
  bool get hasReceivedWelcomeBonus => _hasReceivedWelcomeBonus;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _coins = prefs.getInt('user_coins') ?? 0;
    _hasReceivedWelcomeBonus = prefs.getBool('welcome_bonus_received') ?? false;
    notifyListeners();
  }

  // ✅ إضافة عملات ترحيبية عند أول فتح
  Future<void> giveWelcomeBonus() async {
    if (!_hasReceivedWelcomeBonus) {
      _coins += 50; // 🎁 عدد العملات الترحيبية (يمكنك تغييره)
      _hasReceivedWelcomeBonus = true;
      await _save();
      notifyListeners();
      AppLogger.success('🎁 Welcome bonus: 50 coins added!');
    }
  }

  Future<void> addCoins(int amount) async {
    _coins += amount;
    await _save();
    notifyListeners();
  }

  Future<bool> deductCoins(int amount) async {
    if (_coins >= amount) {
      _coins -= amount;
      await _save();
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('user_coins', _coins);
    await prefs.setBool('welcome_bonus_received', _hasReceivedWelcomeBonus);
  }
}

// =============================================================================
// 4. DOWNLOAD SERVICE
// =============================================================================
class DownloadService {
  static Future<void> downloadWallpaper(
    BuildContext context,
    WallpaperModel wallpaper,
  ) async {
    final hasPermission = await _requestStoragePermission(context);
    if (!hasPermission) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ يحتاج التطبيق إلى إذن الصور للحفظ',
                style: GoogleFonts.poppins()),
            backgroundColor: Colors.orange[800],
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
                label: 'الإعدادات',
                textColor: Colors.white,
                onPressed: () => openAppSettings()),
          ),
        );
      }
      return;
    }

    // ✅ خصم العملات قبل بدء التحميل
    final coinsProvider = Provider.of<CoinsProvider>(context, listen: false);
    if (coinsProvider.coins < 10) {
      if (context.mounted) showInsufficientCoinsDialog(context);
      return;
    }

    await coinsProvider.deductCoins(10);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم خصم 10 عملات 🪙 | الرصيد: ${coinsProvider.coins}',
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.orange[800],
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _DownloadProgressDialog(wallpaper: wallpaper),
      );
    }
  }

  static Future<bool> _requestStoragePermission(BuildContext context) async {
    final granted = await GalleryPermission.request();
    if (granted) return true;
    if (await GalleryPermission.isPermanentlyDenied() && context.mounted) {
      openAppSettings();
    }
    return false;
  }
}

class _DownloadProgressDialog extends StatefulWidget {
  final WallpaperModel wallpaper;
  const _DownloadProgressDialog({required this.wallpaper});

  @override
  State<_DownloadProgressDialog> createState() =>
      _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  double _progress = 0;
  String _status = 'جاري التحميل...';
  bool _done = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final safeTitle =
          widget.wallpaper.title.replaceAll(RegExp(r'[^\w\u0600-\u06FF]'), '_');
      final fileName =
          '${safeTitle}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savePath = '${tempDir.path}/$fileName';
      final dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 120)));

      await dio.download(
        widget.wallpaper.imageUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1 && mounted)
            setState(() => _progress = received / total);
        },
      );

      final result = await SaverGallery.saveFile(
        file: savePath,
        name: safeTitle,
        androidRelativePath: 'Pictures/4K خلفيات',
        androidExistNotSave: false,
      );

      final tempFile = File(savePath);
      if (await tempFile.exists()) await tempFile.delete();

      if (mounted) {
        setState(() {
          _done = result.isSuccess;
          _error = !result.isSuccess;
          _status = result.isSuccess ? 'تم الحفظ في المعرض ✅' : 'فشل الحفظ ❌';
        });
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = true;
          _status = 'خطأ: $e';
        });
        await Future.delayed(const Duration(seconds: 3));
        if (mounted) Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A2533),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(_done ? 'تم التحميل!' : (_error ? 'خطأ' : 'جاري التحميل'),
          style: GoogleFonts.poppins(
              color: Colors.white, fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.wallpaper.title,
              style: GoogleFonts.poppins(color: Colors.grey[400], fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 20),
          if (!_done && !_error)
            LinearProgressIndicator(
                value: _progress == 0 ? null : _progress,
                backgroundColor: Colors.grey[800],
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                borderRadius: BorderRadius.circular(8),
                minHeight: 8)
          else
            Container(
                height: 8,
                decoration: BoxDecoration(
                    color: _done ? Colors.green : Colors.red,
                    borderRadius: BorderRadius.circular(8))),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_done)
                const Icon(Icons.check_circle, color: Colors.green, size: 18),
              if (_error) const Icon(Icons.error, color: Colors.red, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    _done || _error
                        ? _status
                        : '${(_progress * 100).toStringAsFixed(0)}%',
                    style: GoogleFonts.poppins(
                        color: _done
                            ? Colors.green
                            : (_error ? Colors.red : Colors.white70),
                        fontSize: 13),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 5. STATE MANAGEMENT
// =============================================================================
class AppProvider with ChangeNotifier {
  int _currentIndex = 0;
  int get currentIndex => _currentIndex;
  void changeTab(int index) {
    if (_currentIndex != index) {
      _currentIndex = index;
      notifyListeners();
    }
  }
}

class FavoritesProvider with ChangeNotifier {
  final Set<String> _favoriteIds = {};
  final List<WallpaperModel> _favorites = [];
  Set<String> get favoriteIds => _favoriteIds;
  List<WallpaperModel> get favorites => List.unmodifiable(_favorites);
  bool isFavorite(String id) => _favoriteIds.contains(id);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList('favorites') ?? [];
    _favorites.clear();
    _favoriteIds.clear();
    for (final jsonStr in jsonList) {
      try {
        final w = WallpaperModel.fromJson(jsonDecode(jsonStr));
        _favorites.add(w);
        _favoriteIds.add(w.id);
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> toggle(WallpaperModel wallpaper) async {
    if (_favoriteIds.contains(wallpaper.id)) {
      _favoriteIds.remove(wallpaper.id);
      _favorites.removeWhere((w) => w.id == wallpaper.id);
    } else {
      _favoriteIds.add(wallpaper.id);
      _favorites.insert(0, wallpaper);
    }
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'favorites', _favorites.map((w) => jsonEncode(w.toJson())).toList());
  }

  Future<void> clearAll() async {
    _favoriteIds.clear();
    _favorites.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('favorites');
    notifyListeners();
  }
}

class PrivacyProvider with ChangeNotifier {
  bool _accepted = false;
  bool get accepted => _accepted;
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _accepted = prefs.getBool('privacy_accepted') ?? false;
    notifyListeners();
  }

  Future<void> accept() async {
    _accepted = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('privacy_accepted', true);
    notifyListeners();
  }
}

class PermissionsInitializer {
  static Future<void> requestOnFirstLaunch(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyGranted = prefs.getBool('permissions_granted') ?? false;
    if (alreadyGranted) return;
    await _requestUntilGranted(context);
  }

  static Future<void> _requestUntilGranted(BuildContext context) async {
    int attempts = 0;
    const int maxAttempts = 3;
    while (attempts < maxAttempts) {
      final granted = await GalleryPermission.request();
      if (granted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('permissions_granted', true);
        return;
      }
      attempts++;
      if (!context.mounted) return;

      if (await GalleryPermission.isPermanentlyDenied()) {
        openAppSettings();
        return;
      }

      if (attempts >= maxAttempts) {
        openAppSettings();
        return;
      }
      final retry = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: const Color(0xFF1A2533),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Column(children: [
              Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.15),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.photo_library_rounded,
                      color: Colors.blueAccent, size: 36)),
              const SizedBox(height: 14),
              Text('إذن الصور مطلوب',
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18),
                  textAlign: TextAlign.center),
            ]),
            content: Text(
                'يحتاج التطبيق إلى إذن الوصول للصور لحفظ الخلفيات في معرض جهازك.',
                style: GoogleFonts.poppins(
                    color: Colors.grey[300], fontSize: 13, height: 1.8),
                textAlign: TextAlign.center),
            actionsAlignment: MainAxisAlignment.center,
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            actions: [
              SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: Text('السماح بالوصول للصور',
                          style:
                              GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14))))),
              const SizedBox(height: 8),
              SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                      onPressed: () {
                        openAppSettings();
                        Navigator.pop(context, false);
                      },
                      icon: const Icon(Icons.settings_outlined,
                          size: 16, color: Colors.grey),
                      label: Text('فتح إعدادات التطبيق',
                          style: GoogleFonts.poppins(
                              color: Colors.grey, fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                          side: BorderSide(
                              color: Colors.grey.withValues(alpha: 0.3)),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14))))),
            ],
          ),
        ),
      );
      if (retry != true) return;
    }
  }
}

// =============================================================================
// HELPER FUNCTIONS (دوال مساعدة للعملات والإعلانات)
// =============================================================================
void watchAdForCoins(BuildContext context) {
  AdMobManager().showRewardedAd(
    onUserEarnedReward: (ad, reward) async {
      final coinsProvider = Provider.of<CoinsProvider>(context, listen: false);
      await coinsProvider.addCoins(5);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '🎉 حصلت على 5 عملات! رصيدك: ${coinsProvider.coins} 🪙',
                style: GoogleFonts.poppins()),
            backgroundColor: Colors.green[700],
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    },
    onAdDismissed: () {},
  );
}

void showInsufficientCoinsDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1A2533),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.monetization_on, color: Colors.amber),
          const SizedBox(width: 8),
          Text('عملات غير كافية',
              style: GoogleFonts.poppins(
                  color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
      content: Text(
        'تحتاج إلى 10 عملات لتحميل هذه الصورة.\nشاهد إعلاناً لكسب 5 عملات!',
        style: GoogleFonts.poppins(color: Colors.grey[400]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('إلغاء', style: GoogleFonts.poppins(color: Colors.grey)),
        ),
        ElevatedButton.icon(
          onPressed: () {
            Navigator.pop(context);
            watchAdForCoins(context);
          },
          icon: const Icon(Icons.play_circle_outline, size: 18),
          label: Text('شاهد إعلاناً (+5 🪙)',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber[700],
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    ),
  );
}

// =============================================================================
// PRIVACY TEXT
// =============================================================================
const String kPrivacyPolicyText = '''
سياسة الخصوصية – 4K خلفيات
Privacy Policy – 4K Wallpapers
آخر تحديث / Last Updated: مايو 2026

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[AR] 1. المعلومات التي يتم جمعها
نحن لا نطلب إنشاء حساب داخل التطبيق ولا نقوم بجمع أو تخزين أي معلومات شخصية تحدد هويتك (مثل الاسم أو البريد الإلكتروني). قد تقوم بعض خدمات الطرف الثالث المستخدمة بجمع بيانات تقنية بشكل تلقائي لتحسين الأداء وعرض الإعلانات، وتشمل: نوع الجهاز، نظام التشغيل، عنوان IP، ومعرّفات الإعلانات.

[EN] 1. Information We Collect
We do not require account creation and we do not collect or store personal information (such as names or emails). Third-party services may automatically collect technical data to improve performance and display ads, including: device type, operating system, IP address, and advertising identifiers.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[AR] 2. الإعلانات
يستخدم التطبيق خدمة Google AdMob لعرض الإعلانات. قد تستخدم Google وشركاؤها معرّفات الإعلانات لتقديم إعلانات مخصصة تهم المستخدم بناءً على اهتماماته.

[EN] 2. Advertising
The application uses Google AdMob to display advertisements. Google and its partners may use advertising identifiers to provide personalized ads based on your interests.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[AR] 3. أذونات التطبيق
يتطلب التطبيق الوصول إلى بعض الأذونات الأساسية ليعمل بشكل صحيح:
- إذن الإنترنت: لتحميل الصور المتجددة وعرض الإعلانات.
- إذن التخزين أو الصور: لحفظ وتحميل الخلفيات مباشرة داخل جهازك. نحن لا نصل إلى صورك الخاصة ولا نقوم بجمعها أو مشاركتها أبداً.

[EN] 3. App Permissions
The app requires the following essential permissions to function properly:
- Internet Permission: To load online wallpapers and display ads.
- Storage/Photos Permission: To allow saving and downloading wallpapers onto your device. We never access, collect, or share your personal photos.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[AR] 4. خدمات الطرف الثالث
يستخدم التطبيق خدمات تابعة لشركة Google تساعد في استقرار التطبيق وتحسين تجربة الاستخدام، وهي:
Google Play Services, Google AdMob, Firebase Analytics, Firebase Crashlytics.

[EN] 4. Third-Party Services
The app utilizes Google services to improve stability, user experience, and performance:
Google Play Services, Google AdMob, Firebase Analytics, Firebase Crashlytics.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[AR] 5. أمان البيانات
نحن نسعى لحماية بياناتك التقنية باستخدام وسائل أمان مناسبة، ولكن يرجى العلم أنه لا يمكن ضمان الحماية الكاملة بنسبة 100% لأي خدمة عبر الإنترنت.

[EN] 5. Data Security
We strive to protect your technical data using appropriate security measures, but no internet-based service can be guaranteed to be 100% secure.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[AR] 6. خصوصية الأطفال
هذا التطبيق غير موجه للأطفال دون سن 13 عاماً، ونحن لا نجمع أي بيانات تخصهم بشكل متعمد.

[EN] 6. Children's Privacy
This application is not intended for or directed at children under the age of 13.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[AR] 7. التعديلات على السياسة
قد نقوم بتحديث سياسة الخصوصية هذه من وقت لآخر لمواكبة أي تغييرات في التطبيق أو القوانين، وسيتم نشر أي تحديث مباشرة داخل هذه الصفحة.

[EN] 7. Changes to This Privacy Policy
We may update our Privacy Policy from time to time. Any changes will be updated and posted directly on this page.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[AR] 8. التواصل معنا
إذا كان لديك أي استفسار أو سؤال بخصوص سياسة الخصوصية، يمكنك التواصل معنا عبر صفحة التطبيق الرسمية على متجر Google Play أو عبر بريد الدعم الفني الموضح في صفحة المتجر.

[EN] 8. Contact Us
If you have any questions regarding this Privacy Policy, please contact us through our official Google Play Store page or via the support email listed on the store.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
© 2026 4K Wallpapers - All Rights Reserved
''';

// =============================================================================
// 6. WIDGETS
// =============================================================================
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  const GlassContainer(
      {super.key,
      required this.child,
      this.blur = 12.0,
      this.opacity = 0.08,
      this.padding = EdgeInsets.zero,
      this.borderRadius = const BorderRadius.all(Radius.circular(20))});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: opacity),
              borderRadius: borderRadius,
              border: Border.all(color: Colors.white.withValues(alpha: 0.15))),
          child: child,
        ),
      ),
    );
  }
}

class ShimmerLoadingCard extends StatelessWidget {
  const ShimmerLoadingCard({super.key});
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[850]!,
      highlightColor: Colors.grey[700]!,
      child: Container(
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(16))),
    );
  }
}

class FavoriteButton extends StatelessWidget {
  final WallpaperModel wallpaper;
  const FavoriteButton({super.key, required this.wallpaper});

  @override
  Widget build(BuildContext context) {
    return Consumer<FavoritesProvider>(
      builder: (context, favProvider, _) {
        final isFav = favProvider.isFavorite(wallpaper.id);
        return GestureDetector(
          onTap: () async {
            await favProvider.toggle(wallpaper);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content:
                      Text(isFav ? '💔 حُذف من المفضلة' : '❤️ أُضيف للمفضلة'),
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))));
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isFav
                    ? Colors.red.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.1)),
            child: Icon(isFav ? Icons.favorite : Icons.favorite_border,
                color: isFav ? Colors.red : Colors.white, size: 24),
          ),
        );
      },
    );
  }
}

class WallpaperCard extends StatelessWidget {
  final WallpaperModel wallpaper;
  final VoidCallback? onTap;
  final double? width;
  final double? height;
  final Object heroTag;
  const WallpaperCard(
      {super.key,
      required this.wallpaper,
      required this.heroTag,
      this.onTap,
      this.width,
      this.height});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Hero(
        tag: heroTag,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4))
              ]),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                    imageUrl: wallpaper.thumbnailUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => const ShimmerLoadingCard(),
                    errorWidget: (_, __, ___) => Container(
                        color: Colors.grey[850],
                        child: const Icon(Icons.broken_image,
                            color: Colors.grey))),
                Container(
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7)
                    ]))),
                Positioned(
                    bottom: 10,
                    left: 8,
                    right: 8,
                    child: Text(wallpaper.title,
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
                Positioned(
                    top: 6,
                    right: 6,
                    child: Consumer<FavoritesProvider>(
                        builder: (_, fav, __) => fav.isFavorite(wallpaper.id)
                            ? const Icon(Icons.favorite,
                                color: Colors.red, size: 16)
                            : const SizedBox.shrink())),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class WallpaperCard169 extends StatelessWidget {
  final WallpaperModel wallpaper;
  final VoidCallback? onTap;
  final Object heroTag;
  const WallpaperCard169(
      {super.key, required this.wallpaper, required this.heroTag, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Hero(
        tag: heroTag,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                  imageUrl: wallpaper.thumbnailUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => const ShimmerLoadingCard(),
                  errorWidget: (_, __, ___) => Container(
                      color: Colors.grey[850],
                      child:
                          const Icon(Icons.broken_image, color: Colors.grey))),
              Container(
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.65)
                  ]))),
              Positioned(
                  bottom: 10,
                  left: 12,
                  right: 12,
                  child: Text(wallpaper.title,
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// 7. PRIVACY SCREENS
// =============================================================================
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
              Color(0xFF0F0F1A),
              Color(0xFF0F2027),
              Color(0xFF1A1A2E)
            ])),
        child: SafeArea(
          child: Column(children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(children: [
                  IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new,
                          color: Colors.white, size: 20),
                      onPressed: () => Navigator.pop(context)),
                  Text('سياسة الخصوصية',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 18))
                ])),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12))),
                      child: SingleChildScrollView(
                          child: Text(kPrivacyPolicyText,
                              style: GoogleFonts.poppins(
                                  color: Colors.white.withValues(alpha: 0.88),
                                  fontSize: 13.5,
                                  height: 1.9),
                              textDirection: TextDirection.rtl)),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class PrivacyPolicyDialog extends StatefulWidget {
  const PrivacyPolicyDialog({super.key});
  @override
  State<PrivacyPolicyDialog> createState() => _PrivacyPolicyDialogState();
}

class _PrivacyPolicyDialogState extends State<PrivacyPolicyDialog> {
  bool _scrolledToEnd = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 20) {
        if (!_scrolledToEnd) setState(() => _scrolledToEnd = true);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.78),
          decoration: BoxDecoration(
              gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0F2027), Color(0xFF1A1A2E)]),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: BoxDecoration(
                  border: Border(
                      bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.1)))),
              child: Row(children: [
                Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: Colors.blueAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.privacy_tip_outlined,
                        color: Colors.blueAccent, size: 22)),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('سياسة الخصوصية',
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 17)),
                      Text('يرجى القراءة قبل المتابعة',
                          style: GoogleFonts.poppins(
                              color: Colors.grey[400], fontSize: 12))
                    ])),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                      controller: _scrollController,
                      child: Text(kPrivacyPolicyText,
                          style: GoogleFonts.poppins(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 13,
                              height: 1.8),
                          textDirection: TextDirection.rtl)),
                ),
              ),
            ),
            if (!_scrolledToEnd)
              Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.keyboard_arrow_down,
                            color: Colors.blueAccent.withValues(alpha: 0.7),
                            size: 18),
                        Text('مرر للأسفل للمتابعة',
                            style: GoogleFonts.poppins(
                                color: Colors.grey[500], fontSize: 11))
                      ])),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await context.read<PrivacyProvider>().accept();
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 0),
                  child: Text('أوافق على سياسة الخصوصية',
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// =============================================================================
// 8. SPLASH SCREEN
// =============================================================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;
  late Animation<double> _textFadeAnim;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800));
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.5, curve: Curves.easeIn)));
    _scaleAnim = Tween<double>(begin: 0.6, end: 1).animate(CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.6, curve: Curves.elasticOut)));
    _textFadeAnim = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.5, 1.0, curve: Curves.easeIn)));
    _controller.forward();

    bool adFinished = false;
    bool splashTimeElapsed = false;
    bool navigated = false;

    void maybeNavigate() {
      if (navigated) return;
      if (adFinished && splashTimeElapsed) {
        navigated = true;
        if (!mounted) return;
        Navigator.of(context).pushReplacement(PageRouteBuilder(
            pageBuilder: (_, anim, __) =>
                FadeTransition(opacity: anim, child: const MainLayout()),
            transitionDuration: const Duration(milliseconds: 600)));
      }
    }

    AdMobManager().showAppOpenAd(onComplete: () {
      adFinished = true;
      maybeNavigate();
    });

    Future.delayed(const Duration(milliseconds: 3000), () {
      splashTimeElapsed = true;
      maybeNavigate();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
              Color(0xFF0A1628),
              Color(0xFF0F2027),
              Color(0xFF1A1035)
            ])),
        child: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (_, __) => Opacity(
                  opacity: _fadeAnim.value,
                  child: Transform.scale(
                      scale: _scaleAnim.value,
                      child: Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.blue.withValues(alpha: 0.4),
                                    blurRadius: 30,
                                    spreadRadius: 5),
                                BoxShadow(
                                    color: Colors.purple.withValues(alpha: 0.3),
                                    blurRadius: 50,
                                    spreadRadius: 10)
                              ]),
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(30),
                              child: Image.asset('assets/icon.png',
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                      decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(30),
                                          gradient: const LinearGradient(
                                              colors: [
                                                Color(0xFF1565C0),
                                                Color(0xFF7B1FA2)
                                              ])),
                                      child: const Icon(Icons.wallpaper,
                                          color: Colors.white, size: 60))))))),
            ),
            const SizedBox(height: 28),
            AnimatedBuilder(
              animation: _controller,
              builder: (_, __) => Opacity(
                  opacity: _textFadeAnim.value,
                  child: Column(children: [
                    Text('مرحباً 👋',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('اكتشف أجمل الخلفيات',
                        style: GoogleFonts.poppins(
                            color: Colors.white60, fontSize: 16))
                  ])),
            ),
            const SizedBox(height: 60),
            AnimatedBuilder(
              animation: _controller,
              builder: (_, __) => Opacity(
                  opacity: _textFadeAnim.value,
                  child: SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                          color: Colors.blueAccent.withValues(alpha: 0.8),
                          strokeWidth: 2.5))),
            ),
          ]),
        ),
      ),
    );
  }
}

// =============================================================================
// 9. PREVIEW SCREEN
// =============================================================================
class PreviewScreen extends StatefulWidget {
  final WallpaperModel wallpaper;
  final Object heroTag;
  final List<WallpaperModel> wallpapers;
  final int initialIndex;
  const PreviewScreen(
      {super.key,
      required this.wallpaper,
      required this.heroTag,
      required this.wallpapers,
      required this.initialIndex});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _handleDownload(BuildContext context, WallpaperModel wallpaper) {
    final coinsProvider = Provider.of<CoinsProvider>(context, listen: false);
    if (coinsProvider.coins >= 10) {
      DownloadService.downloadWallpaper(context, wallpaper);
    } else {
      showInsufficientCoinsDialog(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemCount: widget.wallpapers.length,
        itemBuilder: (context, index) {
          final wallpaper = widget.wallpapers[index];
          return Stack(children: [
            Positioned.fill(
                child: CachedNetworkImage(
                    imageUrl: wallpaper.imageUrl,
                    fit: wallpaper.isLandscape ? BoxFit.fitWidth : BoxFit.cover,
                    placeholder: (_, __) => Container(
                        color: Colors.grey[900],
                        child: const Center(
                            child: CircularProgressIndicator(
                                color: Colors.blueAccent))),
                    errorWidget: (_, __, ___) => Container(
                        color: Colors.grey[900],
                        child: const Icon(Icons.error,
                            color: Colors.white, size: 48)))),
            Positioned.fill(
                child: Container(
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [
                  0.0,
                  0.35,
                  0.7,
                  1.0
                ],
                            colors: [
                  Colors.black.withValues(alpha: 0.45),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.95)
                ])))),
            Positioned(
              top: 48,
              left: 16,
              right: 16,
              child: GlassContainer(
                opacity: 0.12,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                borderRadius: BorderRadius.circular(30),
                child: Row(children: [
                  IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new,
                          color: Colors.white, size: 20),
                      onPressed: () => Navigator.pop(context)),
                  const Spacer(),
                  FavoriteButton(wallpaper: wallpaper),
                  const SizedBox(width: 4),
                  IconButton(
                      icon: const Icon(Icons.share,
                          color: Colors.white, size: 22),
                      onPressed: () => Share.share(
                          'شاهد هذه الخلفية الرائعة: ${wallpaper.title}\n${wallpaper.imageUrl}')),
                ]),
              ),
            ),
            Positioned(
              bottom: 40,
              left: 16,
              right: 16,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const BannerAdWidget(),
                const SizedBox(height: 8),
                GlassContainer(
                  opacity: 0.14,
                  padding: const EdgeInsets.all(18),
                  borderRadius: BorderRadius.circular(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(wallpaper.title,
                                style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            Text(
                                '${wallpaper.category} • ${wallpaper.width}×${wallpaper.height}',
                                style: GoogleFonts.poppins(
                                    color: Colors.grey[400], fontSize: 11))
                          ])),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                              color: Colors.blueAccent.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: Colors.blueAccent
                                      .withValues(alpha: 0.5))),
                          child: Text(wallpaper.isLandscape ? '16:9' : '9:16',
                              style: GoogleFonts.poppins(
                                  color: Colors.blueAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600))),
                    ]),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.download_rounded,
                          label: 'تحميل (10 🪙)',
                          color: Colors.blueAccent,
                          onTap: () => _handleDownload(context, wallpaper),
                        ),
                      ),
                    ]),
                  ]),
                ),
              ]),
            ),
            Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(
                    child: Text(
                        '${_currentIndex + 1}/${widget.wallpapers.length}',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)))),
          ]);
        },
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label,
          style:
              GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0),
    );
  }
}

// =============================================================================
// 10. WALLPAPER GRID LOADER
// =============================================================================
class CategoryWallpapersScreen extends StatelessWidget {
  final String categoryName;
  const CategoryWallpapersScreen({super.key, required this.categoryName});

  @override
  Widget build(BuildContext context) {
    final is169 = categoryName == '16:9' || categoryName == '16:9 Ratio';
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new,
                  color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context)),
          title: Text(categoryName,
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold, color: Colors.white))),
      body:
          _WallpaperGridLoader(categoryName: categoryName, isLandscape: is169),
    );
  }
}

class _WallpaperGridLoader extends StatefulWidget {
  final String categoryName;
  final bool isLandscape;
  const _WallpaperGridLoader(
      {required this.categoryName, this.isLandscape = false});

  @override
  State<_WallpaperGridLoader> createState() => _WallpaperGridLoaderState();
}

class _WallpaperGridLoaderState extends State<_WallpaperGridLoader> {
  late Future<List<WallpaperModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = GitHubService.getWallpapers(widget.categoryName);
  }

  void _refresh() {
    GitHubService.clearCache();
    setState(() => _future = GitHubService.getWallpapers(widget.categoryName));
  }

  void _navigateWithAd(WallpaperModel wallpaper, Object heroTag,
      List<WallpaperModel> wallpapers, int initialIndex) {
    AdMobManager().trackWallpaperView(
      onAdComplete: () {
        if (mounted) {
          Navigator.push(
              context,
              PageRouteBuilder(
                  pageBuilder: (_, anim, __) => FadeTransition(
                      opacity: anim,
                      child: PreviewScreen(
                          wallpaper: wallpaper,
                          heroTag: heroTag,
                          wallpapers: wallpapers,
                          initialIndex: initialIndex)),
                  transitionDuration: const Duration(milliseconds: 300)));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<WallpaperModel>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return widget.isLandscape ? _shimmerLandscape() : _shimmerGrid();
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Icon(Icons.folder_open, size: 64, color: Colors.grey[600]),
                const SizedBox(height: 16),
                Text('لا توجد صور',
                    style: GoogleFonts.poppins(color: Colors.grey)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                    label: Text('إعادة المحاولة', style: GoogleFonts.poppins()),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))))
              ]));
        }
        final wallpapers = snapshot.data!;
        return Column(children: [
          const SmartBannerAdWidget(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _refresh(),
              color: Colors.blueAccent,
              child: widget.isLandscape
                  ? ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      itemCount: wallpapers.length,
                      itemBuilder: (context, index) {
                        return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: AspectRatio(
                                aspectRatio: 16 / 9,
                                child: WallpaperCard169(
                                    wallpaper: wallpapers[index],
                                    heroTag:
                                        'wp_${wallpapers[index].id}_${widget.categoryName}_$index',
                                    onTap: () => _navigateWithAd(
                                        wallpapers[index],
                                        'wp_${wallpapers[index].id}_${widget.categoryName}_$index',
                                        wallpapers,
                                        index))));
                      },
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.65,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12),
                      itemCount: wallpapers.length,
                      itemBuilder: (context, index) {
                        final heroTag =
                            'wp_${wallpapers[index].id}_${widget.categoryName}_$index';
                        return WallpaperCard(
                            wallpaper: wallpapers[index],
                            heroTag: heroTag,
                            onTap: () => _navigateWithAd(
                                wallpapers[index], heroTag, wallpapers, index));
                      },
                    ),
            ),
          ),
        ]);
      },
    );
  }

  Widget _shimmerGrid() => GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.65,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12),
      itemCount: 10,
      itemBuilder: (_, __) => const ShimmerLoadingCard());
  Widget _shimmerLandscape() => ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AspectRatio(
              aspectRatio: 16 / 9, child: const ShimmerLoadingCard())));
}

// =============================================================================
// 11. HOME SCREEN
// =============================================================================
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _navigateTo(BuildContext context, String category) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => CategoryWallpapersScreen(categoryName: category)));
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(slivers: [
      SliverAppBar(
        floating: true,
        snap: true,
        backgroundColor: Colors.transparent,
        title: Text('KM2 Wallpapers',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 24,
                color: Colors.white)),
        actions: [
          Consumer<CoinsProvider>(
            builder: (context, coins, _) => Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: Colors.amber.withValues(alpha: 0.4))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.monetization_on,
                    color: Colors.amber, size: 18),
                const SizedBox(width: 4),
                Text('${coins.coins}',
                    style: GoogleFonts.poppins(
                        color: Colors.amber,
                        fontWeight: FontWeight.bold,
                        fontSize: 14))
              ]),
            ),
          ),
          IconButton(
              icon: const Icon(Icons.favorite_border, color: Colors.white),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const FavoritesScreen()))),
          IconButton(
              icon: const Icon(Icons.settings_outlined, color: Colors.white),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()))),
        ],
      ),
      const SliverToBoxAdapter(
          child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: SmartBannerAdWidget()))),
      _sectionHeader(context, 'New', 'New'),
      _horizontalList(context, 'New'),
      _sectionHeader(context, 'Sport', 'Sport'),
      _horizontalList(context, 'Sport'),
      _sectionHeader(context, 'Anime', 'Anime'),
      _horizontalList(context, 'Anime'),
      _sectionHeader(context, '16:9', '16:9'),
      _horizontalList(context, '16:9'),
      _sectionHeader(context, 'Best', 'Best'),
      _horizontalList(context, 'Best'),
      const SliverToBoxAdapter(
          child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: SmartBannerAdWidget()))),
      ...MockData.categories.map((cat) => _categoryRow(context, cat)),
      const SliverToBoxAdapter(child: SizedBox(height: 100)),
    ]);
  }

  SliverToBoxAdapter _sectionHeader(
      BuildContext context, String title, String category) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Container(
                width: 4,
                height: 24,
                decoration: BoxDecoration(
                    color: Colors.blueAccent,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            Text(title,
                style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            if (title == '16:9') ...[
              const SizedBox(width: 8),
              Icon(Icons.aspect_ratio, color: Colors.blueAccent, size: 20)
            ]
          ]),
          GestureDetector(
              onTap: () => _navigateTo(context, category),
              child: const Text('See All →',
                  style: TextStyle(
                      color: Colors.blueAccent,
                      fontWeight: FontWeight.w600,
                      fontSize: 14))),
        ]),
      ),
    );
  }

  SliverToBoxAdapter _horizontalList(BuildContext context, String category) {
    final is169 = category == '16:9' || category == '16:9 Ratio';
    final cardWidth = is169 ? 285.0 : 150.0;
    final cardHeight = is169 ? 160.0 : 250.0;
    return SliverToBoxAdapter(
      child: FutureBuilder<List<WallpaperModel>>(
        future: GitHubService.getWallpapers(category),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting)
            return SizedBox(
                height: cardHeight,
                child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: 5,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, __) => SizedBox(
                        width: cardWidth, child: const ShimmerLoadingCard())));
          if (!snapshot.hasData || snapshot.data!.isEmpty)
            return SizedBox(height: cardHeight);
          final wallpapers = snapshot.data!;
          final baseCount = wallpapers.length > 12 ? 12 : wallpapers.length;
          final totalCount = baseCount + (baseCount ~/ 5);
          return SizedBox(
            height: cardHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: totalCount,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, displayIndex) {
                const int adInterval = 6;
                int imageIndex = displayIndex - (displayIndex ~/ adInterval);
                if (displayIndex % adInterval == 5)
                  return _adCard(cardWidth, cardHeight);
                if (imageIndex >= baseCount) return const SizedBox.shrink();
                final heroTag =
                    'wp_${wallpapers[imageIndex].id}_${category}_$imageIndex';
                return WallpaperCard(
                  wallpaper: wallpapers[imageIndex],
                  heroTag: heroTag,
                  width: cardWidth,
                  height: cardHeight,
                  onTap: () {
                    AdMobManager().trackWallpaperView(
                      onAdComplete: () {
                        Navigator.push(
                            context,
                            PageRouteBuilder(
                                pageBuilder: (_, anim, __) => FadeTransition(
                                    opacity: anim,
                                    child: PreviewScreen(
                                        wallpaper: wallpapers[imageIndex],
                                        heroTag: heroTag,
                                        wallpapers: wallpapers,
                                        initialIndex: imageIndex)),
                                transitionDuration:
                                    const Duration(milliseconds: 300)));
                      },
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _adCard(double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: Colors.blueAccent.withValues(alpha: 0.3), width: 1)),
      child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(fit: StackFit.expand, children: [
            Container(
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                  Colors.blueAccent.withValues(alpha: 0.1),
                  Colors.cyanAccent.withValues(alpha: 0.05)
                ]))),
            Center(
                child: SizedBox(
                    width: width * 0.9,
                    height: height * 0.8,
                    child: const BannerAdWidget(adSize: AdSize.banner))),
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25))),
                child: Text('إعلان',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ])),
    );
  }

  SliverToBoxAdapter _categoryRow(BuildContext context, CategoryModel cat) {
    return SliverToBoxAdapter(
      child: GestureDetector(
        onTap: () => _navigateTo(context, cat.name),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: FutureBuilder<List<WallpaperModel>>(
            future: GitHubService.getWallpapers(cat.name),
            builder: (context, snapshot) {
              return Container(
                height: 90,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.white.withValues(alpha: 0.05)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(fit: StackFit.expand, children: [
                    if (snapshot.hasData && snapshot.data!.isNotEmpty)
                      CachedNetworkImage(
                          imageUrl: snapshot.data![0].thumbnailUrl,
                          fit: BoxFit.cover),
                    Container(
                        decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                      Colors.black.withValues(alpha: 0.75),
                      Colors.black.withValues(alpha: 0.3)
                    ]))),
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(children: [
                          Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                  color:
                                      cat.accentColor.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(12)),
                              child: Icon(cat.icon,
                                  color: cat.accentColor, size: 20)),
                          const SizedBox(width: 14),
                          Expanded(
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(cat.name,
                                    style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15)),
                                if (snapshot.hasData)
                                  Text('${snapshot.data!.length} صورة',
                                      style: GoogleFonts.poppins(
                                          color: Colors.grey[400],
                                          fontSize: 11))
                              ])),
                          const Icon(Icons.chevron_right, color: Colors.white70)
                        ])),
                  ]),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// 12. OTHER SCREENS
// =============================================================================
class NewScreen extends StatelessWidget {
  const NewScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text('New',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                  color: Colors.white))),
      body: const _WallpaperGridLoader(categoryName: 'New'));
}

class BestScreen extends StatelessWidget {
  const BestScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text('Best',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                  color: Colors.white))),
      body: const _WallpaperGridLoader(categoryName: 'Best'));
}

class Screen169 extends StatelessWidget {
  const Screen169({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Row(children: [
            Text('16:9 ',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                    color: Colors.white)),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: Colors.cyan.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.cyan.withValues(alpha: 0.5))),
                child: Text('Landscape',
                    style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Colors.cyan,
                        fontWeight: FontWeight.w600)))
          ])),
      body:
          const _WallpaperGridLoader(categoryName: '16:9', isLandscape: true));
}

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Consumer<FavoritesProvider>(
      builder: (context, favProvider, _) {
        return CustomScrollView(slivers: [
          SliverAppBar(
              floating: true,
              backgroundColor: Colors.transparent,
              title: Text('Favorites',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                      color: Colors.white)),
              actions: [
                if (favProvider.favorites.isNotEmpty)
                  IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _confirmClearAll(context, favProvider))
              ]),
          const SliverToBoxAdapter(child: Center(child: BannerAdWidget())),
          if (favProvider.favorites.isEmpty)
            SliverFillRemaining(
                child: Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                  Icon(Icons.favorite_border,
                      size: 80, color: Colors.grey[600]),
                  const SizedBox(height: 20),
                  Text('لا توجد مفضلات بعد',
                      style: GoogleFonts.poppins(
                          color: Colors.grey[400], fontSize: 18)),
                  const SizedBox(height: 8),
                  Text('اضغط ♥ على أي صورة لحفظها هنا',
                      style: GoogleFonts.poppins(
                          color: Colors.grey[600], fontSize: 13))
                ])))
          else
            SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.65,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final wallpaper = favProvider.favorites[index];
                      return WallpaperCard(
                          wallpaper: wallpaper,
                          heroTag: 'wp_${wallpaper.id}_favorites_$index',
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => PreviewScreen(
                                      wallpaper: wallpaper,
                                      heroTag:
                                          'wp_${wallpaper.id}_favorites_$index',
                                      wallpapers: favProvider.favorites,
                                      initialIndex: index))));
                    }, childCount: favProvider.favorites.length))),
        ]);
      },
    );
  }

  void _confirmClearAll(BuildContext context, FavoritesProvider provider) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2533),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('مسح المفضلة',
            style: GoogleFonts.poppins(color: Colors.white)),
        content: Text('هل تريد حذف كل المفضلات؟',
            style: GoogleFonts.poppins(color: Colors.grey[400])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('إلغاء',
                  style: GoogleFonts.poppins(color: Colors.grey[600]))),
          TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await provider.clearAll();
              },
              child: Text('مسح الكل',
                  style: GoogleFonts.poppins(color: Colors.red)))
        ],
      ),
    );
  }
}

class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return CustomScrollView(slivers: [
      SliverAppBar(
          floating: true,
          backgroundColor: Colors.transparent,
          title: Text('Catalog',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                  color: Colors.white))),
      const SliverToBoxAdapter(
          child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: SmartBannerAdWidget()))),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.78,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14),
          delegate: SliverChildBuilderDelegate((context, index) {
            final cat = MockData.categories[index];
            return GestureDetector(
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          CategoryWallpapersScreen(categoryName: cat.name))),
              child: FutureBuilder<List<WallpaperModel>>(
                future: GitHubService.getWallpapers(cat.name),
                builder: (context, snapshot) {
                  final firstUrl = snapshot.hasData && snapshot.data!.isNotEmpty
                      ? snapshot.data![0].thumbnailUrl
                      : null;
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(fit: StackFit.expand, children: [
                      firstUrl != null
                          ? CachedNetworkImage(
                              imageUrl: firstUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) =>
                                  const ShimmerLoadingCard())
                          : Container(
                              color: Colors.grey[850],
                              child: Icon(cat.icon,
                                  color: Colors.grey[600], size: 40)),
                      Container(
                          decoration: BoxDecoration(
                              gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.85)
                          ]))),
                      Positioned(
                          bottom: 14,
                          left: 12,
                          right: 12,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Icon(cat.icon,
                                      color: cat.accentColor, size: 16),
                                  const SizedBox(width: 6),
                                  Expanded(
                                      child: Text(cat.name,
                                          style: GoogleFonts.poppins(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14),
                                          overflow: TextOverflow.ellipsis))
                                ]),
                                if (snapshot.hasData)
                                  Text('${snapshot.data!.length} صورة',
                                      style: GoogleFonts.poppins(
                                          color: Colors.grey[400],
                                          fontSize: 11))
                              ])),
                    ]),
                  );
                },
              ),
            );
          }, childCount: MockData.categories.length),
        ),
      ),
    ]);
  }
}

// =============================================================================
// 13. SETTINGS SCREEN
// =============================================================================
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final favCount = context.watch<FavoritesProvider>().favorites.length;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new,
                  color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context)),
          title: Text('الإعدادات',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold, color: Colors.white))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Center(child: BannerAdWidget()),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3))),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.monetization_on,
                      color: Colors.amber, size: 20)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('اربح العملات',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                    Text('شاهد إعلاناً لكسب 5 عملات 🪙',
                        style: GoogleFonts.poppins(
                            color: Colors.grey[400], fontSize: 12))
                  ])),
            ]),
            const SizedBox(height: 12),
            Consumer<CoinsProvider>(
              builder: (context, coins, _) => Row(children: [
                Text('رصيدك الحالي: ',
                    style: GoogleFonts.poppins(
                        color: Colors.grey[300], fontSize: 13)),
                Text('${coins.coins} 🪙',
                    style: GoogleFonts.poppins(
                        color: Colors.amber,
                        fontSize: 16,
                        fontWeight: FontWeight.bold))
              ]),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => watchAdForCoins(context),
                icon: const Icon(Icons.play_circle_outline, size: 18),
                label: Text('شاهد إعلاناً (+5 🪙)',
                    style: GoogleFonts.poppins(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        _SettingsTile(
            icon: Icons.delete_sweep,
            iconColor: Colors.orange,
            title: 'مسح الكاش',
            subtitle: 'تحرير الذاكرة من الصور المؤقتة',
            onTap: () {
              GitHubService.clearCache();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('تم مسح الكاش ✅', style: GoogleFonts.poppins()),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  backgroundColor: Colors.green[700]));
            }),
        const SizedBox(height: 12),
        _SettingsTile(
            icon: Icons.network_check,
            iconColor: Colors.green,
            title: 'اختبار الاتصال بـ GitHub',
            subtitle: 'التحقق من حالة الاتصال',
            onTap: () async {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content:
                      Text('⏳ جاري الاختبار...', style: GoogleFonts.poppins()),
                  behavior: SnackBarBehavior.floating));
              final ok = await GitHubService.testConnection();
              if (context.mounted)
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok ? '✅ الاتصال ناجح' : '❌ فشل الاتصال',
                        style: GoogleFonts.poppins()),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: ok ? Colors.green[700] : Colors.red[700],
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))));
            }),
        const SizedBox(height: 12),
        _SettingsTile(
            icon: Icons.favorite,
            iconColor: Colors.red,
            title: 'المفضلة',
            subtitle: '$favCount صورة محفوظة',
            trailing: favCount > 0
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12)),
                    child: Text('$favCount',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)))
                : null,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const FavoritesScreen()))),
        const SizedBox(height: 12),
        _SettingsTile(
            icon: Icons.security,
            iconColor: Colors.teal,
            title: 'أذونات التطبيق',
            subtitle: 'إدارة أذونات الصور والتخزين',
            onTap: () async {
              final isGranted = await GalleryPermission.isGranted();
              if (context.mounted) {
                if (isGranted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('✅ الأذونات ممنوحة',
                          style: GoogleFonts.poppins()),
                      backgroundColor: Colors.green[700],
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))));
                } else {
                  openAppSettings();
                }
              }
            }),
        const SizedBox(height: 12),
        _SettingsTile(
            icon: Icons.privacy_tip_outlined,
            iconColor: Colors.blueAccent,
            title: 'سياسة الخصوصية',
            subtitle: 'اقرأ سياسة الخصوصية الخاصة بالتطبيق',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const PrivacyPolicyScreen()))),
        const SizedBox(height: 12),
        _SettingsTile(
            icon: Icons.info_outline,
            iconColor: Colors.cyan,
            title: 'عن التطبيق',
            subtitle: 'KASEM 2026',
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: const Color(0xFF1A2533),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  title: Text('4K خلفيات',
                      style: GoogleFonts.poppins(
                          color: Colors.white, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.blue.withValues(alpha: 0.4),
                                  blurRadius: 20)
                            ]),
                        child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Image.asset('assets/icon.png',
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                    color: Colors.blueAccent,
                                    child: const Icon(Icons.wallpaper,
                                        color: Colors.white, size: 40))))),
                    const SizedBox(height: 16),
                    Text('الإصدار 1.1',
                        style: GoogleFonts.poppins(
                            color: Colors.grey[400], fontSize: 13)),
                    const SizedBox(height: 4),
                    Text('تطبيق خلفيات عالي الجودة',
                        style: GoogleFonts.poppins(
                            color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text('KASEM 2026',
                        style: GoogleFonts.poppins(
                            color: Colors.grey[500], fontSize: 12))
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('إغلاق',
                            style:
                                GoogleFonts.poppins(color: Colors.blueAccent)))
                  ],
                ),
              );
            }),
      ]),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  const _SettingsTile(
      {required this.icon,
      required this.iconColor,
      required this.title,
      required this.subtitle,
      required this.onTap,
      this.trailing});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.12))),
            child: Row(children: [
              Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: iconColor, size: 22)),
              const SizedBox(width: 16),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(title,
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                    Text(subtitle,
                        style: GoogleFonts.poppins(
                            color: Colors.grey[400], fontSize: 12))
                  ])),
              if (trailing != null) ...[trailing!, const SizedBox(width: 6)],
              const Icon(Icons.chevron_right, color: Colors.grey)
            ]),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// 14. DATA
// =============================================================================
class MockData {
  static List<CategoryModel> get categories => const [
        CategoryModel(
            name: 'All Images',
            repository: 'All-images',
            icon: Icons.photo_library,
            accentColor: Colors.blueAccent),
        CategoryModel(
            name: 'Anime',
            repository: 'anime_wallpapers',
            icon: Icons.auto_awesome,
            accentColor: Colors.orange),
        CategoryModel(
            name: 'Sport',
            repository: 'Sport',
            icon: Icons.sports,
            accentColor: Colors.green),
        CategoryModel(
            name: 'Cars',
            repository: 'cars',
            icon: Icons.directions_car,
            accentColor: Colors.red),
        CategoryModel(
            name: 'Nature',
            repository: 'nature',
            icon: Icons.nature,
            accentColor: Colors.green),
        CategoryModel(
            name: 'Space',
            repository: 'space',
            icon: Icons.rocket,
            accentColor: Colors.purple),
        CategoryModel(
            name: '16:9 Ratio',
            repository: 'imag-16-9',
            icon: Icons.crop_landscape,
            accentColor: Colors.cyan),
      ];
}

// =============================================================================
// 15. BOTTOM NAV
// =============================================================================
class CustomBottomNav extends StatelessWidget {
  const CustomBottomNav({super.key});
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 12, right: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(30),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.15))),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _NavItem(
                      icon: Icons.home_rounded,
                      label: 'Main',
                      index: 0,
                      provider: provider),
                  _NavItem(
                      icon: Icons.fiber_new_rounded,
                      label: 'New',
                      index: 1,
                      provider: provider),
                  _NavItem(
                      icon: Icons.star_rounded,
                      label: 'Best',
                      index: 2,
                      provider: provider),
                  _NavItem(
                      icon: Icons.crop_landscape_rounded,
                      label: '16:9',
                      index: 3,
                      provider: provider),
                  _NavItem(
                      icon: Icons.grid_view_rounded,
                      label: 'Catalog',
                      index: 4,
                      provider: provider),
                ]),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final AppProvider provider;
  const _NavItem(
      {required this.icon,
      required this.label,
      required this.index,
      required this.provider});

  @override
  Widget build(BuildContext context) {
    final isSelected = provider.currentIndex == index;
    return GestureDetector(
      onTap: () => provider.changeTab(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: isSelected
                ? Colors.blueAccent.withValues(alpha: 0.22)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              color: isSelected ? Colors.blueAccent : Colors.grey, size: 22),
          const SizedBox(height: 3),
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 9,
                  color: isSelected ? Colors.blueAccent : Colors.grey,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal))
        ]),
      ),
    );
  }
}

// =============================================================================
// 16. MAIN LAYOUT
// =============================================================================
class MainLayout extends StatefulWidget {
  const MainLayout({super.key});
  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _checkPrivacyThenPermissions());
  }

  void _checkPrivacyThenPermissions() {
    final privacyProvider = context.read<PrivacyProvider>();
    if (!privacyProvider.accepted) {
      showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const PrivacyPolicyDialog()).then((_) async {
        if (!mounted) return;
        await PermissionsInitializer.requestOnFirstLaunch(context);
        if (!mounted) return;
        if (Platform.isAndroid) {
          await NotificationService.requestPermissionAndSubscribe();
        }
      });
    } else {
      PermissionsInitializer.requestOnFirstLaunch(context).then((_) async {
        if (!mounted) return;
        if (Platform.isAndroid) {
          await NotificationService.requestPermissionAndSubscribe();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final screens = [
      const HomeScreen(),
      const NewScreen(),
      const BestScreen(),
      const Screen169(),
      const CatalogScreen()
    ];
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Stack(children: [
        Positioned.fill(
            child: Container(
                decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
              Color(0xFF0F0F1A),
              Color(0xFF0F2027),
              Color(0xFF1A1A2E)
            ])))),
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            switchInCurve: Curves.easeInOutCubic,
            switchOutCurve: Curves.easeInOutCubic,
            child: KeyedSubtree(
                key: ValueKey(provider.currentIndex),
                child: screens[provider.currentIndex]),
          ),
        ),
        const Positioned(
            bottom: 0, left: 0, right: 0, child: CustomBottomNav()),
      ]),
    );
  }
}

// =============================================================================
// 17. APP & MAIN
// =============================================================================
class WallpaperApp extends StatelessWidget {
  const WallpaperApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '4K خلفيات',
      navigatorKey: NotificationService.navigatorKey,
      theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: Colors.transparent,
          primaryColor: Colors.blueAccent,
          colorScheme: const ColorScheme.dark(primary: Colors.blueAccent)),
      home: const SplashScreen(),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Firebase مُعطّل تماماً على iOS لهذه النسخة (خطوة تشخيصية) - يعمل على أندرويد فقط
  if (Platform.isAndroid) {
    try {
      await Firebase.initializeApp();
      AppLogger.success('✅ Firebase initialized successfully');
    } catch (e) {
      AppLogger.error('❌ Firebase initialization failed: $e');
    }
  } else {
    AppLogger.info('ℹ️ Firebase disabled on iOS for this build');
  }

  // ✅ خدمة الإشعارات مبنية على Firebase Messaging - تعمل على أندرويد فقط بنفس السبب
  if (Platform.isAndroid) {
    try {
      await NotificationService.initialize();
      AppLogger.success('✅ Notification service initialized');
    } catch (e) {
      AppLogger.error('❌ Notification service failed: $e');
    }
  }

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light));

  try {
    await AdMobManager().initialize();
  } catch (e) {
    AppLogger.error('AdMob initialization failed: $e');
  }

  final favProvider = FavoritesProvider();
  final privacyProvider = PrivacyProvider();
  final coinsProvider = CoinsProvider();

  await Future.wait(
      [favProvider.load(), privacyProvider.load(), coinsProvider.load()]);

  await coinsProvider.giveWelcomeBonus();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppProvider()),
        ChangeNotifierProvider.value(value: favProvider),
        ChangeNotifierProvider.value(value: privacyProvider),
        ChangeNotifierProvider.value(value: coinsProvider),
      ],
      child: const WallpaperApp(),
    ),
  );
}
