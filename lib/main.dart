import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
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

// 🔐 لوحة تحكم المشرف (ملف مستقل بجانب main.dart)
import 'admin_panel.dart';

class AppFonts {
  static TextStyle poppins({
    Color? color,
    Color? backgroundColor,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? wordSpacing,
    TextBaseline? textBaseline,
    double? height,
    Locale? locale,
    Paint? foreground,
    Paint? background,
    List<Shadow>? shadows,
    List<FontFeature>? fontFeatures,
    TextDecoration? decoration,
    Color? decorationColor,
    TextDecorationStyle? decorationStyle,
    double? decorationThickness,
  }) {
    return TextStyle(
      fontFamily: 'Poppins',
      color: color,
      backgroundColor: backgroundColor,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      textBaseline: textBaseline,
      height: height,
      locale: locale,
      foreground: foreground,
      background: background,
      shadows: shadows,
      fontFeatures: fontFeatures,
      decoration: decoration,
      decorationColor: decorationColor,
      decorationStyle: decorationStyle,
      decorationThickness: decorationThickness,
    );
  }
}

// =============================================================================
// 📝 App Logger
// =============================================================================
class AppLogger {
  static void info(String msg) => debugPrint('ℹ️  $msg');
  static void success(String msg) => debugPrint('✅ $msg');
  static void warning(String msg) => debugPrint('⚠️  $msg');
  static void error(String msg) => debugPrint('❌ $msg');
}

// =============================================================================
// 🔔 NOTIFICATION SERVICE — خدمة الإشعارات
// =============================================================================

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  AppLogger.info('Handling a background message: ${message.messageId}');
}

class NotificationService {
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static Future<void> initialize() async {
    try {
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);

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

      FirebaseMessaging.onMessageOpenedApp
          .listen(_handleNotificationNavigation);

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
      final data = message.data;

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
        AppLogger.info('📸 Opening wallpaper: ${data['wallpaper_id']}');
      }
    } catch (e) {
      AppLogger.error('❌ Error in _handleNotificationNavigation: $e');
    }
  }

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
        AppLogger.warning('⚠️ User declined notification permissions: '
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
// 🔐 GALLERY PERMISSION HELPER
// =============================================================================

enum GalleryPermissionResult { granted, denied, permanentlyDenied }

class GalleryPermission {
  static int? _cachedSdkInt;

  static Future<bool> isGranted() async {
    if (Platform.isIOS) {
      final status = await Permission.photos.status;
      return status.isGranted || status.isLimited;
    }
    final sdkInt = await _androidSdkInt();
    if (sdkInt >= 33) {
      return (await Permission.photos.status).isGranted;
    }
    if (sdkInt >= 29) return true; // Scoped Storage
    return (await Permission.storage.status).isGranted;
  }

  static Future<GalleryPermissionResult> requestOnce() async {
    if (Platform.isIOS) {
      final status = await Permission.photos.request();
      if (status.isGranted || status.isLimited) {
        return GalleryPermissionResult.granted;
      }
      return status.isPermanentlyDenied
          ? GalleryPermissionResult.permanentlyDenied
          : GalleryPermissionResult.denied;
    }
    final sdkInt = await _androidSdkInt();
    if (sdkInt >= 29 && sdkInt < 33) {
      return GalleryPermissionResult.granted;
    }
    final permission = sdkInt >= 33 ? Permission.photos : Permission.storage;

    if (await permission.status.isPermanentlyDenied) {
      return GalleryPermissionResult.permanentlyDenied;
    }

    final status = await permission.request();
    if (status.isGranted) return GalleryPermissionResult.granted;
    return status.isPermanentlyDenied
        ? GalleryPermissionResult.permanentlyDenied
        : GalleryPermissionResult.denied;
  }

  static Future<bool> request() async {
    final result = await requestOnce();
    return result == GalleryPermissionResult.granted;
  }

  static Future<bool> isPermanentlyDenied() async {
    if (Platform.isIOS) {
      return (await Permission.photos.status).isPermanentlyDenied;
    }
    final sdkInt = await _androidSdkInt();
    if (sdkInt >= 33) {
      return (await Permission.photos.status).isPermanentlyDenied;
    }
    if (sdkInt >= 29) return false;
    return (await Permission.storage.status).isPermanentlyDenied;
  }

  // ✅ تحسين: قراءة نسخة أندرويد مرة واحدة فقط وتخزينها (كانت تُقرأ في كل نداء)
  static Future<int> _androidSdkInt() async {
    if (_cachedSdkInt != null) return _cachedSdkInt!;
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    _cachedSdkInt = androidInfo.version.sdkInt;
    return _cachedSdkInt!;
  }
}

// =============================================================================
// 0. ADMOB SERVICE
// =============================================================================
class AdMobIds {
  static String get bannerAdUnitId {
    if (Platform.isAndroid) return 'ca-app-pub-4756404048214956/3103410719';
    return 'ca-app-pub-3940256099942544/2934735716';
  }

  static String get interstitialAdUnitId {
    if (Platform.isAndroid) return 'ca-app-pub-4756404048214956/7589450639';
    return 'ca-app-pub-3940256099942544/1033173712';
  }

  static String get rewardedAdUnitId {
    if (Platform.isAndroid) return 'ca-app-pub-4756404048214956/8168076692';
    return 'ca-app-pub-3940256099942544/5224354917';
  }

  static String get nativeAdUnitId {
    if (Platform.isAndroid) return 'ca-app-pub-4756404048214956/2620236541';
    return 'ca-app-pub-3940256099942544/2247696110';
  }

  static String get appOpenAdUnitId {
    if (Platform.isAndroid) return 'ca-app-pub-4756404048214956/7070617440';
    return 'ca-app-pub-3940256099942544/3419835294';
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
  bool _initialized = false;
  DateTime? _appOpenLoadTime;
  int _viewCount = 0;
  static const int _interstitialInterval = 5;
  static const String _viewCountKey = 'admob_wallpaper_view_count';

  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;
    await MobileAds.instance.initialize();
    _initialized = true;
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

  void _loadInterstitialAd() {
    if (!_initialized) return;
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
          if (_interstitialLoadAttempts < _maxFailedLoadAttempts) {
            _loadInterstitialAd();
          }
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
    if (!_initialized) return;
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
          if (_rewardedLoadAttempts < _maxFailedLoadAttempts) {
            _loadRewardedAd();
          }
        },
      ),
    );
  }

  /// ✅ إصلاح: كان يخرج بصمت إذا لم يكن الإعلان جاهزاً فلا يحدث شيء للمستخدم.
  /// الآن يُبلّغ عبر onAdNotReady ويعيد المحاولة في الخلفية.
  void showRewardedAd({
    required Function(AdWithoutView, RewardItem) onUserEarnedReward,
    VoidCallback? onAdDismissed,
    VoidCallback? onAdNotReady,
  }) {
    if (_rewardedAd == null) {
      _rewardedLoadAttempts = 0;
      _loadRewardedAd();
      onAdNotReady?.call();
      return;
    }
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
        onAdNotReady?.call();
      },
    );
    _rewardedAd!.show(onUserEarnedReward: onUserEarnedReward);
  }

  bool get isRewardedAdReady => _rewardedAd != null;

  void _loadAppOpenAd() {
    if (!_initialized) return;
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
      return DateTime.now().difference(_appOpenLoadTime!).inHours < 4;
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

// ─── Banner Ad Widget ────────────────────────────────────────────────────────
// ✅ إصلاح: كان يُحمَّل مرتين (initState + didChangeDependencies) لكل بانر.
// الآن التحميل من didChangeDependencies فقط، مع حارس تخلّص عند إلغاء الودجت.
class ResponsiveBannerAdWidget extends StatefulWidget {
  final EdgeInsetsGeometry padding;
  const ResponsiveBannerAdWidget(
      {super.key,
      this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8)});

  @override
  State<ResponsiveBannerAdWidget> createState() =>
      _ResponsiveBannerAdWidgetState();
}

class _ResponsiveBannerAdWidgetState extends State<ResponsiveBannerAdWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  double? _lastWidth;
  Orientation? _lastOrientation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    final width = media.size.width;
    if (_lastWidth == width && _lastOrientation == media.orientation) return;
    _lastWidth = width;
    _lastOrientation = media.orientation;
    _loadAd(width.truncate(), media.orientation);
  }

  Future<void> _loadAd(int screenWidth, Orientation orientation) async {
    _bannerAd?.dispose();
    _bannerAd = null;
    if (!mounted) return;
    setState(() => _isLoaded = false);

    // إذا لم تكتمل تهيئة AdMob بعد (شبكة بطيئة) ننتظر قليلاً ثم نحاول مرة أخرى
    if (!AdMobManager().isInitialized) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted || !AdMobManager().isInitialized) return;
    }

    final size = await AdSize.getAnchoredAdaptiveBannerAdSize(
      orientation,
      screenWidth,
    );
    if (!mounted) return;

    final ad = BannerAd(
      adUnitId: AdMobIds.bannerAdUnitId,
      size: size ?? AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) setState(() => _isLoaded = false);
        },
      ),
    );
    _bannerAd = ad;
    await ad.load();
    // إذا أُلغيت الشاشة أثناء التحميل نتخلص من الإعلان فوراً (منع تسريب ذاكرة)
    if (!mounted) {
      ad.dispose();
      _bannerAd = null;
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _bannerAd == null) return const SizedBox.shrink();
    return Padding(
      padding: widget.padding,
      child: Center(
        child: SizedBox(
          width: _bannerAd!.size.width.toDouble(),
          height: _bannerAd!.size.height.toDouble(),
          child: AdWidget(ad: _bannerAd!),
        ),
      ),
    );
  }
}

class BannerAdWidget extends ResponsiveBannerAdWidget {
  const BannerAdWidget({super.key, super.padding});
}

class SmartBannerAdWidget extends ResponsiveBannerAdWidget {
  const SmartBannerAdWidget({super.key, super.padding});
}

// =============================================================================
// 1. MODELS
// =============================================================================
class WallpaperModel {
  final String id;
  final String title;

  /// الرابط الأساسي (jsDelivr CDN) — المسار المعتمد للعرض والتحميل
  final String imageUrl;

  /// ✅ رابط احتياطي مستقل (raw.githubusercontent) يُجرَّب تلقائياً إذا فشل
  /// أو تعلّق الرابط الأساسي. وجود مسارين مختلفين تماماً يضمن ظهور الصورة
  /// حتى لو حُجب أحد النطاقين على شبكة المستخدم.
  final String fallbackUrl;

  final String category;
  final String repository;
  final int width;
  final int height;
  final DateTime uploadedAt;

