import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';

// ─────────────────────────────────────────────────────────────────────────────
// الإعدادات الثابتة
// ─────────────────────────────────────────────────────────────────────────────
class AdminConfig {
  static const String owner = 'pcbalad2020-coder';
  static const String branch = 'main';

  /// المستودع الذي يحتوي workflow إرسال الإشعارات وملف التذكير اليومي
  static const String controlRepo = kNotifyConfigRepo;

  /// الأقسام المتاحة للرفع: الاسم المعروض ← اسم المستودع
  static const Map<String, String> repos = {
    'All Images': 'All-images',
    'Sport': 'sport',
    'Anime': 'anime_wallpapers',
    'Cars': 'cars',
    'Nature': 'nature',
    'Space': 'space',
    '16:9': 'imag-16-9',
  };

  static const String _tokenKey = 'admin_github_token';

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    return (token == null || token.isEmpty) ? null : token;
  }

  static Future<void> setToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token.trim());
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// خدمة GitHub الخاصة بالمشرف
// ─────────────────────────────────────────────────────────────────────────────
class AdminResult {
  final bool ok;
  final String message;
  const AdminResult(this.ok, this.message);
}

class AdminService {
  static Dio _dio(String token) => Dio(BaseOptions(
        baseUrl: 'https://api.github.com',
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 120),
        headers: {
          'Accept': 'application/vnd.github+json',
          'Authorization': 'Bearer $token',
          'X-GitHub-Api-Version': '2022-11-28',
          'User-Agent': 'KM2-Admin/1.0',
        },
        validateStatus: (code) => code != null && code < 500,
      ));

  /// التحقق من صلاحية التوكن
  static Future<AdminResult> verifyToken(String token) async {
    try {
      final res = await _dio(token).get('/user');
      if (res.statusCode == 200) {
        final login = res.data is Map ? res.data['login'] : null;
        return AdminResult(true, 'التوكن صالح ✅ (${login ?? 'مستخدم'})');
      }
      if (res.statusCode == 401) {
        return const AdminResult(false, 'التوكن غير صالح أو منتهي');
      }
      return AdminResult(false, 'استجابة غير متوقعة: ${res.statusCode}');
    } catch (e) {
      return AdminResult(false, 'تعذّر الاتصال: $e');
    }
  }

  /// قراءة files.json مع الـ sha اللازم للتحديث
  static Future<Map<String, dynamic>?> _readManifest(
      String token, String repo) async {
    final res = await _dio(token).get(
      '/repos/${AdminConfig.owner}/$repo/contents/files.json',
      queryParameters: {'ref': AdminConfig.branch},
    );
    if (res.statusCode != 200 || res.data is! Map) return null;

    final encoded = (res.data['content'] as String? ?? '').replaceAll('\n', '');
    final sha = res.data['sha'] as String?;
    if (sha == null) return null;

    List<String> names = [];
    try {
      final decoded = jsonDecode(utf8.decode(base64Decode(encoded)));
      if (decoded is List) {
        names = decoded.map((e) => e.toString()).toList();
      } else if (decoded is Map) {
        // ✅ صيغة الـ workflow الجديدة: {"thumbs":true,"files":[...]}
        final list = decoded['files'] as List? ?? [];
        names = list.map((e) => e.toString()).toList();
      }
    } catch (_) {}

    return {'sha': sha, 'names': names};
  }

  /// ✅ قراءة أسماء الصور الموجودة فعلياً في المستودع.
  /// ضرورية عندما لا يوجد files.json: بدونها تظن اللوحة أن المستودع فارغ
  /// فتقترح الاسم "1.jpg" وهو موجود مسبقاً → خطأ 422 sha wasn't supplied.
  static Future<List<String>> _listRepoImages(String token, String repo) async {
    try {
      final res = await _dio(token).get(
        '/repos/${AdminConfig.owner}/$repo/contents',
        queryParameters: {'ref': AdminConfig.branch, 'per_page': 1000},
      );
      if (res.statusCode != 200 || res.data is! List) return [];
      return (res.data as List)
          .where((item) => item is Map && item['type'] == 'file')
          .map((item) => item['name'].toString())
          .where((name) => _allowedExtensions.any(name.toLowerCase().endsWith))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// ترتيب رقمي ذكي: 2.jpg قبل 10.jpg
  static List<String> _sorted(List<String> names) {
    final list = [...names];
    list.sort((a, b) {
      final ai = int.tryParse(a.split('.').first);
      final bi = int.tryParse(b.split('.').first);
      if (ai != null && bi != null) return ai.compareTo(bi);
      return a.compareTo(b);
    });
    return list;
  }

  /// الامتدادات التي يقرأها التطبيق — أي اسم خارجها يُتجاهل عند العرض
  static const List<String> _allowedExtensions = [
    '.jpg',
    '.jpeg',
    '.png',
    '.webp'
  ];

  /// يقترح اسماً رقمياً تالياً حسب نمط التسمية الموجود (1.jpg, 2.jpg ...)
  static String _nextName(List<String> names, String extension) {
    int max = 0;
    for (final n in names) {
      final stem = n.split('/').last.split('.').first;
      final value = int.tryParse(stem);
      if (value != null && value > max) max = value;
    }
    return '${max + 1}$extension';
  }

  /// رفع صورة باسم تلقائي + تحديث (أو إنشاء) files.json
  static Future<AdminResult> uploadImage({
    required String token,
    required String repo,
    required List<int> bytes,
    required String extension,
  }) async {
    // ✅ حارس أساسي: رفع مصفوفة فارغة ينتج ملفاً بحجم 0 بايت على GitHub
    // يبدو ناجحاً لكنه صورة معطوبة. يحدث على iPhone حين تكون الصورة في
    // iCloud ولم تُنزَّل على الجهاز بعد (خيار Optimize iPhone Storage).
    if (bytes.isEmpty) {
      return const AdminResult(
          false,
          'الملف فارغ (0 بايت) — الصورة على iCloud ولم تُنزَّل بعد. '
          'افتحها في تطبيق الصور حتى تكتمل ثم أعد المحاولة');
    }
    if (bytes.length < 1024) {
      return AdminResult(false,
          'حجم الملف ${bytes.length} بايت فقط — يبدو تالفاً، اختر صورة أخرى');
    }

    try {
      // مصدران للأسماء: files.json + محتوى المستودع الفعلي.
      // الاعتماد على واحد فقط كان يسبب اقتراح اسم موجود مسبقاً (خطأ 422).
      final manifest = await _readManifest(token, repo);
      final manifestNames =
          (manifest?['names'] as List<String>?) ?? const <String>[];
      final repoNames = await _listRepoImages(token, repo);
      final known = <String>{...manifestNames, ...repoNames};

      final safeExtension = _allowedExtensions.contains(extension.toLowerCase())
          ? extension.toLowerCase()
          : '.jpg';

      // محاولات متعددة تحسباً لاسم محجوز لم يظهر في أي من المصدرين
      String fileName = _nextName(known.toList(), safeExtension);
      Response? upload;

      for (int attempt = 1; attempt <= 4; attempt++) {
        upload = await _dio(token).put(
          '/repos/${AdminConfig.owner}/$repo/contents/$fileName',
          data: {
            'message': 'add $fileName via admin panel',
            'content': base64Encode(bytes),
            'branch': AdminConfig.branch,
          },
        );

        // 422 = الاسم موجود بالفعل → جرّب الرقم التالي
        if (upload.statusCode == 422) {
          known.add(fileName);
          fileName = _nextName(known.toList(), safeExtension);
          continue;
        }
        break;
      }

      if (upload == null ||
          (upload.statusCode != 201 && upload.statusCode != 200)) {
        final code = upload?.statusCode;
        final msg = upload?.data is Map ? upload!.data['message'] : '';
        return AdminResult(false, 'فشل رفع الصورة ($code) $msg');
      }

      // تحديث files.json — أو إنشاؤه من الصفر إن كان مفقوداً
      final updated = _sorted({...known, fileName}.toList());
      final res = await _dio(token).put(
        '/repos/${AdminConfig.owner}/$repo/contents/files.json',
        data: {
          'message': manifest == null
              ? 'create files.json via admin panel'
              : 'update files.json ($fileName)',
          'content': base64Encode(
              utf8.encode(const JsonEncoder.withIndent('').convert(updated))),
          // sha مطلوب للتحديث فقط ويجب ألا يُرسل عند الإنشاء
          if (manifest != null) 'sha': manifest['sha'],
          'branch': AdminConfig.branch,
        },
      );

      if (res.statusCode != 200 && res.statusCode != 201) {
        final msg = res.data is Map ? res.data['message'] : '';
        return AdminResult(
            true, 'رُفعت "$fileName" ✅ لكن تحديث files.json فشل ($msg)');
      }

      return AdminResult(
          true,
          manifest == null
              ? 'تم رفع "$fileName" وإنشاء files.json بـ ${updated.length} صورة ✅'
              : 'تم رفع "$fileName" ✅ (${updated.length} صورة في القسم)');
    } catch (e) {
      return AdminResult(false, 'خطأ أثناء الرفع: $e');
    }
  }

  // ── 📢 الشريط الإعلاني (KM2MY) ───────────────────────────────────────────

  /// قراءة promo.json الحالي مع sha اللازم للتحديث (null إن لم يوجد)
  static Future<Map<String, dynamic>?> readPromo(String token) async {
    try {
      final res = await _dio(token).get(
        '/repos/${AdminConfig.owner}/$kPromoRepo/contents/promo.json',
        queryParameters: {'ref': AdminConfig.branch},
      );
      if (res.statusCode != 200 || res.data is! Map) return null;
      final sha = res.data['sha'] as String?;
      final encoded =
          (res.data['content'] as String? ?? '').replaceAll('\n', '');
      if (sha == null) return null;
      final decoded = jsonDecode(utf8.decode(base64Decode(encoded)));
      if (decoded is! Map) return null;
      return {'sha': sha, 'data': Map<String, dynamic>.from(decoded)};
    } catch (e) {
      return null;
    }
  }

  /// نشر الشريط: يرفع الصورة (إن وُجدت) ثم يكتب promo.json
  static Future<AdminResult> publishPromo({
    required String token,
    required bool active,
    String title = '',
    String body = '',
    String link = '',
    DateTime? endAtUtc,
    List<int>? imageBytes,
    String imageExtension = '.jpg',
    double imageAspectRatio = 0,
    String? keepImage,
    double keepRatio = 0,
  }) async {
    try {
      String imageName = keepImage ?? '';
      double ratio = imageAspectRatio > 0 ? imageAspectRatio : keepRatio;

      // 1) رفع صورة جديدة إن اختيرت
      if (imageBytes != null && imageBytes.isNotEmpty) {
        if (imageBytes.length < 1024) {
          return AdminResult(
              false, 'حجم الصورة ${imageBytes.length} بايت فقط — يبدو تالفاً');
        }
        final ext = _allowedExtensions.contains(imageExtension.toLowerCase())
            ? imageExtension.toLowerCase()
            : '.jpg';
        // اسم فريد: إعادة استخدام نفس الاسم تُبقي الصورة القديمة في كاش
        // الشبكة لساعات فيرى المستخدمون إعلاناً منتهياً
        imageName = 'promo_${DateTime.now().millisecondsSinceEpoch}$ext';
        ratio = imageAspectRatio;

        final up = await _dio(token).put(
          '/repos/${AdminConfig.owner}/$kPromoRepo/contents/$imageName',
          data: {
            'message': 'add promo image',
            'content': base64Encode(imageBytes),
            'branch': AdminConfig.branch,
          },
        );
        if (up.statusCode != 201 && up.statusCode != 200) {
          final msg = up.data is Map ? up.data['message'] : '';
          return AdminResult(
              false, 'فشل رفع صورة الشريط (${up.statusCode}) $msg');
        }
      }

      // 2) كتابة promo.json
      final existing = await readPromo(token);
      final payload = <String, dynamic>{
        'active': active,
        if (imageName.isNotEmpty) 'image': imageName,
        if (title.trim().isNotEmpty) 'title': title.trim(),
        if (body.trim().isNotEmpty) 'body': body.trim(),
        if (link.trim().isNotEmpty) 'link': link.trim(),
        if (endAtUtc != null)
          'endAt': '${endAtUtc.toIso8601String().split('.').first}Z',
        if (ratio > 0) 'aspectRatio': double.parse(ratio.toStringAsFixed(4)),
      };

      final res = await _dio(token).put(
        '/repos/${AdminConfig.owner}/$kPromoRepo/contents/promo.json',
        data: {
          'message': active ? 'publish promo' : 'disable promo',
          'content': base64Encode(
              utf8.encode(const JsonEncoder.withIndent('  ').convert(payload))),
          if (existing != null) 'sha': existing['sha'],
          'branch': AdminConfig.branch,
        },
      );

      if (res.statusCode != 200 && res.statusCode != 201) {
        final msg = res.data is Map ? res.data['message'] : '';
        return AdminResult(false, 'فشل حفظ الشريط (${res.statusCode}) $msg');
      }

      GitHubService.clearPromoCache();
      return AdminResult(
          true,
          active
              ? 'نُشر الشريط ✅ — اضغط «عرض في التطبيق» لرؤيته فوراً'
              : 'أُوقف الشريط ✅ — لن يظهر لأي مستخدم');
    } catch (e) {
      return AdminResult(false, 'خطأ أثناء نشر الشريط: $e');
    }
  }

  /// إطلاق حدث في GitHub ليتولى الـ Action إرسال الإشعار
  static Future<AdminResult> sendNotification({
    required String token,
    required String title,
    required String body,
    String? category,
  }) async {
    try {
      final res = await _dio(token).post(
        '/repos/${AdminConfig.owner}/${AdminConfig.controlRepo}/dispatches',
        data: {
          'event_type': 'send_notification',
          'client_payload': {
            'title': title,
            'body': body,
            if (category != null && category.isNotEmpty) 'category': category,
          },
        },
      );

      if (res.statusCode == 204) {
        return const AdminResult(
            true, 'أُرسل الطلب ✅ — يصل الإشعار خلال ~30 ثانية');
      }
      if (res.statusCode == 404) {
        return const AdminResult(false,
            'المستودع ${AdminConfig.controlRepo} غير موجود أو التوكن بلا صلاحية عليه');
      }
      final msg = res.data is Map ? res.data['message'] : '';
      return AdminResult(false, 'فشل الإرسال (${res.statusCode}) $msg');
    } catch (e) {
      return AdminResult(false, 'خطأ أثناء الإرسال: $e');
    }
  }

  // ── ⏰ التذكير اليومي (km2-config) ───────────────────────────────────────

  /// قراءة daily_reminder.json الحالي مع sha اللازم للتحديث (null إن لم يوجد)
  static Future<Map<String, dynamic>?> readDailyReminder(String token) async {
    try {
      final res = await _dio(token).get(
        '/repos/${AdminConfig.owner}/$kNotifyConfigRepo/contents/daily_reminder.json',
        queryParameters: {'ref': AdminConfig.branch},
      );
      if (res.statusCode != 200 || res.data is! Map) return null;
      final sha = res.data['sha'] as String?;
      final encoded =
          (res.data['content'] as String? ?? '').replaceAll('\n', '');
      if (sha == null) return null;
      final decoded = jsonDecode(utf8.decode(base64Decode(encoded)));
      if (decoded is! Map) return null;
      return {'sha': sha, 'data': Map<String, dynamic>.from(decoded)};
    } catch (e) {
      return null;
    }
  }

  /// يكتب daily_reminder.json — يُنشئه إن لم يكن موجوداً، أو يحدّثه إن وُجد
  static Future<AdminResult> publishDailyReminder({
    required String token,
    required DailyReminderModel config,
  }) async {
    try {
      final existing = await readDailyReminder(token);
      final res = await _dio(token).put(
        '/repos/${AdminConfig.owner}/$kNotifyConfigRepo/contents/daily_reminder.json',
        data: {
          'message': existing == null
              ? 'create daily_reminder.json via admin panel'
              : 'update daily_reminder.json via admin panel',
          'content': base64Encode(utf8.encode(
              const JsonEncoder.withIndent('  ').convert(config.toJson()))),
          if (existing != null) 'sha': existing['sha'],
          'branch': AdminConfig.branch,
        },
      );

      if (res.statusCode != 200 && res.statusCode != 201) {
        final msg = res.data is Map ? res.data['message'] : '';
        return AdminResult(false, 'فشل حفظ التذكير اليومي (${res.statusCode}) $msg');
      }

      GitHubService.clearDailyReminderCache();
      return AdminResult(
          true,
          config.enabled
              ? 'حُفظ التذكير اليومي ✅ — سيصل للمستخدمين خلال يوم أو يومين'
              : 'عُطّل التذكير اليومي ✅ — لن يُرسل بعد الآن');
    } catch (e) {
      return AdminResult(false, 'خطأ أثناء حفظ التذكير اليومي: $e');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// الواجهة
// ─────────────────────────────────────────────────────────────────────────────
class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  static const Color _bg = Color(0xFF0F1620);
  static const Color _panel = Color(0xFF16202C);

  String? _token;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final token = await AdminConfig.getToken();
    if (!mounted) return;
    setState(() {
      _token = token;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 4,
        child: Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: _panel,
            elevation: 0,
            title: const Text('لوحة التحكم',
                style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.bold)),
            bottom: const TabBar(
              isScrollable: true,
              indicatorColor: Colors.blueAccent,
              labelColor: Colors.blueAccent,
              unselectedLabelColor: Colors.grey,
              tabs: [
                Tab(icon: Icon(Icons.cloud_upload_outlined), text: 'رفع صورة'),
                Tab(icon: Icon(Icons.campaign_outlined), text: 'الشريط'),
                Tab(
                    icon: Icon(Icons.notifications_active_outlined),
                    text: 'إشعار'),
                Tab(icon: Icon(Icons.key_outlined), text: 'المفتاح'),
              ],
            ),
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  children: [
                    _UploadTab(token: _token),
                    _PromoTab(token: _token),
                    _NotifyTab(token: _token),
                    _TokenTab(
                      token: _token,
                      onChanged: (t) => setState(() => _token = t),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// إعادة بناء واجهة التطبيق من الصفر لتظهر التغييرات فوراً بلا إعادة تشغيل
void _openAppFresh(BuildContext context) {
  Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const MainLayout()),
    (route) => false,
  );
}

// ── تبويب رفع الصورة ─────────────────────────────────────────────────────────
class _UploadTab extends StatefulWidget {
  final String? token;
  const _UploadTab({required this.token});

  @override
  State<_UploadTab> createState() => _UploadTabState();
}

class _UploadTabState extends State<_UploadTab> {
  String _repoLabel = AdminConfig.repos.keys.first;
  XFile? _picked;
  List<int>? _bytes;
  bool _busy = false;
  String? _status;
  bool _statusOk = false;

  Future<void> _pick() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;

      if (bytes.isEmpty) {
        setState(() {
          _picked = null;
          _bytes = null;
          _statusOk = false;
          _status = 'تعذّرت قراءة الصورة (0 بايت) — غالباً لأنها مخزّنة في '
              'iCloud ولم تُنزَّل. افتحها في تطبيق الصور وانتظر اكتمالها '
              'ثم أعد المحاولة';
        });
        return;
      }

      setState(() {
        _picked = file;
        _bytes = bytes;
        _statusOk = false;
        _status = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusOk = false;
          _status = 'تعذّر اختيار الصورة: $e';
        });
      }
    }
  }

  Future<void> _upload() async {
    final token = widget.token;
    if (token == null) {
      setState(() {
        _statusOk = false;
        _status = 'أدخل مفتاح GitHub أولاً من تبويب «المفتاح»';
      });
      return;
    }
    if (_bytes == null) {
      setState(() {
        _statusOk = false;
        _status = 'اختر صورة أولاً';
      });
      return;
    }

    setState(() {
      _busy = true;
      _status = null;
    });

    final name = _picked?.name ?? 'image.jpg';
    final dot = name.lastIndexOf('.');
    final ext = dot > 0 ? name.substring(dot).toLowerCase() : '.jpg';

    final result = await AdminService.uploadImage(
      token: token,
      repo: AdminConfig.repos[_repoLabel]!,
      bytes: _bytes!,
      extension: ext,
    );

    // ✅ مسح الكاش فور النجاح حتى تُقرأ القائمة الجديدة بدل المخزّنة (6 ساعات)
    if (result.ok) GitHubService.clearCache();

    if (!mounted) return;
    setState(() {
      _busy = false;
      _statusOk = result.ok;
      _status = result.message;
      if (result.ok) {
        _picked = null;
        _bytes = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _AdminPanelBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('القسم',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _repoLabel,
                dropdownColor: const Color(0xFF1A2533),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                items: AdminConfig.repos.keys
                    .map((label) => DropdownMenuItem(
                        value: label,
                        child: Text(label,
                            style: const TextStyle(color: Colors.white))))
                    .toList(),
                onChanged: (v) => setState(() => _repoLabel = v ?? _repoLabel),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _AdminPanelBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_picked != null) ...[
                Text('الصورة المختارة: ${_picked!.name}',
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                    'الحجم: ${((_bytes?.length ?? 0) / 1024 / 1024).toStringAsFixed(2)} ميجابايت',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                const SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(_picked == null ? 'اختر صورة' : 'تغيير الصورة'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed:
              (_busy || _bytes == null || _bytes!.isEmpty) ? null : _upload,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.cloud_upload),
          label: Text(_busy ? 'جاري الرفع...' : 'رفع الصورة'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        if (_status != null) ...[
          const SizedBox(height: 16),
          _StatusBox(ok: _statusOk, message: _status!),
        ],
        if (_statusOk && _status != null) ...[
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => _openAppFresh(context),
            icon: const Icon(Icons.visibility),
            label: const Text('عرض الصورة في التطبيق الآن'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
        const SizedBox(height: 16),
        const _HintBox(text: 'مرحبا بك في لوحة التحكم .\n'),
      ],
    );
  }
}

// ── تبويب الشريط الإعلاني ────────────────────────────────────────────────────
class _PromoTab extends StatefulWidget {
  final String? token;
  const _PromoTab({required this.token});

  @override
  State<_PromoTab> createState() => _PromoTabState();
}

class _PromoTabState extends State<_PromoTab> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _bodyCtrl = TextEditingController();
  final TextEditingController _linkCtrl = TextEditingController();

  XFile? _picked;
  List<int>? _bytes;
  double _ratio = 0; // نسبة أبعاد الصورة الجديدة
  double _keepRatio = 0; // نسبة الصورة المحفوظة سابقاً
  String? _keepImage; // اسم الصورة الحالية إن لم تُغيَّر
  int? _hours = 24; // مدة العرض بالساعات (null = بلا انتهاء)
  bool _busy = false;
  bool _loading = true;
  bool _currentlyActive = false;
  String? _status;
  bool _statusOk = false;

  static const List<int?> _durations = [1, 6, 24, 72, 168, null];
  static const List<String> _durationLabels = [
    'ساعة',
    '6 ساعات',
    'يوم',
    '3 أيام',
    'أسبوع',
    'بلا انتهاء'
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _linkCtrl.dispose();
    super.dispose();
  }

  /// يقرأ الإعلان الحالي فتعدّله بدل كتابته من الصفر
  Future<void> _loadCurrent() async {
    final token = widget.token;
    if (token == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final current = await AdminService.readPromo(token);
    if (!mounted) return;
    setState(() {
      _loading = false;
      final data = current?['data'] as Map<String, dynamic>?;
      if (data == null) return;
      _currentlyActive = data['active'] == true;
      _titleCtrl.text = data['title'] as String? ?? '';
      _bodyCtrl.text = data['body'] as String? ?? '';
      _linkCtrl.text = data['link'] as String? ?? '';
      final img = data['image'] as String? ?? '';
      if (img.isNotEmpty && !img.startsWith('http')) _keepImage = img;
      _keepRatio = (data['aspectRatio'] as num?)?.toDouble() ?? 0;
    });
  }

  Future<void> _pick() async {
    try {
      final file = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 92);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;

      if (bytes.isEmpty) {
        setState(() {
          _statusOk = false;
          _status = 'تعذّرت قراءة الصورة (0 بايت) — قد تكون مخزّنة في iCloud. '
              'افتحها في تطبيق الصور حتى تكتمل ثم أعد المحاولة';
        });
        return;
      }

      // ✅ قياس النسبة هنا وكتابتها في promo.json: يعرف التطبيق الارتفاع
      // الصحيح فوراً بلا انتظار تحميل الصورة ولا قفزة في التخطيط
      double ratio = 0;
      try {
        final decoded = await decodeImageFromList(Uint8List.fromList(bytes));
        if (decoded.height > 0) ratio = decoded.width / decoded.height;
      } catch (_) {}

      setState(() {
        _picked = file;
        _bytes = bytes;
        _ratio = ratio;
        _status = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusOk = false;
          _status = 'تعذّر اختيار الصورة: $e';
        });
      }
    }
  }

  void _removeImage() {
    setState(() {
      _picked = null;
      _bytes = null;
      _ratio = 0;
      _keepImage = null;
      _keepRatio = 0;
    });
  }

  Future<void> _publish({required bool active}) async {
    final token = widget.token;
    if (token == null) {
      setState(() {
        _statusOk = false;
        _status = 'أدخل مفتاح GitHub أولاً من تبويب «المفتاح»';
      });
      return;
    }

    if (active &&
        _bytes == null &&
        _keepImage == null &&
        _titleCtrl.text.trim().isEmpty &&
        _bodyCtrl.text.trim().isEmpty) {
      setState(() {
        _statusOk = false;
        _status = 'أضف صورة أو نصاً على الأقل';
      });
      return;
    }

    setState(() {
      _busy = true;
      _status = null;
    });

    final name = _picked?.name ?? 'image.jpg';
    final dot = name.lastIndexOf('.');
    final ext = dot > 0 ? name.substring(dot).toLowerCase() : '.jpg';

    final result = await AdminService.publishPromo(
      token: token,
      active: active,
      title: _titleCtrl.text,
      body: _bodyCtrl.text,
      link: _linkCtrl.text,
      endAtUtc: _hours == null
          ? null
          : DateTime.now().toUtc().add(Duration(hours: _hours!)),
      imageBytes: _bytes,
      imageExtension: ext,
      imageAspectRatio: _ratio,
      keepImage: _keepImage,
      keepRatio: _keepRatio,
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _statusOk = result.ok;
      _status = result.message;
      if (result.ok) {
        _currentlyActive = active;
        if (_picked != null) {
          // صارت محفوظة على الخادم باسم جديد
          _keepImage = null;
          _keepRatio = _ratio;
          _picked = null;
          _bytes = null;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final hasImage = _bytes != null || _keepImage != null;
    final previewRatio =
        _ratio > 0 ? _ratio : (_keepRatio > 0 ? _keepRatio : 16 / 7);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // حالة الشريط الحالية
        _AdminPanelBox(
          child: Row(children: [
            Icon(_currentlyActive ? Icons.campaign : Icons.campaign_outlined,
                color: _currentlyActive ? Colors.green : Colors.grey),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _currentlyActive
                    ? 'الشريط نشط حالياً في التطبيق'
                    : 'الشريط متوقف — لا يظهر لأحد',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),

        // الصورة + معاينة بالمقاس النهائي
        _AdminPanelBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('الصورة (اختيارية)',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 10),
              if (_bytes != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AspectRatio(
                    aspectRatio: previewRatio.clamp(0.6, 4.0),
                    child: Image.memory(Uint8List.fromList(_bytes!),
                        fit: BoxFit.cover),
                  ),
                )
              else if (_keepImage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    const Icon(Icons.image_outlined,
                        color: Colors.blueAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('الصورة الحالية محفوظة',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                    ),
                  ]),
                ),
              if (hasImage) const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _pick,
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: Text(hasImage ? 'تغيير' : 'اختر صورة'),
                  ),
                ),
                if (hasImage) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _busy ? null : _removeImage,
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.redAccent),
                    tooltip: 'إزالة الصورة',
                  ),
                ],
              ]),
              if (_ratio > 0) ...[
                const SizedBox(height: 8),
                Text(
                    'النسبة ${_ratio.toStringAsFixed(2)} — ارتفاع الشريط '
                    'سيطابق صورتك تماماً بلا قصّ',
                    style: TextStyle(color: Colors.grey[500], fontSize: 11)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // النصوص
        _AdminPanelBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titleCtrl,
                maxLength: 40,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  labelText: 'العنوان (اختياري)',
                ),
              ),
              TextField(
                controller: _bodyCtrl,
                maxLines: 2,
                maxLength: 120,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  labelText: 'النص (اختياري)',
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _linkCtrl,
                keyboardType: TextInputType.url,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  labelText: 'رابط عند الضغط (اختياري)',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // مدة العرض
        _AdminPanelBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('مدة العرض (تبدأ من لحظة النشر)',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(_durations.length, (i) {
                  final selected = _hours == _durations[i];
                  return GestureDetector(
                    onTap: () => setState(() => _hours = _durations[i]),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.blueAccent.withValues(alpha: 0.25)
                            : const Color(0xFF1A2533),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: selected
                                ? Colors.blueAccent
                                : const Color(0x1FFFFFFF)),
                      ),
                      child: Text(_durationLabels[i],
                          style: TextStyle(
                              color: selected ? Colors.blueAccent : Colors.grey,
                              fontSize: 12.5,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.normal)),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        ElevatedButton.icon(
          onPressed: _busy ? null : () => _publish(active: true),
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.campaign),
          label: Text(_busy ? 'جاري النشر...' : 'نشر الشريط'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _publish(active: false),
          icon: const Icon(Icons.visibility_off_outlined,
              color: Colors.redAccent),
          label: const Text('إيقاف الشريط الآن',
              style: TextStyle(color: Colors.redAccent)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.redAccent),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        if (_status != null) ...[
          const SizedBox(height: 16),
          _StatusBox(ok: _statusOk, message: _status!),
        ],
        if (_statusOk && _status != null) ...[
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => _openAppFresh(context),
            icon: const Icon(Icons.visibility),
            label: const Text('عرض في التطبيق الآن'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
        const SizedBox(height: 16),
        const _HintBox(
          text: 'الشريط يظهر فوق السلايدر في الشاشة الرئيسية، وارتفاعه يطابق '
              'مقاس صورتك تماماً بلا قصّ.\n\n'
              '«إيقاف الشريط» يخفيه فوراً عن الجميع بلا حذف، فيمكنك إعادة '
              'نشره لاحقاً بنفس المحتوى.',
        ),
      ],
    );
  }
}

// ── تبويب الإشعارات ──────────────────────────────────────────────────────────
class _NotifyTab extends StatefulWidget {
  final String? token;
  const _NotifyTab({required this.token});

  @override
  State<_NotifyTab> createState() => _NotifyTabState();
}

class _NotifyTabState extends State<_NotifyTab> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _bodyCtrl = TextEditingController();
  String? _category;
  bool _busy = false;
  String? _status;
  bool _statusOk = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final token = widget.token;
    if (token == null) {
      setState(() {
        _statusOk = false;
        _status = 'أدخل مفتاح GitHub أولاً من تبويب «المفتاح»';
      });
      return;
    }
    if (_titleCtrl.text.trim().isEmpty || _bodyCtrl.text.trim().isEmpty) {
      setState(() {
        _statusOk = false;
        _status = 'العنوان والنص مطلوبان';
      });
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1A2533),
            title: const Text('تأكيد الإرسال',
                style: TextStyle(color: Colors.white)),
            content: Text(
                'سيصل هذا الإشعار إلى جميع المستخدمين ولا يمكن التراجع عنه.\n\n'
                '«${_titleCtrl.text.trim()}»',
                style: TextStyle(color: Colors.grey[400])),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('إلغاء')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('إرسال',
                      style: TextStyle(color: Colors.redAccent))),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;

    setState(() {
      _busy = true;
      _status = null;
    });

    final result = await AdminService.sendNotification(
      token: token,
      title: _titleCtrl.text.trim(),
      body: _bodyCtrl.text.trim(),
      category: _category,
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _statusOk = result.ok;
      _status = result.message;
      if (result.ok) {
        _titleCtrl.clear();
        _bodyCtrl.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _AdminPanelBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titleCtrl,
                maxLength: 60,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'عنوان الإشعار',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _bodyCtrl,
                maxLines: 3,
                maxLength: 160,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'نص الإشعار',
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _category,
                dropdownColor: const Color(0xFF1A2533),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  labelText: 'يفتح قسماً عند الضغط (اختياري)',
                ),
                items: [
                  const DropdownMenuItem<String>(
                      value: null,
                      child:
                          Text('بدون', style: TextStyle(color: Colors.white))),
                  ...AdminConfig.repos.keys.map((label) => DropdownMenuItem(
                      value: label,
                      child: Text(label,
                          style: const TextStyle(color: Colors.white)))),
                ],
                onChanged: (v) => setState(() => _category = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _busy ? null : _send,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send),
          label: Text(_busy ? 'جاري الإرسال...' : 'إرسال للجميع'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        if (_status != null) ...[
          const SizedBox(height: 16),
          _StatusBox(ok: _statusOk, message: _status!),
        ],
        const Divider(height: 40, color: Colors.white24),
        _DailyReminderCard(token: widget.token),
        const SizedBox(height: 16),
        const _HintBox(
            text:
                '                       -----------------  KASEM  ------------------- '),
      ],
    );
  }
}

// ── التذكير اليومي التلقائي (12 ظهراً و10 مساءً) ────────────────────────────
// إشعار محلي يُجدوَل داخل كل جهاز فور فتح التطبيق (main.dart)، مستقل تماماً
// عن إشعار الإرسال اليدوي أعلاه. هذا القسم يتحكم فقط بنصّه وتفعيله عبر ملف
// daily_reminder.json في مستودع km2-config — يقرؤه كل جهاز عند إقلاعه.
class _DailyReminderCard extends StatefulWidget {
  final String? token;
  const _DailyReminderCard({required this.token});

  @override
  State<_DailyReminderCard> createState() => _DailyReminderCardState();
}

class _DailyReminderCardState extends State<_DailyReminderCard> {
  final TextEditingController _noonTitleCtrl = TextEditingController();
  final TextEditingController _noonBodyCtrl = TextEditingController();
  final TextEditingController _nightTitleCtrl = TextEditingController();
  final TextEditingController _nightBodyCtrl = TextEditingController();
  bool _enabled = true;
  bool _loading = true;
  bool _busy = false;
  String? _status;
  bool _statusOk = false;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  @override
  void dispose() {
    _noonTitleCtrl.dispose();
    _noonBodyCtrl.dispose();
    _nightTitleCtrl.dispose();
    _nightBodyCtrl.dispose();
    super.dispose();
  }

  void _fill(DailyReminderModel config) {
    _enabled = config.enabled;
    _noonTitleCtrl.text = config.noonTitle;
    _noonBodyCtrl.text = config.noonBody;
    _nightTitleCtrl.text = config.nightTitle;
    _nightBodyCtrl.text = config.nightBody;
  }

  Future<void> _loadCurrent() async {
    final token = widget.token;
    if (token == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _fill(DailyReminderModel.defaults);
        });
      }
      return;
    }
    final current = await AdminService.readDailyReminder(token);
    if (!mounted) return;
    setState(() {
      _loading = false;
      final data = current?['data'] as Map<String, dynamic>?;
      _fill(data == null
          ? DailyReminderModel.defaults
          : DailyReminderModel.fromJson(data));
    });
  }

  Future<void> _save() async {
    final token = widget.token;
    if (token == null) {
      setState(() {
        _statusOk = false;
        _status = 'أدخل مفتاح GitHub أولاً من تبويب «المفتاح»';
      });
      return;
    }
    if (_noonTitleCtrl.text.trim().isEmpty ||
        _noonBodyCtrl.text.trim().isEmpty ||
        _nightTitleCtrl.text.trim().isEmpty ||
        _nightBodyCtrl.text.trim().isEmpty) {
      setState(() {
        _statusOk = false;
        _status = 'كل الحقول الأربعة مطلوبة';
      });
      return;
    }

    setState(() {
      _busy = true;
      _status = null;
    });

    final result = await AdminService.publishDailyReminder(
      token: token,
      config: DailyReminderModel(
        enabled: _enabled,
        noonTitle: _noonTitleCtrl.text.trim(),
        noonBody: _noonBodyCtrl.text.trim(),
        nightTitle: _nightTitleCtrl.text.trim(),
        nightBody: _nightBodyCtrl.text.trim(),
      ),
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _statusOk = result.ok;
      _status = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator()));
    }
    return _AdminPanelBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.alarm_outlined, color: Colors.blueAccent),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('التذكير اليومي التلقائي (12 ظهراً و10 مساءً)',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              Switch(
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
                activeThumbColor: Colors.blueAccent,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              'يُرسل تلقائياً من كل جهاز (بلا حاجة لضغط زر) بتوقيت المستخدم '
              'المحلي — يعمل على أندرويد وآيفون معاً، ومستقل عن الإشعار '
              'اليدوي أعلاه.',
              style: TextStyle(color: Colors.grey[400], fontSize: 12)),
          const SizedBox(height: 16),
          const Text('☀️ إشعار الظهر', style: TextStyle(color: Colors.blueAccent)),
          const SizedBox(height: 8),
          TextField(
            controller: _noonTitleCtrl,
            maxLength: 60,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
                border: OutlineInputBorder(), labelText: 'عنوان إشعار الظهر'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _noonBodyCtrl,
            maxLines: 2,
            maxLength: 160,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
                border: OutlineInputBorder(), labelText: 'نص إشعار الظهر'),
          ),
          const SizedBox(height: 16),
          const Text('🌙 إشعار المساء', style: TextStyle(color: Colors.blueAccent)),
          const SizedBox(height: 8),
          TextField(
            controller: _nightTitleCtrl,
            maxLength: 60,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'عنوان إشعار المساء'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nightBodyCtrl,
            maxLines: 2,
            maxLength: 160,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
                border: OutlineInputBorder(), labelText: 'نص إشعار المساء'),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: Text(_busy ? 'جاري الحفظ...' : 'حفظ التذكير اليومي'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          if (_status != null) ...[
            const SizedBox(height: 16),
            _StatusBox(ok: _statusOk, message: _status!),
          ],
        ],
      ),
    );
  }
}

