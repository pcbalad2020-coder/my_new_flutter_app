# 📚 المراجع والموارد الكاملة

## 🔗 الروابط الرسمية

### CodeMagic
- 🌐 [codemagic.io](https://codemagic.io)
- 📖 [CodeMagic Documentation](https://docs.codemagic.io)
- 📖 [iOS Build & Release](https://docs.codemagic.io/flutter-guide/building-for-ios/)
- 📖 [iOS Code Signing](https://docs.codemagic.io/ios-code-signing/)

### Apple Developer
- 🍎 [Developer Account](https://developer.apple.com)
- 📖 [App Store Connect](https://appstoreconnect.apple.com)
- 📖 [Certificate Guide](https://developer.apple.com/support/certificates/)

### Flutter
- 🌐 [flutter.dev](https://flutter.dev)
- 📖 [iOS Deployment](https://flutter.dev/docs/deployment/ios)
- 📖 [Building iOS Apps](https://flutter.dev/docs/platform-integration/ios/)

---

## 📝 ملفات المشروع المهمة

```
wallpaper/
├── codemagic.yaml                     # ⭐ تكوين البناء على CodeMagic
├── QUICK_START_IPA.md                 # ⭐ خطوات سريعة
├── IPA_EXPORT_GUIDE.md                # ⭐ دليل كامل
├── TROUBLESHOOTING_iOS.md             # ⭐ حل المشاكل
├── pubspec.yaml                       # إصدارات المكتبات
├── analysis_options.yaml
└── ios/
    ├── Runner/
    │   ├── Info.plist                 # ⭐ الأذونات و Bundle ID
    │   ├── AppDelegate.swift
    │   └── Runner-Bridging-Header.h
    ├── Podfile                        # ⭐ إعدادات CocoaPods
    ├── ExportOptions.plist            # ⭐ خيارات التصدير
    └── Runner.xcworkspace/
```

---

## 🔑 البيانات المطلوبة

### 1. من Apple Developer

```
✅ Team ID:              XXXXXXXXXX
✅ Bundle ID:            com.example.wallpaper
✅ App ID:               Wallpaper App
✅ Certificate:          Distribution Certificate (.cer)
✅ Private Key:          Private Key (.p12)
✅ Provisioning:         App Store Provisioning Profile
```

### 2. من Project

```
✅ Flutter Version:      3.0.0+
✅ iOS Min Deployment:   13.0
✅ Xcode Version:        14.0+
✅ CocoaPods:            Latest
```

---

## 🛠️ الأدوات المطلوبة

**Windows PowerShell:**
```powershell
# تحقق من التثبيت:

# Flutter
flutter --version

# CocoaPods
pod --version
```

**Mac/Linux:**
```bash
# تحقق من التثبيت:

# Flutter
flutter --version

# Xcode (على Mac فقط)
xcode-select --print-path

# CocoaPods
pod --version

# Ruby (عادة مثبت)
ruby --version
```

---

## 🎯 خطوات التصدير المختصرة

### الطريقة 1: CodeMagic (الموصى به للـ Windows)

```
1. انضم إلى codemagic.io
2. ربط GitHub
3. أضف بيانات التوقيع
4. ابدأ البناء
5. احصل على IPA
```

### الطريقة 2: محلي على Mac (للمتقدمين)

```bash
# تنظيف
flutter clean

# البناء
flutter build ios --release

# التصدير
cd ios
xcodebuild -workspace Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -archivePath build/Runner.xcarchive \
  archive

xcodebuild -exportArchive \
  -archivePath build/Runner.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/ipa
```

---

## ⚙️ إعدادات مهمة

### `pubspec.yaml`
```yaml
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'
```

### `ios/Podfile`
```ruby
platform :ios, '13.0'
```

### `ios/Runner/Info.plist`
```xml
<key>CFBundleIdentifier</key>
<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>الوصول للصور</string>
```

### `ios/ExportOptions.plist`
```xml
<key>method</key>
<string>app-store</string>

<key>teamID</key>
<string>YOUR_TEAM_ID</string>
```

---

## 🔍 الفحوصات المطلوبة

```bash
# 1. فحص Flutter
flutter doctor -v

# 2. تحليل الكود
flutter analyze

# 3. تشغيل الاختبارات
flutter test

# 4. بناء مبدئي
flutter build ios --release --no-codesign

# 5. فحص CocoaPods
cd ios && pod check && pod install --repo-update
```

---

## 📊 مقارنة الخيارات

| الخيار | الإيجابيات | السلبيات |
|-------|-----------|---------|
| **CodeMagic** | سهل، محدث، آلي | قد يحتاج دفع |
| **Mac محلي** | كامل التحكم | يحتاج Mac |
| **GitHub Actions** | مجاني | معقد للمبتدئين |
| **Fastlane** | احترافي | منحنى تعلم |

---

## 🚨 الأخطاء الشائعة والحلول

| الخطأ | السبب | الحل |
|------|-----|------|
| Pod install failed | مكتبات غير متوافقة | `pod install --repo-update` |
| Certificate expired | الشهادة منتهية | جدّد من Apple |
| Provisioning mismatch | عدم التطابق | استخدم نفس Bundle ID |
| Bitcode error | إعدادات Bitcode | عطّل Bitcode |
| Memory error | بناء ثقيل | نظف وأعد المحاولة |

---

## 📞 قنوات الدعم

### رسمي
- 🍎 [Apple Support](https://support.apple.com)
- 📧 [Flutter Support](https://github.com/flutter/flutter/issues)

### مجتمع
- 💬 [Flutter Discord](https://discord.gg/flutter)
- 📱 [Flutter Stack Overflow](https://stackoverflow.com/questions/tagged/flutter)

---

## 💡 نصائح احترافية

1. **استخدم Staging أولاً**
   - أنشئ App ID منفصلة للاختبار
   - اختبر على TestFlight قبل App Store

2. **احتفظ بسجل الإصدارات**
   ```yaml
   version: 1.0.0+BUILD_NUMBER
   ```

3. **تفعيل CI/CD**
   - استخدم CodeMagic للبناء التلقائي
   - اختبر كل PR قبل merge

4. **أمان البيانات**
   - لا تخزن Certificates في Git
   - استخدم Environment Variables
   - راجع البيانات الموقعة بانتظام

---

## 📈 الخطوات التالية

```
1. ✅ قرأت الأدلة
2. ✅ حضّرت البيانات الموقعة
3. ✅ سجلت في CodeMagic
4. ✅ ربطت GitHub
5. ✅ ابدأ البناء الأول
6. ✅ احصل على IPA
7. ✅ رفع على App Store
8. ✅ اجلب المراجعات
```

---

## 🎓 تعليم إضافي

### دورات مجانية
- [Google Flutter Course](https://www.udacity.com/course/build-native-mobile-apps-with-flutter--ud836)
- [Flutter Official Tutorials](https://flutter.dev/docs/getting-started)

### كتب موصى بها
- "Flutter in Action" - Eric Windmill
- "Professional iOS Development" - Ben Scheirman

---

## ✨ ملخص النقاط الأساسية

✅ استخدم **CodeMagic** من Windows  
✅ حضّر **Apple Developer Account**  
✅ اتبع **دليل التصدير** بالتفصيل  
✅ احفظ **سجل الإصدارات**  
✅ استخدم **TestFlight** للاختبار  
✅ راقب **التعليقات والتقييمات**  

---

**تم إعداد المشروع بنجاح! 🎉**

لأي استفسار، راجع الأدلة المتاحة أو اطلب دعم من المجتمع.