  const WallpaperModel({
    required this.id,
    required this.title,
    required this.imageUrl,
    this.fallbackUrl = '',
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
        'fallbackUrl': fallbackUrl,
        'category': category,
        'repository': repository,
        'width': width,
        'height': height,
        'uploadedAt': uploadedAt.toIso8601String(),
      };

  factory WallpaperModel.fromJson(Map<String, dynamic> json) => WallpaperModel(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        imageUrl: json['imageUrl'] as String? ?? '',
        fallbackUrl: json['fallbackUrl'] as String? ?? '',
        category: json['category'] as String? ?? '',
        repository: json['repository'] as String? ?? '',
        width: json['width'] as int? ?? 1080,
        height: json['height'] as int? ?? 1920,
        uploadedAt: DateTime.tryParse(json['uploadedAt'] as String? ?? '') ??
            DateTime.now(),
      );

  bool get isLandscape => width > height;

  /// ✅ يُحسب وقت العرض لا وقت الإنشاء: لو تبيّن أن وسيط الضغط غير متاح على
  /// شبكة المستخدم يعود تلقائياً للرابط الأصلي بلا حاجة لإعادة جلب أي شيء،
  /// كما أن المفضلة المحفوظة لا تعلق على رابط وسيط قديم.
  String get thumbnailUrl =>
      GitHubService.thumbUrl(imageUrl, width: isLandscape ? 700 : 400);
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
// -----------------------------------------------------------------------------
// ✅ تعديلات الأداء في هذه النسخة:
// 1) الكاش صار على مستوى «المستودع» لا «القسم»: New و Best و All Images تشترك
//    في نفس المستودع All-images، فكانت تُطلب 3 مرات — الآن مرة واحدة.
// 2) منع الطلبات المتزامنة المكررة (_inFlight): عند فتح الرئيسية تُطلب عدة
//    أقسام في نفس اللحظة، وبعضها لنفس المستودع.
// 3) مصغّرات مضغوطة عبر wsrv.nl بدل تحميل صور 4K كاملة في الشبكة/القوائم
//    (أكبر تحسين منفرد للسرعة والبيانات). أوقفه بجعل _useThumbProxy = false.
// 4) كاش مستقبلات الواجهة (futureOf) لمنع إعادة الطلب مع كل إعادة بناء.
// =============================================================================
class GitHubService {
  static const String _owner = 'pcbalad2020-coder';
  static const String _branch = 'main';
  static const String _token =
      String.fromEnvironment('GITHUB_TOKEN', defaultValue: '');

  /// ⚠️ وسيط تصغير الصور (wsrv.nl) — مُعطَّل عمداً.
  /// ثبت عملياً أنه غير قابل للوصول من شبكة هذا التطبيق، وعند تفعيله كانت
  /// طلبات الصور «تتعلّق بلا رد» فتبقى الشاشة في وضع تحميل دائم.
  /// لا تفعّله إلا بعد التأكد من عمله فعلياً على الشبكة المستهدفة.
  static const bool _useThumbProxy = false;

  static const Map<String, String> repositories = {
    'All Images': 'All-images',
    'All-images': 'All-images',
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

  static String _normalizeCategoryKey(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  static String resolveRepositoryName(String categoryName) {
    if (categoryName.isEmpty) {
      AppLogger.warning('⚠️ Empty category name; falling back to All-images');
      return 'All-images';
    }

    final direct = repositories[categoryName];
    if (direct != null) return direct;

    final normalized = _normalizeCategoryKey(categoryName);
    for (final entry in repositories.entries) {
      if (_normalizeCategoryKey(entry.key) == normalized) {
        return entry.value;
      }
    }

    AppLogger.warning(
        '⚠️ Unknown category "$categoryName"; falling back to All-images');
    return 'All-images';
  }

  // كاش النماذج لكل قسم (رخيص — لا يسبب طلبات شبكة)
  static final Map<String, List<WallpaperModel>> _cache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};

  // كاش قوائم الملفات لكل مستودع (هذا هو ما يوفّر طلبات الشبكة فعلياً)
  static final Map<String, List<Map<String, dynamic>>> _fileCache = {};
  static final Map<String, DateTime> _fileCacheTimestamps = {};
  static final Map<String, Future<List<Map<String, dynamic>>>> _inFlight = {};

  // كاش مستقبلات الواجهة — يمنع إنشاء Future جديد داخل كل build
  static final Map<String, Future<List<WallpaperModel>>> _uiFutures = {};

  static const Duration _cacheDuration = Duration(hours: 6);

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://api.github.com',
    // ✅ مهلات قصيرة: الهدف اكتشاف الفشل بسرعة والانتقال للمصدر البديل،
    // لا انتظار 30 ثانية لكل مصدر (كان يجمّد بقية الأقسام في الطابور).
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 25),
    headers: {
      'Accept': 'application/vnd.github.v3+json',
      'User-Agent': 'KM2-Wallpaper-App/1.3.0',
      if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
    },
  ));