// ── تبويب المفتاح ────────────────────────────────────────────────────────────
class _TokenTab extends StatefulWidget {
  final String? token;
  final ValueChanged<String?> onChanged;
  const _TokenTab({required this.token, required this.onChanged});

  @override
  State<_TokenTab> createState() => _TokenTabState();
}

class _TokenTabState extends State<_TokenTab> {
  final TextEditingController _ctrl = TextEditingController();
  bool _busy = false;
  String? _status;
  bool _statusOk = false;
  bool _obscure = true;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final token = _ctrl.text.trim();
    if (token.isEmpty) {
      setState(() {
        _statusOk = false;
        _status = 'ألصق التوكن أولاً';
      });
      return;
    }

    setState(() {
      _busy = true;
      _status = null;
    });

    final result = await AdminService.verifyToken(token);
    if (result.ok) {
      await AdminConfig.setToken(token);
      widget.onChanged(token);
      _ctrl.clear();
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _statusOk = result.ok;
      _status = result.message;
    });
  }

  Future<void> _remove() async {
    await AdminConfig.clearToken();
    widget.onChanged(null);
    if (!mounted) return;
    setState(() {
      _statusOk = true;
      _status = 'حُذف التوكن من هذا الجهاز';
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasToken = widget.token != null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _AdminPanelBox(
          child: Row(children: [
            Icon(hasToken ? Icons.verified_user : Icons.gpp_maybe,
                color: hasToken ? Colors.green : Colors.orange),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hasToken
                    ? 'التوكن محفوظ على هذا الجهاز'
                    : 'لا يوجد توكن — اللوحة معطّلة',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        _AdminPanelBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _ctrl,
                obscureText: _obscure,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'GitHub Personal Access Token',
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save),
                label: Text(_busy ? 'جاري التحقق...' : 'تحقق واحفظ'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                ),
              ),
              if (hasToken) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _remove,
                  icon:
                      const Icon(Icons.delete_outline, color: Colors.redAccent),
                  label: const Text('حذف التوكن من الجهاز',
                      style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ],
          ),
        ),
        if (_status != null) ...[
          const SizedBox(height: 16),
          _StatusBox(ok: _statusOk, message: _status!),
        ],
        const SizedBox(height: 16),
        const _HintBox(
            text:
                '                     -----------------  KASEM  ------------------- '),
      ],
    );
  }
}

// ── عناصر مساعدة ─────────────────────────────────────────────────────────────
class _AdminPanelBox extends StatelessWidget {
  final Widget child;
  const _AdminPanelBox({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16202C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: child,
    );
  }
}

class _StatusBox extends StatelessWidget {
  final bool ok;
  final String message;
  const _StatusBox({required this.ok, required this.message});

  @override
  Widget build(BuildContext context) {
    final color = ok ? Colors.green : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        Icon(ok ? Icons.check_circle : Icons.error_outline, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message,
              style: const TextStyle(color: Colors.white, fontSize: 13)),
        ),
      ]),
    );
  }
}

class _HintBox extends StatelessWidget {
  final String text;
  const _HintBox({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blueAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.25)),
      ),
      child: Text(text,
          style: TextStyle(color: Colors.grey[400], fontSize: 12, height: 1.6)),
    );
  }
}