  static final Dio _jsDelivrDio = Dio(BaseOptions(
    baseUrl: 'https://data.jsdelivr.com',
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 25),
    headers: {
      'Accept': 'application/json',
      'User-Agent': 'KM2-Wallpaper-App/1.3.0',
    },
  ));

  /// ✅ رابط الصورة عبر jsDelivr CDN — هذا هو المسار المعتمد للصور.
  static String _toJsDelivr({
    required String owner,
    required String repo,
    required String branch,
    required String path,
  }) {
    final encodedPath = path.split('/').map(Uri.encodeComponent).join('/');
    return 'https://cdn.jsdelivr.net/gh/$owner/$repo@$branch/$encodedPath';
  }

  static String _toRawGithub({
    required String owner,
    required String repo,
    required String branch,
    required String path,
  }) {
    final encodedPath = path.split('/').map(Uri.encodeComponent).join('/');
    return 'https://raw.githubusercontent.com/$owner/$repo/$branch/$encodedPath';
  }

  /// ✅ رابط مصغّر مضغوط (webp) بعرض محدد — يقلّل حجم الصورة من عدة ميغابايت
  /// إلى عشرات الكيلوبايت في الشبكات والقوائم.
  /// نتيجة فحص الوسيط: يبدأ معطلاً ولا يُفعَّل إلا بعد نجاح فحص حقيقي.
  static bool _thumbProxyReady = false;
  static bool get isThumbProxyReady => _thumbProxyReady;

  /// ✅ يختبر الوسيط بصورة صغيرة جداً بمهلة 5 ثوانٍ. إن لم يستجب نبقى على
  /// الروابط الأصلية — هذا يمنع الحالة الأسوأ: طلب صورة «معلّق بلا خطأ»
  /// يترك الشاشة في وضع تحميل دائم لأن errorWidget لا يُستدعى أبداً.
  static Future<void> probeThumbProxy() async {
    if (!_useThumbProxy) {
      AppLogger.info('🖼️ Thumb proxy disabled by config');
      return;
    }
    try {
      final probeDio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        responseType: ResponseType.bytes,
      ));
      const sample =
          'https://raw.githubusercontent.com/$_owner/nature/$_branch/1.jpg';
      final res = await probeDio.get(
        'https://wsrv.nl/?url=${Uri.encodeComponent(sample)}&w=32&output=webp&q=40',
      );
      final bytes = res.data as List?;
      _thumbProxyReady = res.statusCode == 200 && (bytes?.isNotEmpty ?? false);
      AppLogger.success(_thumbProxyReady
          ? '🖼️ Thumb proxy OK — سيتم عرض مصغّرات مضغوطة'
          : '🖼️ Thumb proxy unavailable — استخدام الروابط الأصلية');
    } catch (e) {
      _thumbProxyReady = false;
      AppLogger.warning('🖼️ Thumb proxy probe failed: $e — using direct URLs');
    }
  }

  static String thumbUrl(String url, {int width = 400}) {
    if (!_useThumbProxy || !_thumbProxyReady || url.isEmpty) return url;
    // maxage=1y يبقي النسخة المصغّرة على شبكة الوسيط فيكون الطلب التالي
    // لأي مستخدم فورياً. we = لا تكبّر الصور الأصغر من العرض المطلوب.
    return 'https://wsrv.nl/?url=${Uri.encodeComponent(url)}'
        '&w=$width&output=webp&q=72&we&maxage=1y';
  }

  /// عميل مخصص لجلب ملف القائمة الثابت من raw.githubusercontent
  static final Dio _rawDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 25),
    headers: {'User-Agent': 'KM2-Wallpaper-App/1.3.0'},
  ));

  /// ✅ المصدر الأول والأفضل: ملف `files.json` موضوع داخل كل مستودع ويحوي
  /// أسماء الصور. مزاياه أنه:
  ///  • بلا أي حد استخدام (ليس API بل ملف عادي) → لا خطأ 403 أبداً
  ///  • بلا حد حجم المستودع → يعمل مع All-images و imag-16-9 اللذين يرفضهما
  ///    jsDelivr لتجاوزهما 50 ميجابايت (وهذا سبب فراغ قسمي New/Best/16:9)
  ///  • طلب واحد صغير جداً (بضعة كيلوبايت) → أسرع مصدر على الإطلاق
  /// إن لم يوجد الملف في مستودع ما، ينتقل الكود للمصادر التالية تلقائياً.
  static Future<List<Map<String, dynamic>>> _fetchViaManifest(
      String repoName) async {
    final url = _toRawGithub(
        owner: _owner, repo: repoName, branch: _branch, path: 'files.json');
    final response = await _rawDio.get(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    if (response.statusCode != 200 || response.data == null) return [];

    final decoded = jsonDecode(response.data.toString());
    final rawList = decoded is List
        ? decoded
        : (decoded is Map ? (decoded['files'] as List? ?? []) : const []);

    return rawList.map((e) => e.toString()).where((path) {
      final lower = path.toLowerCase();
      return lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.png') ||
          lower.endsWith('.webp');
    }).map((path) {
      final clean = path.startsWith('/') ? path.substring(1) : path;
      return {
        'name': clean.split('/').last,
        'download_url': _toJsDelivr(
            owner: _owner, repo: repoName, branch: _branch, path: clean),
        'raw_url': _toRawGithub(
            owner: _owner, repo: repoName, branch: _branch, path: clean),
        'type': 'file',
      };
    }).toList();
  }

  static Future<List<Map<String, dynamic>>> _fetchViaJsDelivr(
      String repoName) async {
    final response = await _jsDelivrDio.get(
      '/v1/packages/gh/$_owner/$repoName@$_branch',
      queryParameters: {'structure': 'flat'},
    );
    if (response.statusCode == 200 && response.data != null) {
      final files = response.data['files'] as List? ?? [];
      return files.where((f) {
        final name = (f['name'] as String).toLowerCase();
        return name.endsWith('.jpg') ||
            name.endsWith('.jpeg') ||
            name.endsWith('.png') ||
            name.endsWith('.webp');
      }).map((f) {
        var path = f['name'] as String;
        if (path.startsWith('/')) path = path.substring(1);
        final filename = path.split('/').last;
        return {
          'name': filename,
          'download_url': _toJsDelivr(
            owner: _owner,
            repo: repoName,
            branch: _branch,
            path: path,
          ),
          'raw_url': _toRawGithub(
            owner: _owner,
            repo: repoName,
            branch: _branch,
            path: path,
          ),
          'type': 'file',
        };
      }).toList();
    }
    return [];
  }

  /// ✅ مصدر إضافي لقائمة الملفات: نقطة jsDelivr «القديمة». تدعم أسماء
  /// الفروع مباشرة (@main) وتنجح أحياناً حين تفشل النقطة الحديثة، وبلا أي
  /// حد استخدام ولا مصادقة — وجودها يجعل GitHub API خطة أخيرة نادرة بدل
  /// أن يكون المنقذ الوحيد (وهو محدود بـ 60 طلب/ساعة لكل IP → خطأ 403).
  static Future<List<Map<String, dynamic>>> _fetchViaJsDelivrLegacy(
      String repoName) async {
    final response = await _jsDelivrDio.get(
      '/v1/package/gh/$_owner/$repoName@$_branch/flat',
    );
    if (response.statusCode == 200 && response.data != null) {
      final files = response.data['files'] as List? ?? [];
      return files.where((f) {
        final name = (f['name'] as String? ?? '').toLowerCase();
        return name.endsWith('.jpg') ||
            name.endsWith('.jpeg') ||
            name.endsWith('.png') ||
            name.endsWith('.webp');
      }).map((f) {
        var path = f['name'] as String;
        if (path.startsWith('/')) path = path.substring(1);
        final filename = path.split('/').last;
        return {
          'name': filename,
          'download_url': _toJsDelivr(
            owner: _owner,
            repo: repoName,
            branch: _branch,
            path: path,
          ),
          'raw_url': _toRawGithub(
            owner: _owner,
            repo: repoName,
            branch: _branch,
            path: path,
          ),
          'type': 'file',
        };
      }).toList();
    }
    return [];
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
          // ⚠️ الإصلاح الحاسم: كانت هذه الخطة البديلة تبني روابط raw فقط،
          // فأي مستودع فشلت قائمته عبر jsDelivr كانت صوره تأتي من نطاق آخر
          // قد يكون محجوباً → القسم يظهر فارغاً رغم نجاح قراءة القائمة.
          // الآن الرابط الأساسي jsDelivr دائماً، وraw احتياطي فقط.
          'download_url': _toJsDelivr(
            owner: _owner,
            repo: repoName,
            branch: _branch,
            path: path,
          ),
          'raw_url': _toRawGithub(
            owner: _owner,
            repo: repoName,
            branch: _branch,
            path: path,
          ),
          'type': 'file',
        };
      }).toList();
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> _fetchFromRepoContents(
      String repoName) async {
    final response = await _dio.get(
      '/repos/$_owner/$repoName/contents',
      queryParameters: {'ref': _branch, 'per_page': 100},
    );
    if (response.statusCode == 200 && response.data is List) {
      final data = response.data as List;
      return data.where((item) => item['type'] == 'file').where((item) {
        final name = (item['name'] as String).toLowerCase();
        return name.endsWith('.jpg') ||
            name.endsWith('.jpeg') ||
            name.endsWith('.png') ||
            name.endsWith('.webp');
      }).map((item) {
        final name = item['name'] as String;
        return {
          'name': name,
          'download_url': _toJsDelivr(
            owner: _owner,
            repo: repoName,
            branch: _branch,
            path: name,
          ),
          'raw_url': _toRawGithub(
            owner: _owner,
            repo: repoName,
            branch: _branch,
            path: name,
          ),
          'type': 'file',
        };
      }).toList();
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> _fetchFiles(String repoName) async {
    // المصدر الأول: ملف القائمة الثابت (إن وُجد) — الأسرع والأضمن
    try {
      final manifest = await _fetchViaManifest(repoName);
      if (manifest.isNotEmpty) {
        AppLogger.success(
            '✅ Manifest OK: $repoName (${manifest.length} files)');
        return manifest;
      }
    } catch (e) {
      AppLogger.info('ℹ️ No files.json in $repoName — using API sources');
    }

    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        AppLogger.info('📥 Fetching (jsDelivr) [$attempt/2]: $repoName');
        final files = await _fetchViaJsDelivr(repoName);
        if (files.isNotEmpty) {
          AppLogger.success('✅ jsDelivr OK: $repoName (${files.length} files)');
          return files;
        }
        AppLogger.warning('⚠️ jsDelivr returned empty for $repoName');
        break;
      } on DioException catch (e) {
        AppLogger.warning(
            '⚠️ jsDelivr failed for $repoName | type=${e.type} | status=${e.response?.statusCode}');
        // connectionError = فشل DNS/اتصال من الجهاز نفسه — تستحق محاولة ثانية
        final worthRetry = e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout;
        if (attempt == 1 && worthRetry) {
          await Future.delayed(const Duration(milliseconds: 900));
          continue;
        }
        break;
      } catch (e) {
        AppLogger.warning('⚠️ jsDelivr unexpected error for $repoName: $e');
        break;
      }
    }
    // مصدر ثانٍ: نقطة jsDelivr القديمة — بلا حد استخدام، تُجرَّب قبل GitHub
    try {
      final legacy = await _fetchViaJsDelivrLegacy(repoName);
      if (legacy.isNotEmpty) {
        AppLogger.success(
            '✅ jsDelivr legacy OK: $repoName (${legacy.length} files)');
        return legacy;
      }
      AppLogger.warning('⚠️ jsDelivr legacy returned empty for $repoName');
    } on DioException catch (e) {
      AppLogger.warning(
          '⚠️ jsDelivr legacy failed for $repoName | type=${e.type} | status=${e.response?.statusCode}');
    } catch (e) {
      AppLogger.warning(
          '⚠️ jsDelivr legacy unexpected error for $repoName: $e');
    }

    AppLogger.info('↪️ Falling back to GitHub API for: $repoName');

    try {
      final files = await _fetchViaTrees(repoName);
      if (files.isNotEmpty) {
        AppLogger.success('✅ GitHub trees OK: $repoName (${files.length})');
        return files;
      }
      return await _fetchFromRepoContents(repoName);
    } on DioException catch (e) {
      AppLogger.warning(
          '⚠️ Trees API failed for $repoName | type=${e.type} | status=${e.response?.statusCode}');
      try {
        return await _fetchFromRepoContents(repoName);
      } catch (err) {
        AppLogger.error('❌ Contents API also failed for $repoName: $err');
        return [];
      }
    } catch (e) {
      AppLogger.error('❌ Unexpected error fetching $repoName: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> _getFilesWithFallback(
      String repoName) async {
    final files = await _getFiles(repoName);
    if (files.isNotEmpty || repoName == 'All-images') return files;

    AppLogger.warning(
        '⚠️ Repo "$repoName" returned no files; falling back to All-images');
    return _getFiles('All-images');
  }

  // ✅ حدّ أقصى 3 طلبات متزامنة: الرئيسية كانت تفتح 7 طلبات دفعة واحدة
  // (مستودع لكل قسم) فتفشل بعضها على الشبكات الضعيفة أو تتأخر جداً.
  static int _activeFetches = 0;
  static const int _maxConcurrentFetches = 4;
  static final List<Completer<void>> _fetchQueue = [];

  static Future<void> _acquireSlot() {
    if (_activeFetches < _maxConcurrentFetches) {
      _activeFetches++;
      return Future.value();
    }
    final completer = Completer<void>();
    _fetchQueue.add(completer);
    return completer.future;
  }

  static void _releaseSlot() {
    if (_fetchQueue.isNotEmpty) {
      _fetchQueue.removeAt(0).complete();
    } else if (_activeFetches > 0) {
      _activeFetches--;
    }
  }

  /// جلب قائمة ملفات المستودع مع كاش ومنع الطلبات المتزامنة المكررة
  static Future<List<Map<String, dynamic>>> _getFiles(String repoName) {
    final ts = _fileCacheTimestamps[repoName];
    if (ts != null &&
        DateTime.now().difference(ts) < _cacheDuration &&
        _fileCache[repoName] != null) {
      return Future.value(_fileCache[repoName]!);
    }
    final existing = _inFlight[repoName];
    if (existing != null) return existing;

    final future =
        _acquireSlot().then((_) => _fetchFiles(repoName)).then((files) {
      if (files.isNotEmpty) {
        _fileCache[repoName] = files;
        _fileCacheTimestamps[repoName] = DateTime.now();
      } else {
        AppLogger.warning('⚠️ No files returned for repo: $repoName');
      }
      return files;
    }).whenComplete(() {
      _releaseSlot();
      _inFlight.remove(repoName);
    });

    _inFlight[repoName] = future;
    return future;
  }

  static Future<List<WallpaperModel>> getWallpapers(String categoryName) async {
    final cachedAt = _cacheTimestamps[categoryName];
    if (cachedAt != null &&
        _cache[categoryName] != null &&
        DateTime.now().difference(cachedAt) < _cacheDuration) {
      return _cache[categoryName]!;
    }

    final repoName = resolveRepositoryName(categoryName);
    if (repoName.isEmpty) return [];

    final files = await _getFilesWithFallback(repoName);
    final is169 = categoryName == '16:9' || categoryName == '16:9 Ratio';
    final wallpapers = files.map((file) {
      final name = file['name'] as String? ?? 'unnamed';
      final jsDelivrUrl = file['download_url'] as String? ?? '';
      final rawUrl = file['raw_url'] as String? ?? '';
      // ✅ عكس الأولوية بناءً على قياس فعلي: روابط cdn.jsdelivr.net كانت
      // «تتعلّق بلا رد» على شبكة المستخدم (سطور ⌛ Image stalled في اللوج)
      // بينما raw.githubusercontent استجاب فوراً. لذا raw هو الأساسي الآن
      // و jsDelivr الاحتياطي — والعكس يحدث تلقائياً إن تعطّل raw يوماً.
      final primaryUrl = rawUrl.isNotEmpty ? rawUrl : jsDelivrUrl;
      final secondaryUrl = rawUrl.isNotEmpty ? jsDelivrUrl : '';
      return WallpaperModel(
        id: '${repoName}_$name',
        title: name.replaceAll(
            RegExp(r'\.(jpg|jpeg|png|webp)$', caseSensitive: false), ''),
        imageUrl: primaryUrl,
        fallbackUrl: secondaryUrl,
        category: categoryName,
        repository: repoName,
        width: is169 ? 1920 : 1080,
        height: is169 ? 1080 : 1920,
        uploadedAt: DateTime.now(),
      );
    }).toList()
      ..shuffle(Random());

    // ✅ لا نخزّن نتيجة فارغة: كان الفشل المؤقت (انقطاع لحظي عند الإقلاع)
    // يُخزَّن 6 ساعات فيبقى القسم فارغاً حتى لو عاد الإنترنت.
    if (wallpapers.isNotEmpty) {
      _cache[categoryName] = wallpapers;
      _cacheTimestamps[categoryName] = DateTime.now();
    }
    return wallpapers;
  }

  /// ✅ تُستخدم داخل build بدل getWallpapers مباشرة — نفس المستقبل يُعاد
  /// استخدامه فلا يحدث طلب/وميض جديد مع كل إعادة بناء للواجهة.
  static Future<List<WallpaperModel>> futureOf(String categoryName) {
    final existing = _uiFutures[categoryName];
    if (existing != null) return existing;

    // ✅ المستقبل يُحفظ فقط عند النجاح. لو رجع فارغاً أو رمى خطأ نحذفه فوراً
    // حتى تُعاد المحاولة تلقائياً في أول إعادة بناء أو سحب للتحديث.
    final future = getWallpapers(categoryName).then((list) {
      if (list.isEmpty) _uiFutures.remove(categoryName);
      return list;
    }).catchError((Object e) {
      AppLogger.error('❌ futureOf($categoryName) failed: $e');
      _uiFutures.remove(categoryName);
      return <WallpaperModel>[];
    });

    _uiFutures[categoryName] = future;
    return future;
  }

  static void clearCache() {
    _cache.clear();
    _cacheTimestamps.clear();
    _fileCache.clear();
    _fileCacheTimestamps.clear();
    _uiFutures.clear();
  }

  static Future<bool> testConnection() async {
    try {
      final response = await _jsDelivrDio.get(
        '/v1/packages/gh/$_owner/nature@$_branch',
        queryParameters: {'structure': 'flat'},
      );
      return response.statusCode == 200;
    } catch (e) {
      AppLogger.error('❌ testConnection failed: $e');
      return false;
    }
  }
}

// =============================================================================
// 3. COINS PROVIDER
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

  Future<void> giveWelcomeBonus() async {
    if (!_hasReceivedWelcomeBonus) {
      _coins += 50;
      _hasReceivedWelcomeBonus = true;
      await _save();
      notifyListeners();
      AppLogger.success('🎁 Welcome bonus: 50 coins added!');
    }
  }

  Future<void> addCoins(int amount) async {
    _coins += amount;
    notifyListeners();
    await _save();
  }

  Future<bool> deductCoins(int amount) async {
    if (_coins >= amount) {
      _coins -= amount;
      notifyListeners();
      await _save();
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
// -----------------------------------------------------------------------------
// ✅ إصلاح: العملات كانت تُخصم قبل بدء التحميل ولا تُعاد عند الفشل.
// الآن الخصم يتم فقط بعد نجاح الحفظ في المعرض.
// =============================================================================
class DownloadService {
  static const int downloadCost = 10;

  static Future<void> downloadWallpaper(
    BuildContext context,
    WallpaperModel wallpaper,
  ) async {
    final coinsProvider = Provider.of<CoinsProvider>(context, listen: false);
    if (coinsProvider.coins < downloadCost) {
      showInsufficientCoinsDialog(context);
      return;
    }

    final hasPermission = await _requestStoragePermission(context);
    if (!hasPermission) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ يحتاج التطبيق إلى إذن الصور للحفظ',
                style: AppFonts.poppins()),
            backgroundColor: Colors.orange[800],
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

    if (!context.mounted) return;

    final success = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _DownloadProgressDialog(wallpaper: wallpaper),
        ) ??
        false;

    if (!context.mounted) return;

    if (success) {
      await coinsProvider.deductCoins(downloadCost);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'تم الحفظ ✅ | خُصمت $downloadCost عملات — الرصيد: ${coinsProvider.coins} 🪙',
              style: AppFonts.poppins()),
          backgroundColor: Colors.green[700],
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('لم يكتمل التحميل — لم تُخصم أي عملات',
              style: AppFonts.poppins()),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  static Future<bool> _requestStoragePermission(BuildContext context) async {
    if (await GalleryPermission.isGranted()) return true;

    final result = await GalleryPermission.requestOnce();
    if (result == GalleryPermissionResult.granted) return true;

    if (result == GalleryPermissionResult.permanentlyDenied &&
        context.mounted) {
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
    String? savePath;
    try {
      final tempDir = await getTemporaryDirectory();
      final safeTitle =
          widget.wallpaper.title.replaceAll(RegExp(r'[^\w\u0600-\u06FF]'), '_');
      final fileName =
          '${safeTitle}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      savePath = '${tempDir.path}/$fileName';
      final dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 120)));

      void onProgress(int received, int total) {
        if (total != -1 && mounted) {
          setState(() => _progress = received / total);
        }
      }

      try {
        await dio.download(widget.wallpaper.imageUrl, savePath,
            onReceiveProgress: onProgress);
      } catch (e) {
        // ✅ إعادة المحاولة بالنطاق الآخر بدل إظهار فشل مباشر
        final alt = widget.wallpaper.fallbackUrl;
        if (alt.isEmpty || alt == widget.wallpaper.imageUrl) rethrow;
        AppLogger.warning('⚠️ Download failed, retrying via fallback URL');
        if (mounted) setState(() => _progress = 0);
        await dio.download(alt, savePath, onReceiveProgress: onProgress);
      }

      final result = await SaverGallery.saveFile(
        file: savePath,
        name: safeTitle,
        androidRelativePath: 'Pictures/4K خلفيات',
        androidExistNotSave: false,
      );

      final tempFile = File(savePath);
      if (await tempFile.exists()) await tempFile.delete();

      if (!mounted) return;
      setState(() {
        _done = result.isSuccess;
        _error = !result.isSuccess;
        _status = result.isSuccess ? 'تم الحفظ في المعرض ✅' : 'فشل الحفظ ❌';
      });
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) Navigator.of(context).pop(result.isSuccess);
    } catch (e) {
      AppLogger.error('❌ Download failed for ${widget.wallpaper.imageUrl}: $e');
      if (savePath != null) {
        try {
          final f = File(savePath);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _error = true;
        _status = 'تعذّر التحميل، تحقق من الاتصال';
      });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A2533),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(_done ? 'تم التحميل!' : (_error ? 'خطأ' : 'جاري التحميل'),
          style: AppFonts.poppins(
              color: Colors.white, fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.wallpaper.title,
              style: AppFonts.poppins(color: Colors.grey[400], fontSize: 12),
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
                    style: AppFonts.poppins(
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

/// عنصر محذوف من المفضلة مع موقعه الأصلي (لدعم التراجع)
class RemovedFavorite {
  final int index;
  final WallpaperModel wallpaper;
  const RemovedFavorite(this.index, this.wallpaper);
}

class FavoritesProvider with ChangeNotifier {
  final Set<String> _favoriteIds = {};
  final List<WallpaperModel> _favorites = [];

  Set<String> get favoriteIds => _favoriteIds;
  List<WallpaperModel> get favorites => List.unmodifiable(_favorites);
  int get count => _favorites.length;
  bool isFavorite(String id) => _favoriteIds.contains(id);

  List<String> get categories {
    final set = <String>{};
    for (final w in _favorites) {
      if (w.category.trim().isNotEmpty) set.add(w.category);
    }
    final list = set.toList()..sort();
    return list;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList('favorites') ?? [];
    _favorites.clear();
    _favoriteIds.clear();
    for (final jsonStr in jsonList) {
      try {
        final w = WallpaperModel.fromJson(jsonDecode(jsonStr));
        if (_favoriteIds.add(w.id)) _favorites.add(w);
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
    notifyListeners();
    await _save();
  }

  /// حذف مجموعة صور مع إرجاع مواقعها الأصلية حتى يمكن التراجع
  Future<List<RemovedFavorite>> removeMany(Set<String> ids) async {
    if (ids.isEmpty) return const [];
    final removed = <RemovedFavorite>[];
    for (int i = _favorites.length - 1; i >= 0; i--) {
      final w = _favorites[i];
      if (ids.contains(w.id)) {
        removed.add(RemovedFavorite(i, w));
        _favorites.removeAt(i);
        _favoriteIds.remove(w.id);
      }
    }
    removed.sort((a, b) => a.index.compareTo(b.index));
    notifyListeners();
    await _save();
    return removed;
  }

  /// إعادة الصور المحذوفة إلى مواقعها الأصلية
  Future<void> restore(List<RemovedFavorite> items) async {
    if (items.isEmpty) return;
    final sorted = [...items]..sort((a, b) => a.index.compareTo(b.index));
    for (final item in sorted) {
      if (_favoriteIds.contains(item.wallpaper.id)) continue;
      final index =
          item.index < _favorites.length ? item.index : _favorites.length;
      _favorites.insert(index, item.wallpaper);
      _favoriteIds.add(item.wallpaper.id);
    }
    notifyListeners();
    await _save();
  }

  Future<List<RemovedFavorite>> clearAll() async {
    final snapshot = <RemovedFavorite>[
      for (int i = 0; i < _favorites.length; i++)
        RemovedFavorite(i, _favorites[i]),
    ];
    _favorites.clear();
    _favoriteIds.clear();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('favorites');
    return snapshot;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'favorites', _favorites.map((w) => jsonEncode(w.toJson())).toList());
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
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('privacy_accepted', true);
  }
}

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================
void watchAdForCoins(BuildContext context) {
  final messenger = ScaffoldMessenger.of(context);
  AdMobManager().showRewardedAd(
    onUserEarnedReward: (ad, reward) async {
      final coinsProvider = Provider.of<CoinsProvider>(context, listen: false);
      await coinsProvider.addCoins(5);
      messenger.showSnackBar(
        SnackBar(
          content: Text('🎉 حصلت على 5 عملات! رصيدك: ${coinsProvider.coins} 🪙',
              style: AppFonts.poppins()),
          backgroundColor: Colors.green[700],
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    },
    onAdDismissed: () {},
    // ✅ إصلاح: كان الزر لا يفعل شيئاً إذا لم يكن الإعلان جاهزاً
    onAdNotReady: () {
      messenger.showSnackBar(
        SnackBar(
          content: Text('الإعلان غير جاهز بعد، حاول بعد لحظات',
              style: AppFonts.poppins()),
          backgroundColor: Colors.orange[800],
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    },
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
              style: AppFonts.poppins(
                  color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
      content: Text(
        'تحتاج إلى 10 عملات لتحميل هذه الصورة.\nشاهد إعلاناً لكسب 5 عملات!',
        style: AppFonts.poppins(color: Colors.grey[400]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('إلغاء', style: AppFonts.poppins(color: Colors.grey)),
        ),
        ElevatedButton.icon(
          onPressed: () {
            Navigator.pop(context);
            watchAdForCoins(context);
          },
          icon: const Icon(Icons.play_circle_outline, size: 18),
          label: Text('شاهد إعلاناً (+5 🪙)',
              style: AppFonts.poppins(fontWeight: FontWeight.w600)),
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
      this.blur = 10.0,
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

/// ✅ بديل خفيف للزجاج بدون BackdropFilter — يُستخدم في القوائم الطويلة
/// (الإعدادات مثلاً) حيث كان الضباب يستهلك إطارات كثيرة على الأجهزة المتوسطة.
class SolidPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  const SolidPanel(
      {super.key,
      required this.child,
      this.padding = EdgeInsets.zero,
      this.radius = 16});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF16202C),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: child,
    );
  }
}

/// ✅ صورة شبكية مع تراجع تلقائي: إذا فشل رابط المصغّر (وسيط خارجي محجوب
/// مثلاً) تُجرَّب الصورة الأصلية بدل ترك مكان فارغ أو تحميل لا ينتهي.
class NetImage extends StatefulWidget {
  final String url;
  final String fallbackUrl;
  final int? memWidth;
  final BoxFit fit;
  const NetImage({
    super.key,
    required this.url,
    this.fallbackUrl = '',
    this.memWidth,
    this.fit = BoxFit.cover,
  });

  @override
  State<NetImage> createState() => _NetImageState();
}

class _NetImageState extends State<NetImage> {
  Timer? _watchdog;
  bool _useFallback = false;

  String get _primary =>
      widget.url.isNotEmpty ? widget.url : widget.fallbackUrl;
  bool get _hasFallback =>
      widget.fallbackUrl.isNotEmpty && widget.fallbackUrl != _primary;

  @override
  void initState() {
    super.initState();
    _startWatchdog();
  }

  @override
  void didUpdateWidget(covariant NetImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.fallbackUrl != widget.fallbackUrl) {
      _watchdog?.cancel();
      _useFallback = false;
      _startWatchdog();
    }
  }

  /// ✅ حارس زمني: أخطر حالة ليست فشل الرابط بل تعليقه بلا رد — عندها لا
  /// يُستدعى errorWidget إطلاقاً وتبقى الشاشة في وضع تحميل للأبد. بعد 7
  /// ثوانٍ بلا صورة ننتقل تلقائياً إلى الرابط الأصلي المباشر.
  void _startWatchdog() {
    if (!_hasFallback) return;
    _watchdog = Timer(const Duration(seconds: 5), () {
      if (!mounted || _useFallback) return;
      AppLogger.warning('⌛ Image stalled, switching to direct URL: $_primary');
      setState(() => _useFallback = true);
    });
  }

  void _cancelWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
  }

  @override
  void dispose() {
    _cancelWatchdog();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = _useFallback ? widget.fallbackUrl : _primary;
    return CachedNetworkImage(
      imageUrl: url,
      fit: widget.fit,
      memCacheWidth: widget.memWidth,
      // ✅ أُزيل maxWidthDiskCache: كان يعيد ترميز كل صورة قبل حفظها على
      // القرص، وهو عمل ثقيل على المعالج ظهر في اللوج كـ 856 إطاراً مفقوداً.
      // memCacheWidth وحده يكفي للتحكم في الذاكرة.
      fadeInDuration: const Duration(milliseconds: 120),
      imageBuilder: (context, provider) {
        _cancelWatchdog();
        return Image(image: provider, fit: widget.fit);
      },
      placeholder: (_, __) => const ShimmerLoadingCard(),
      errorWidget: (context, failedUrl, error) {
        AppLogger.error('❌ Image failed: $failedUrl | $error');
        if (!_useFallback && _hasFallback) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _useFallback = true);
          });
          return const ShimmerLoadingCard();
        }
        return const ImageErrorBox();
      },
    );
  }
}

class ImageErrorBox extends StatelessWidget {
  const ImageErrorBox({super.key});
  @override
  Widget build(BuildContext context) => const ColoredBox(
      color: Color(0xFF20262E),
      child: Center(child: Icon(Icons.broken_image, color: Colors.grey)));
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
            final messenger = ScaffoldMessenger.of(context);
            await favProvider.toggle(wallpaper);
            messenger.showSnackBar(SnackBar(
                content: Text(isFav ? '💔 حُذف من المفضلة' : '❤️ أُضيف للمفضلة',
                    style: AppFonts.poppins()),
                duration: const Duration(seconds: 1),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))));
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
                NetImage(
                    url: wallpaper.thumbnailUrl,
                    fallbackUrl: wallpaper.fallbackUrl,
                    // عرض البطاقة الفعلي ~110-180 بكسل منطقي، فـ320 وفير
                    memWidth: 320),
                const _BottomScrim(),
                Positioned(
                    bottom: 10,
                    left: 8,
                    right: 8,
                    child: Text(wallpaper.title,
                        style: AppFonts.poppins(
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
              NetImage(
                  url: wallpaper.thumbnailUrl,
                  fallbackUrl: wallpaper.fallbackUrl,
                  memWidth: 560),
              const _BottomScrim(),
              Positioned(
                  bottom: 10,
                  left: 12,
                  right: 12,
                  child: Text(wallpaper.title,
                      style: AppFonts.poppins(
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

/// تدرّج سفلي ثابت (const) — أرخص من إنشاء BoxDecoration جديد لكل بطاقة
class _BottomScrim extends StatelessWidget {
  const _BottomScrim();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.45, 1.0],
          colors: [Colors.transparent, Color(0xB3000000)],
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
                      style: AppFonts.poppins(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 18))
                ])),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SolidPanel(
                  radius: 20,
                  padding: const EdgeInsets.all(20),
                  child: SingleChildScrollView(
                      child: Text(kPrivacyPolicyText,
                          style: AppFonts.poppins(
                              color: Colors.white.withValues(alpha: 0.88),
                              fontSize: 13.5,
                              height: 1.9),
                          textDirection: TextDirection.rtl)),
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
                          style: AppFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 17)),
                      Text('يرجى القراءة قبل المتابعة',
                          style: AppFonts.poppins(
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
                          style: AppFonts.poppins(
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
                            style: AppFonts.poppins(
                                color: Colors.grey[500], fontSize: 11))
                      ])),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    await context.read<PrivacyProvider>().accept();
                    navigator.pop();
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 0),
                  child: Text('أوافق على سياسة الخصوصية',
                      style: AppFonts.poppins(
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

/// ✅ تحميل مسبق لأول قسمين + أول 4 صور من السلايدر. يُستدعى من main() قبل
/// runApp أصلاً (بالتوازي مع تهيئة AdMob) حتى تبدأ طلبات الصور بأسرع وقت
/// ممكن بدل انتظار اكتمال الإقلاع بالكامل ثم ظهور شاشة البداية.
Future<void> _prefetchInitialWallpapers() async {
  unawaited(GitHubService.futureOf('New'));
  try {
    final list = await GitHubService.futureOf('16:9');
    for (final w in list.take(4)) {
      if (w.thumbnailUrl.isEmpty) continue;
      // resolve() يبدأ التنزيل ويضعه في كاش الصور بدون الحاجة إلى context
      CachedNetworkImageProvider(w.thumbnailUrl)
          .resolve(ImageConfiguration.empty);
    }
  } catch (e) {
    AppLogger.error('❌ _prefetchInitialWallpapers failed: $e');
  }
}

// =============================================================================
// 8. SPLASH SCREEN — ✅ زمن أقصر (1500ms بدل 3000ms)
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
        vsync: this, duration: const Duration(milliseconds: 1200));
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

    // ✅ تحميل مسبق لأول قسمين أثناء ظهور شاشة البداية → الرئيسية تفتح جاهزة
    // ✅ التحميل المسبق يبدأ الآن من main() قبل حتى ظهور هذه الشاشة (أثناء
    // تهيئة AdMob)، فيصل هنا وقد بدأ فعلياً أو اكتمل. futureOf مُخزَّن مسبقاً
    // (memoized) لذا لا يتكرر أي طلب شبكة بإعادة النداء هنا.
    unawaited(_prefetchInitialWallpapers());

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
            transitionDuration: const Duration(milliseconds: 400)));
      }
    }

    AdMobManager().showAppOpenAd(onComplete: () {
      adFinished = true;
      maybeNavigate();
    });

    Future.delayed(const Duration(milliseconds: 1500), () {
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
                        style: AppFonts.poppins(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('اكتشف أجمل الخلفيات',
                        style: AppFonts.poppins(
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
// 9. PREVIEW SCREEN — ✅ الآن يستخدم heroTag فعلياً (كان يُمرَّر ولا يُستعمل)
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
    DownloadService.downloadWallpaper(context, wallpaper);
  }

  @override
  Widget build(BuildContext context) {
    // ✅ فك الترميز بحجم الشاشة الفعلي (بالبكسل) بدل الأبعاد الكاملة للصورة
    // (قد تكون 4K+) — يقلّل زمن ووزن فك الترميز فتظهر الصورة أسرع وبسلاسة
    // أكبر أثناء التمرير، دون التأثير على جودة ملف التحميل الفعلي لاحقاً.
    final media = MediaQuery.of(context);
    // ✅ سقف 1080: بدونه تُفكّ الصورة بعرض 1242 على iPhone = ~13 ميجابايت
    // للصورة الواحدة، ومع الصفحتين المجاورتين المحمّلتين مسبقاً تتجاوز
    // الذاكرة حدّ النظام فيُقتل التطبيق بصمت أثناء التمرير.
    final rawWidth = (media.size.width * media.devicePixelRatio).round();
    final decodeWidth = rawWidth > 1080 ? 1080 : rawWidth;
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemCount: widget.wallpapers.length,
        // ✅ يجعل فلاتر تبني الصفحة التالية/السابقة مسبقاً (وبالتالي تبدأ
        // صورتها بالتنزيل) قبل أن يصل إليها المستخدم بالتمرير فعلياً.
        allowImplicitScrolling: true,
        itemBuilder: (context, index) {
          final wallpaper = widget.wallpapers[index];
          // ✅ الصورة الكاملة أيضاً تستفيد من التراجع التلقائي بين النطاقين
          final image = NetImage(
            url: wallpaper.imageUrl,
            fallbackUrl: wallpaper.fallbackUrl,
            fit: wallpaper.isLandscape ? BoxFit.fitWidth : BoxFit.cover,
            memWidth: decodeWidth,
          );

          return Stack(children: [
            Positioned.fill(
                child: index == widget.initialIndex
                    ? Hero(tag: widget.heroTag, child: image)
                    : image),
            const Positioned.fill(child: _PreviewScrim()),
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
                      onPressed: () => SharePlus.instance.share(ShareParams(
                          text:
                              'شاهد هذه الخلفية الرائعة: ${wallpaper.title}\n${wallpaper.imageUrl}'))),
                ]),
              ),
            ),
            Positioned(
              bottom: 40,
              left: 16,
              right: 16,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const ResponsiveBannerAdWidget(),
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
                                style: AppFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            Text(
                                '${wallpaper.category} • ${wallpaper.width}×${wallpaper.height}',
                                style: AppFonts.poppins(
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
                              style: AppFonts.poppins(
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
                        style: AppFonts.poppins(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)))),
          ]);
        },
      ),
    );
  }
}

class _PreviewScrim extends StatelessWidget {
  const _PreviewScrim();
  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.0, 0.35, 0.7, 1.0],
          colors: [
            Color(0x73000000),
            Colors.transparent,
            Colors.transparent,
            Color(0xF2000000),
          ],
        ),
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
          style: AppFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
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
      backgroundColor: const Color(0xFF0F1620),
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new,
                  color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context)),
          title: Text(categoryName,
              style: AppFonts.poppins(
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

class _WallpaperGridLoaderState extends State<_WallpaperGridLoader>
    with AutomaticKeepAliveClientMixin {
  late Future<List<WallpaperModel>> _future;

  // ✅ تحميل تدريجي: تُبنى 20 صورة فقط في البداية ثم 20 مع كل وصول للنهاية.
  // الهدف تقليل عدد الصور المفكوكة في الذاكرة دفعة واحدة — وهو سبب إغلاق
  // iOS للتطبيق تلقائياً (jetsam) في الأقسام الكبيرة.
  static const int _pageSize = 20;
  int _visible = _pageSize;

  @override
  bool get wantKeepAlive => true;

  /// يُستدعى مع كل تمرير: يزيد المعروض عند الاقتراب من نهاية القائمة
  bool _onScroll(ScrollNotification notification, int total) {
    if (_visible >= total) return false;
    final metrics = notification.metrics;
    if (metrics.pixels >= metrics.maxScrollExtent - 600) {
      setState(() {
        final next = _visible + _pageSize;
        _visible = next > total ? total : next;
      });
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _future = GitHubService.futureOf(widget.categoryName);
  }

  Future<void> _refresh() async {
    GitHubService.clearCache();
    if (!mounted) return;
    setState(() {
      _visible = _pageSize;
      _future = GitHubService.futureOf(widget.categoryName);
    });
    await _future;
  }

  void _navigateWithAd(WallpaperModel wallpaper, Object heroTag,
      List<WallpaperModel> wallpapers, int initialIndex) {
    AdMobManager().trackWallpaperView(
      onAdComplete: () {
        if (!mounted) return;
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
                transitionDuration: const Duration(milliseconds: 280)));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<WallpaperModel>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return widget.isLandscape ? _shimmerLandscape() : _shimmerGrid();
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Icon(Icons.folder_open, size: 64, color: Colors.grey[600]),
                const SizedBox(height: 16),
                Text('لا توجد صور',
                    style: AppFonts.poppins(color: Colors.grey)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                    label: Text('إعادة المحاولة', style: AppFonts.poppins()),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))))
              ]));
        }
        final wallpapers = snapshot.data!;
        final total = wallpapers.length;
        final shown = _visible > total ? total : _visible;

        return Column(children: [
          const ResponsiveBannerAdWidget(),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) => _onScroll(n, total),
              child: RefreshIndicator(
                onRefresh: _refresh,
                color: Colors.blueAccent,
                child: widget.isLandscape
                    ? ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: shown,
                        cacheExtent: 400,
                        addAutomaticKeepAlives: false,
                        itemBuilder: (context, index) {
                          final heroTag =
                              'grid_${widget.categoryName}_${wallpapers[index].id}_$index';
                          return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: RepaintBoundary(
                                    child: WallpaperCard169(
                                        wallpaper: wallpapers[index],
                                        heroTag: heroTag,
                                        onTap: () => _navigateWithAd(
                                            wallpapers[index],
                                            heroTag,
                                            wallpapers,
                                            index)),
                                  )));
                        },
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        cacheExtent: 400,
                        addAutomaticKeepAlives: false,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 0.65,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12),
                        itemCount: shown,
                        itemBuilder: (context, index) {
                          final heroTag =
                              'grid_${widget.categoryName}_${wallpapers[index].id}_$index';
                          return RepaintBoundary(
                            child: WallpaperCard(
                                wallpaper: wallpapers[index],
                                heroTag: heroTag,
                                onTap: () => _navigateWithAd(wallpapers[index],
                                    heroTag, wallpapers, index)),
                          );
                        },
                      ),
              ),
            ),
          ),
          // مؤشر صغير يوضّح أن هناك المزيد قادماً
          if (shown < total)
            Padding(
              padding: const EdgeInsets.only(bottom: 92, top: 4),
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.blueAccent)),
                const SizedBox(width: 8),
                Text('$shown من $total',
                    style: AppFonts.poppins(
                        color: Colors.grey[500], fontSize: 12)),
              ]),
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
      itemCount: 8,
      itemBuilder: (_, __) => const ShimmerLoadingCard());

  Widget _shimmerLandscape() => ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child:
              AspectRatio(aspectRatio: 16 / 9, child: ShimmerLoadingCard())));
}

// =============================================================================
// 11. HOME SCREEN
// -----------------------------------------------------------------------------
// ✅ تعديلات: حذف بطاقات الإعلان من القوائم الأفقية (كانت تنشئ ~16 بانر في
// وقت واحد داخل بطاقات عرضها 110 بكسل)، واستخدام futureOf بدل إنشاء Future
// جديد في كل إعادة بناء.
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
    return CustomScrollView(cacheExtent: 300, slivers: [
      SliverAppBar(
        floating: true,
        snap: true,
        backgroundColor: Colors.transparent,
        title: Text('KM2 Wallpapers',
            style: AppFonts.poppins(
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
                    style: AppFonts.poppins(
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
      const SliverToBoxAdapter(child: _TopAutoSlider169()),
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
      _sectionHeader(context, 'Cars', 'Cars'),
      _horizontalList(context, 'Cars'),
      _sectionHeader(context, 'Nature', 'Nature'),
      _horizontalList(context, 'Nature'),
      _sectionHeader(context, 'Space', 'Space'),
      _horizontalList(context, 'Space'),
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
                style: AppFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            if (title == '16:9') ...[
              const SizedBox(width: 8),
              const Icon(Icons.aspect_ratio, color: Colors.blueAccent, size: 20)
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
    final screenWidth = MediaQuery.of(context).size.width;
    const horizontalPadding = 16.0;
    const cardSpacing = 10.0;
    final portraitCardWidth =
        (screenWidth - (horizontalPadding * 2) - (cardSpacing * 2)) / 3;
    final cardWidth = is169 ? 285.0 : portraitCardWidth;
    final cardHeight = is169 ? 160.0 : cardWidth / 0.6;

    return SliverToBoxAdapter(
      child: FutureBuilder<List<WallpaperModel>>(
        future: GitHubService.futureOf(category),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return SizedBox(
                height: cardHeight,
                child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: horizontalPadding),
                    itemCount: 4,
                    separatorBuilder: (_, __) =>
                        const SizedBox(width: cardSpacing),
                    itemBuilder: (_, __) => SizedBox(
                        width: cardWidth, child: const ShimmerLoadingCard())));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return SizedBox(height: cardHeight);
          }
          final wallpapers = snapshot.data!;
          final count = wallpapers.length > 12 ? 12 : wallpapers.length;
          return SizedBox(
            height: cardHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(horizontal: horizontalPadding),
              itemCount: count,
              addAutomaticKeepAlives: false,
              separatorBuilder: (_, __) => const SizedBox(width: cardSpacing),
              itemBuilder: (context, index) {
                final heroTag =
                    'home_${category}_${wallpapers[index].id}_$index';
                return RepaintBoundary(
                  child: WallpaperCard(
                    wallpaper: wallpapers[index],
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
                                          wallpaper: wallpapers[index],
                                          heroTag: heroTag,
                                          wallpapers: wallpapers,
                                          initialIndex: index)),
                                  transitionDuration:
                                      const Duration(milliseconds: 280)));
                        },
                      );
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  SliverToBoxAdapter _categoryRow(BuildContext context, CategoryModel cat) {
    return SliverToBoxAdapter(
      child: GestureDetector(
        onTap: () => _navigateTo(context, cat.name),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: FutureBuilder<List<WallpaperModel>>(
            future: GitHubService.futureOf(cat.name),
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
                      NetImage(
                          url: snapshot.data![0].thumbnailUrl,
                          fallbackUrl: snapshot.data![0].fallbackUrl,
                          memWidth: 300),
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
                                    style: AppFonts.poppins(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15)),
                                if (snapshot.hasData)
                                  Text('${snapshot.data!.length} صورة',
                                      style: AppFonts.poppins(
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
// 11.1 TOP AUTO SLIDER — سلايدر 16:9
// =============================================================================
class _TopAutoSlider169 extends StatefulWidget {
  const _TopAutoSlider169();

  @override
  State<_TopAutoSlider169> createState() => _TopAutoSlider169State();
}

class _TopAutoSlider169State extends State<_TopAutoSlider169> {
  final PageController _pageController = PageController();
  Timer? _timer;
  int _currentPage = 0;
  List<WallpaperModel> _wallpapers = [];
  bool _loading = true;

  static const int _maxSlides = 10;

  @override
  void initState() {
    super.initState();
    _loadWallpapers();
  }

  Future<void> _loadWallpapers() async {
    try {
      final wallpapers = await GitHubService.futureOf('16:9');
      if (!mounted) return;
      setState(() {
        _wallpapers = wallpapers.length > _maxSlides
            ? wallpapers.sublist(0, _maxSlides)
            : wallpapers;
        _loading = false;
      });
      if (_wallpapers.length > 1) _startAutoSlide();
    } catch (e) {
      AppLogger.error('❌ Failed to load top 16:9 slider: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startAutoSlide() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted || _wallpapers.isEmpty || !_pageController.hasClients) {
        return;
      }
      _currentPage = (_currentPage + 1) % _wallpapers.length;
      _pageController.animateToPage(
        _currentPage,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _restartAutoSlideDelayed() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 6), () {
      if (mounted && _wallpapers.length > 1) _startAutoSlide();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _openWallpaper(BuildContext context, int index) {
    final wallpaper = _wallpapers[index];
    // ✅ نفس الوسم المستخدم في الـ Hero بالأسفل حتى تعمل حركة الانتقال فعلاً
    final heroTag = 'slider_${wallpaper.id}_$index';
    AdMobManager().trackWallpaperView(
      onAdComplete: () {
        if (!mounted) return;
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, anim, __) => FadeTransition(
              opacity: anim,
              child: PreviewScreen(
                wallpaper: wallpaper,
                heroTag: heroTag,
                wallpapers: _wallpapers,
                initialIndex: index,
              ),
            ),
            transitionDuration: const Duration(milliseconds: 280),
          ),
        );
      },
    );
  }

  Widget _glass({
    required Widget child,
    double radius = 14,
    double blur = 10,
    double opacity = 0.14,
    EdgeInsetsGeometry? padding,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: AspectRatio(aspectRatio: 16 / 9, child: ShimmerLoadingCard()),
      );
    }

    if (_wallpapers.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _glass(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.crop_landscape_rounded,
                        color: Colors.cyanAccent, size: 16),
                    const SizedBox(width: 8),
                    Text('مختارات 16:9',
                        style: AppFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                  ]),
                ),
                GestureDetector(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const Screen169())),
                  child: _glass(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('الكل',
                          style: AppFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                      const SizedBox(width: 3),
                      const Icon(Icons.arrow_back_ios_rounded,
                          color: Colors.white, size: 10),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: NotificationListener<ScrollNotification>(
                onNotification: (notif) {
                  if (notif is ScrollStartNotification) _timer?.cancel();
                  if (notif is ScrollEndNotification)
                    _restartAutoSlideDelayed();
                  return false;
                },
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _wallpapers.length,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  allowImplicitScrolling: true,
                  itemBuilder: (context, index) {
                    final wallpaper = _wallpapers[index];
                    return RepaintBoundary(
                      child: GestureDetector(
                        onTap: () => _openWallpaper(context, index),
                        child: Hero(
                          tag: 'slider_${wallpaper.id}_$index',
                          child: NetImage(
                            url: wallpaper.thumbnailUrl,
                            fallbackUrl: wallpaper.fallbackUrl,
                            memWidth: 640,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(_wallpapers.length, (i) {
                  final isActive = _currentPage == i;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeInOutCubic,
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    width: isActive ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: isActive
                          ? Colors.cyanAccent
                          : Colors.white.withValues(alpha: 0.25),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
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
              style: AppFonts.poppins(
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
              style: AppFonts.poppins(
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
                style: AppFonts.poppins(
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
                    style: AppFonts.poppins(
                        fontSize: 11,
                        color: Colors.cyan,
                        fontWeight: FontWeight.w600)))
          ])),
      body:
          const _WallpaperGridLoader(categoryName: '16:9', isLandscape: true));
}

// =============================================================================
// 12.1 ⭐ FAVORITES v2 — شاشة المفضلة المطوّرة
// -----------------------------------------------------------------------------
// بحث • فلترة بالتصنيف • ترتيب • عرض شبكي/قائمة • تحديد متعدد • تراجع عن الحذف
// =============================================================================
enum FavSort { recent, title, category }

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  String? _categoryFilter;
  FavSort _sort = FavSort.recent;
  bool _gridView = true;
  bool _selecting = false;
  final Set<String> _selected = {};

  static const Color _panel = Color(0xFF16202C);
  static const Color _panelBorder = Color(0x1FFFFFFF);

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── الفلترة والترتيب ──
  List<WallpaperModel> _apply(List<WallpaperModel> source) {
    final q = _query.trim().toLowerCase();
    final list = source.where((w) {
      final okCategory =
          _categoryFilter == null || w.category == _categoryFilter;
      final okQuery = q.isEmpty ||
          w.title.toLowerCase().contains(q) ||
          w.category.toLowerCase().contains(q);
      return okCategory && okQuery;
    }).toList();

    switch (_sort) {
      case FavSort.recent:
        break; // الترتيب المخزّن أصلاً = الأحدث أولاً
      case FavSort.title:
        list.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case FavSort.category:
        list.sort((a, b) {
          final c = a.category.compareTo(b.category);
          return c != 0 ? c : a.title.compareTo(b.title);
        });
        break;
    }
    return list;
  }

  String get _sortLabel {
    switch (_sort) {
      case FavSort.recent:
        return 'الأحدث';
      case FavSort.title:
        return 'الاسم';
      case FavSort.category:
        return 'التصنيف';
    }
  }

  // ── الإجراءات ──
  void _toggleSelect(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
      if (_selected.isEmpty) _selecting = false;
    });
  }

  void _startSelecting(String id) {
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..add(id);
    });
  }

  void _exitSelecting() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  Future<void> _deleteIds(Set<String> ids) async {
    final provider = context.read<FavoritesProvider>();
    final removed = await provider.removeMany(ids);
    if (!mounted || removed.isEmpty) return;
    _exitSelecting();
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          removed.length == 1
              ? 'حُذفت صورة من المفضلة'
              : 'حُذفت ${removed.length} صور من المفضلة',
          style: AppFonts.poppins(),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1A2533),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'تراجع',
          textColor: Colors.amber,
          onPressed: () => provider.restore(removed),
        ),
      ),
    );
  }

  Future<void> _confirmClearAll() async {
    final provider = context.read<FavoritesProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2533),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('مسح المفضلة كاملة',
            style: AppFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('سيتم حذف ${provider.count} صورة. يمكنك التراجع فوراً.',
            style: AppFonts.poppins(color: Colors.grey[400])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('إلغاء',
                  style: AppFonts.poppins(color: Colors.grey[500]))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  Text('مسح الكل', style: AppFonts.poppins(color: Colors.red))),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final removed = await provider.clearAll();
    if (!mounted || removed.isEmpty) return;
    _exitSelecting();
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content:
            Text('حُذفت ${removed.length} صورة', style: AppFonts.poppins()),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1A2533),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
            label: 'تراجع',
            textColor: Colors.amber,
            onPressed: () => provider.restore(removed)),
      ));
  }

  void _shareSelected(List<WallpaperModel> visible) {
    final chosen = visible.where((w) => _selected.contains(w.id)).toList();
    if (chosen.isEmpty) return;
    final text = chosen.map((w) => '${w.title}\n${w.imageUrl}').join('\n\n');
    SharePlus.instance.share(ShareParams(text: text));
  }

  void _openPreview(List<WallpaperModel> list, int index) {
    final wallpaper = list[index];
    AdMobManager().trackWallpaperView(onAdComplete: () {
      if (!mounted) return;
      Navigator.push(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 260),
          pageBuilder: (_, anim, __) => FadeTransition(
            opacity: anim,
            child: PreviewScreen(
              wallpaper: wallpaper,
              heroTag: 'fav_${wallpaper.id}',
              wallpapers: list,
              initialIndex: index,
            ),
          ),
        ),
      );
    });
  }

  // ── البناء ──
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Consumer<FavoritesProvider>(
        builder: (context, provider, _) {
          final all = provider.favorites;
          final visible = _apply(all);
          final categories = provider.categories;

          return Scaffold(
            backgroundColor: Colors.transparent,
            body: CustomScrollView(
              // يبني عناصر أبعد قليلاً عن الشاشة مسبقاً → تمرير أنعم
              cacheExtent: 600,
              slivers: [
                _appBar(provider, visible),
                if (all.isNotEmpty) ...[
                  SliverToBoxAdapter(child: _searchField()),
                  if (categories.isNotEmpty)
                    SliverToBoxAdapter(child: _categoryChips(categories)),
                  SliverToBoxAdapter(
                      child: _statsRow(all.length, visible.length)),
                ],
                if (all.isEmpty)
                  SliverFillRemaining(
                      hasScrollBody: false, child: _emptyState())
                else if (visible.isEmpty)
                  SliverFillRemaining(
                      hasScrollBody: false, child: _noResultsState())
                else if (_gridView)
                  _grid(visible)
                else
                  _list(visible),
                const SliverToBoxAdapter(child: SizedBox(height: 110)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _appBar(FavoritesProvider provider, List<WallpaperModel> visible) {
    if (_selecting) {
      return SliverAppBar(
        pinned: true,
        backgroundColor: const Color(0xFF0F2027),
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: _exitSelecting),
        title: Text('${_selected.length} محددة',
            style: AppFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        actions: [
          IconButton(
            tooltip: 'تحديد الكل',
            icon: const Icon(Icons.select_all, color: Colors.white),
            onPressed: () => setState(() {
              _selected
                ..clear()
                ..addAll(visible.map((w) => w.id));
            }),
          ),
          IconButton(
            tooltip: 'مشاركة',
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: () => _shareSelected(visible),
          ),
          IconButton(
            tooltip: 'حذف',
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () => _deleteIds({..._selected}),
          ),
        ],
      );
    }

    return SliverAppBar(
      floating: true,
      snap: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context)),
      title: Row(children: [
        Text('المفضلة',
            style: AppFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 22,
                color: Colors.white)),
        if (provider.count > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withValues(alpha: 0.35))),
            child: Text('${provider.count}',
                style: AppFonts.poppins(
                    color: Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ]),
      actions: provider.count == 0
          ? null
          : [
              IconButton(
                tooltip: _gridView ? 'عرض قائمة' : 'عرض شبكي',
                icon: Icon(
                    _gridView
                        ? Icons.view_agenda_outlined
                        : Icons.grid_view_rounded,
                    color: Colors.white,
                    size: 22),
                onPressed: () => setState(() => _gridView = !_gridView),
              ),
              PopupMenuButton<FavSort>(
                tooltip: 'ترتيب',
                color: const Color(0xFF1A2533),
                icon: const Icon(Icons.sort_rounded, color: Colors.white),
                onSelected: (value) => setState(() => _sort = value),
                itemBuilder: (_) => [
                  _sortItem(FavSort.recent, 'الأحدث إضافة', Icons.schedule),
                  _sortItem(FavSort.title, 'الاسم (أ–ي)', Icons.sort_by_alpha),
                  _sortItem(
                      FavSort.category, 'التصنيف', Icons.category_outlined),
                ],
              ),
              IconButton(
                tooltip: 'مسح الكل',
                icon: const Icon(Icons.delete_sweep_outlined,
                    color: Colors.redAccent),
                onPressed: _confirmClearAll,
              ),
            ],
    );
  }

  PopupMenuItem<FavSort> _sortItem(FavSort value, String label, IconData icon) {
    final selected = _sort == value;
    return PopupMenuItem<FavSort>(
      value: value,
      child: Row(children: [
        Icon(icon,
            size: 18, color: selected ? Colors.blueAccent : Colors.grey[500]),
        const SizedBox(width: 10),
        Text(label,
            style: AppFonts.poppins(
                color: selected ? Colors.blueAccent : Colors.white,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
      ]),
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Container(
        decoration: BoxDecoration(
            color: _panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _panelBorder)),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          style: AppFonts.poppins(color: Colors.white, fontSize: 14),
          cursorColor: Colors.blueAccent,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            hintText: 'ابحث داخل المفضلة',
            hintStyle: AppFonts.poppins(color: Colors.grey[600], fontSize: 13),
            prefixIcon: Icon(Icons.search, color: Colors.grey[500], size: 20),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: Icon(Icons.close, color: Colors.grey[500], size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    },
                  ),
          ),
        ),
      ),
    );
  }

  Widget _categoryChips(List<String> categories) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        itemCount: categories.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _chip('الكل', _categoryFilter == null,
                () => setState(() => _categoryFilter = null));
          }
          final cat = categories[index - 1];
          return _chip(cat, _categoryFilter == cat,
              () => setState(() => _categoryFilter = cat));
        },
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.blueAccent.withValues(alpha: 0.22) : _panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected
                  ? Colors.blueAccent.withValues(alpha: 0.6)
                  : _panelBorder),
        ),
        child: Text(label,
            style: AppFonts.poppins(
                color: selected ? Colors.blueAccent : Colors.grey[400],
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }

  Widget _statsRow(int total, int shown) {
    final filtered = shown != total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
      child: Row(children: [
        Text(filtered ? '$shown من $total صورة' : '$total صورة',
            style: AppFonts.poppins(color: Colors.grey[500], fontSize: 12)),
        const Spacer(),
        Icon(Icons.sort_rounded, size: 13, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(_sortLabel,
            style: AppFonts.poppins(color: Colors.grey[500], fontSize: 12)),
      ]),
    );
  }

  Widget _grid(List<WallpaperModel> visible) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.66,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final wallpaper = visible[index];
            return RepaintBoundary(
              child: _FavGridCard(
                wallpaper: wallpaper,
                selecting: _selecting,
                selected: _selected.contains(wallpaper.id),
                onTap: () => _selecting
                    ? _toggleSelect(wallpaper.id)
                    : _openPreview(visible, index),
                onLongPress: () => _startSelecting(wallpaper.id),
                onRemove: () => _deleteIds({wallpaper.id}),
              ),
            );
          },
          childCount: visible.length,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: false,
        ),
      ),
    );
  }

  Widget _list(List<WallpaperModel> visible) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final wallpaper = visible[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: RepaintBoundary(
                child: _FavListRow(
                  wallpaper: wallpaper,
                  selecting: _selecting,
                  selected: _selected.contains(wallpaper.id),
                  onTap: () => _selecting
                      ? _toggleSelect(wallpaper.id)
                      : _openPreview(visible, index),
                  onLongPress: () => _startSelecting(wallpaper.id),
                  onRemove: () => _deleteIds({wallpaper.id}),
                ),
              ),
            );
          },
          childCount: visible.length,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: false,
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.withValues(alpha: 0.08),
                border: Border.all(color: Colors.red.withValues(alpha: 0.25))),
            child: const Icon(Icons.favorite_border,
                size: 44, color: Colors.redAccent),
          ),
          const SizedBox(height: 22),
          Text('المفضلة فارغة',
              style: AppFonts.poppins(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('اضغط ♥ على أي خلفية لتحفظها هنا وتصل إليها بسرعة',
              textAlign: TextAlign.center,
              style: AppFonts.poppins(color: Colors.grey[500], fontSize: 13)),
          const SizedBox(height: 22),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            label: Text('تصفّح الخلفيات',
                style: AppFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0),
          ),
        ]),
      ),
    );
  }

  Widget _noResultsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.search_off, size: 56, color: Colors.grey[700]),
          const SizedBox(height: 16),
          Text('لا نتائج مطابقة',
              style: AppFonts.poppins(color: Colors.grey[400], fontSize: 15)),
          const SizedBox(height: 14),
          TextButton(
            onPressed: () {
              _searchCtrl.clear();
              setState(() {
                _query = '';
                _categoryFilter = null;
              });
            },
            child: Text('إزالة الفلاتر',
                style: AppFonts.poppins(color: Colors.blueAccent)),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3) البطاقات
// ─────────────────────────────────────────────────────────────────────────────

class _FavGridCard extends StatelessWidget {
  final WallpaperModel wallpaper;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onRemove;

  const _FavGridCard({
    required this.wallpaper,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? Colors.blueAccent : Colors.transparent,
              width: 2.5),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 4))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(fit: StackFit.expand, children: [
            Hero(
              tag: 'fav_${wallpaper.id}',
              child: NetImage(
                url: wallpaper.thumbnailUrl,
                fallbackUrl: wallpaper.fallbackUrl,
                memWidth: 400,
              ),
            ),
            const _BottomScrim(),
            Positioned(
              bottom: 10,
              right: 8,
              left: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(wallpaper.title,
                      style: AppFonts.poppins(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(wallpaper.category,
                      style: AppFonts.poppins(
                          color: Colors.white60, fontSize: 9.5)),
                ],
              ),
            ),
            if (selecting)
              Positioned(
                top: 8,
                left: 8,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected
                          ? Colors.blueAccent
                          : Colors.black.withValues(alpha: 0.45),
                      border: Border.all(color: Colors.white70, width: 1.5)),
                  child: Icon(selected ? Icons.check : Icons.circle_outlined,
                      size: 14, color: Colors.white),
                ),
              )
            else
              Positioned(
                top: 6,
                left: 6,
                child: GestureDetector(
                  onTap: onRemove,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.42)),
                    child: const Icon(Icons.favorite,
                        color: Colors.redAccent, size: 15),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _FavListRow extends StatelessWidget {
  final WallpaperModel wallpaper;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onRemove;

  const _FavListRow({
    required this.wallpaper,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected
              ? Colors.blueAccent.withValues(alpha: 0.14)
              : const Color(0xFF16202C),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected
                  ? Colors.blueAccent.withValues(alpha: 0.6)
                  : const Color(0x1FFFFFFF)),
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 78,
              height: 78,
              child: NetImage(
                url: wallpaper.thumbnailUrl,
                fallbackUrl: wallpaper.fallbackUrl,
                memWidth: 220,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(wallpaper.title,
                      style: AppFonts.poppins(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 5),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.blueAccent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(wallpaper.category,
                          style: AppFonts.poppins(
                              color: Colors.blueAccent, fontSize: 10)),
                    ),
                    const SizedBox(width: 8),
                    Text(wallpaper.isLandscape ? '16:9' : '9:16',
                        style: AppFonts.poppins(
                            color: Colors.grey[500], fontSize: 10)),
                  ]),
                ]),
          ),
          if (selecting)
            Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? Colors.blueAccent : Colors.grey[600],
                size: 22)
          else
            IconButton(
              icon:
                  const Icon(Icons.favorite, color: Colors.redAccent, size: 20),
              onPressed: onRemove,
            ),
        ]),
      ),
    );
  }
}

// =============================================================================
// 12.2 CATALOG
// =============================================================================
class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return CustomScrollView(slivers: [
      SliverAppBar(
          floating: true,
          backgroundColor: Colors.transparent,
          title: Text('Catalog',
              style: AppFonts.poppins(
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
                future: GitHubService.futureOf(cat.name),
                builder: (context, snapshot) {
                  final firstUrl = snapshot.hasData && snapshot.data!.isNotEmpty
                      ? snapshot.data![0].thumbnailUrl
                      : null;
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(fit: StackFit.expand, children: [
                      firstUrl != null
                          ? NetImage(
                              url: firstUrl,
                              fallbackUrl: snapshot.data![0].fallbackUrl,
                              memWidth: 400)
                          : Container(
                              color: Colors.grey[850],
                              child: Icon(cat.icon,
                                  color: Colors.grey[600], size: 40)),
                      const _BottomScrim(),
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
                                          style: AppFonts.poppins(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14),
                                          overflow: TextOverflow.ellipsis))
                                ]),
                                if (snapshot.hasData)
                                  Text('${snapshot.data!.length} صورة',
                                      style: AppFonts.poppins(
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
// 12.3 🔐 المدخل الخفي للوحة التحكم
// -----------------------------------------------------------------------------
// 7 ضغطات متتالية على رقم الإصدار داخل نافذة «عن التطبيق» تفتح لوحة المشرف.
// اللوحة نفسها لا تعمل بلا توكن GitHub يُدخل يدوياً ويُحفظ على هذا الجهاز فقط،
// فحتى لو اكتشفها مستخدم آخر بالصدفة سيجدها معطّلة تماماً.
// =============================================================================
class _SecretAdminGate extends StatefulWidget {
  final Widget child;
  const _SecretAdminGate({required this.child});

  @override
  State<_SecretAdminGate> createState() => _SecretAdminGateState();
}

class _SecretAdminGateState extends State<_SecretAdminGate> {
  int _taps = 0;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  void _onTap() {
    final now = DateTime.now();
    // إعادة العد إذا تباطأ المستخدم أكثر من ثانيتين بين ضغطتين
    _taps = now.difference(_last).inSeconds > 2 ? 1 : _taps + 1;
    _last = now;

    if (_taps < 7) return;
    _taps = 0;

    // نلتقط الـ navigator قبل الإغلاق لأن context النافذة يصبح غير صالح بعده
    final navigator = Navigator.of(context);
    navigator.pop(); // إغلاق نافذة «عن التطبيق»
    navigator.push(
      MaterialPageRoute(builder: (_) => const AdminPanelScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: widget.child,
    );
  }
}

// =============================================================================
// 13. SETTINGS SCREEN
// =============================================================================
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final favCount = context.watch<FavoritesProvider>().count;
    return Scaffold(
      backgroundColor: const Color(0xFF0F1620),
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new,
                  color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context)),
          title: Text('الإعدادات',
              style: AppFonts.poppins(
                  fontWeight: FontWeight.bold, color: Colors.white))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Center(child: ResponsiveBannerAdWidget()),
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
                        style: AppFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                    Text('شاهد إعلاناً لكسب 5 عملات 🪙',
                        style: AppFonts.poppins(
                            color: Colors.grey[400], fontSize: 12))
                  ])),
            ]),
            const SizedBox(height: 12),
            Consumer<CoinsProvider>(
              builder: (context, coins, _) => Row(children: [
                Text('رصيدك الحالي: ',
                    style: AppFonts.poppins(
                        color: Colors.grey[300], fontSize: 13)),
                Text('${coins.coins} 🪙',
                    style: AppFonts.poppins(
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
                    style: AppFonts.poppins(
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
            subtitle: 'تحرير الذاكرة وإعادة تحميل الصور',
            onTap: () {
              GitHubService.clearCache();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('تم مسح الكاش ✅', style: AppFonts.poppins()),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  backgroundColor: Colors.green[700]));
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
                      style: AppFonts.poppins(
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
                    _SecretAdminGate(
                      child: Text('الإصدار 1.1.0',
                          style: AppFonts.poppins(
                              color: Colors.grey[400], fontSize: 13)),
                    ),
                    const SizedBox(height: 4),
                    Text('تطبيق خلفيات عالي الجودة',
                        style: AppFonts.poppins(
                            color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text('KASEM 2026',
                        style: AppFonts.poppins(
                            color: Colors.grey[500], fontSize: 12))
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('إغلاق',
                            style: AppFonts.poppins(color: Colors.blueAccent)))
                  ],
                ),
              );
            }),
      ]),
    );
  }
}

/// ✅ بدون BackdropFilter — كان كل عنصر في القائمة يشغّل ضباباً منفصلاً
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
      child: SolidPanel(
        padding: const EdgeInsets.all(16),
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
                    style: AppFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
                Text(subtitle,
                    style:
                        AppFonts.poppins(color: Colors.grey[400], fontSize: 12))
              ])),
          if (trailing != null) ...[trailing!, const SizedBox(width: 6)],
          const Icon(Icons.chevron_right, color: Colors.grey)
        ]),
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
            repository: 'sport',
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
// 15. BOTTOM NAV — ✅ ضباب أخف (8 بدل 20)
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
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
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
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
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
              style: AppFonts.poppins(
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
// -----------------------------------------------------------------------------
// ✅ AnimatedSwitcher كان يهدم الشاشة بالكامل عند كل تبديل تبويب (فقدان موضع
// التمرير + إعادة كل الطلبات). الآن IndexedStack «كسول»: يبني التبويب عند أول
// زيارة فقط ثم يبقيه حياً — تنقل فوري بلا إعادة تحميل.
// =============================================================================
class MainLayout extends StatefulWidget {
  const MainLayout({super.key});
  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  final Set<int> _visited = {0};

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
        await _requestInitialPermissions();
      });
    } else {
      _requestInitialPermissions();
    }
  }

  /// ✅ إذن الإشعارات فقط عند الإقلاع. إذن المعرض يُطلب عند أول تحميل صورة
  /// (وقت الحاجة) — هذا ما توصي به سياسة Google Play ويقلّل حوارات البداية.
  Future<void> _requestInitialPermissions() async {
    await NotificationService.requestPermissionAndSubscribe();
  }

  Widget _screenAt(int index) {
    switch (index) {
      case 0:
        return const HomeScreen();
      case 1:
        return const NewScreen();
      case 2:
        return const BestScreen();
      case 3:
        return const Screen169();
      default:
        return const CatalogScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    _visited.add(provider.currentIndex);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Stack(children: [
        const Positioned.fill(
            child: DecoratedBox(
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
              Color(0xFF0F0F1A),
              Color(0xFF0F2027),
              Color(0xFF1A1A2E)
            ])))),
        Positioned.fill(
          child: IndexedStack(
            index: provider.currentIndex,
            children: List.generate(
              5,
              (i) =>
                  _visited.contains(i) ? _screenAt(i) : const SizedBox.shrink(),
            ),
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

/// ✅ تهيئة Firebase والإشعارات تعمل في الخلفية بعد إقلاع الواجهة، فلا تؤخر
/// ظهور أول شاشة (كانت تُنتظر قبل runApp).
Future<void> _initFirebaseAndNotifications() async {
  try {
    await Firebase.initializeApp();
    AppLogger.success('✅ Firebase initialized');
    await NotificationService.initialize();
    AppLogger.success('✅ Notification service initialized');
  } catch (e) {
    AppLogger.error('❌ Firebase/Notification initialization failed: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ حدّ كاش الصور: الافتراضي 100 ميجابايت، وهو سبب رئيسي لقتل iOS للتطبيق
  // (jetsam) عند التمرير في أقسام فيها صور 4K. 60 ميجابايت كافية تماماً.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 60 << 20;
  PaintingBinding.instance.imageCache.maximumSize = 100;

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    AppLogger.error('❌ FlutterError: ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.error('❌ Uncaught PlatformDispatcher error: $error');
    return true;
  };

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light));

  // Firebase في الخلفية — لا يعطّل الإقلاع
  unawaited(_initFirebaseAndNotifications());
  unawaited(GitHubService.probeThumbProxy());

  // ✅ صور أول شاشة تبدأ بالتنزيل فوراً هنا، بالتوازي مع تهيئة AdMob أدناه،
  // بدل انتظار اكتمال الإقلاع كله (حتى 3 ثوانٍ) قبل أول طلب شبكة للصور.
  unawaited(_prefetchInitialWallpapers());

  // AdMob بمهلة قصوى 3 ثوانٍ حتى لا تتعطل الشاشة على شبكة بطيئة
  try {
    await AdMobManager()
        .initialize()
        .timeout(const Duration(seconds: 3), onTimeout: () {});
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
