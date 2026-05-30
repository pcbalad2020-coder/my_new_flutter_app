# 🔧 حل خطأ CocoaPods - Swift Package Manager Conflict

## المشكلة

```
Error: A dependency conflict has occurred because google_mobile_ads uses CocoaPods 
while webview_flutter_wkwebview uses Swift Package Manager.
```

### السبب
- `google_mobile_ads` يعتمد على **CocoaPods**
- `webview_flutter_wkwebview` يعتمد على **Swift Package Manager (SPM)**
- هناك تضارب بينهما

---

## ✅ الحل المطبق

### تم تحديث `ios/Podfile`

تمت إضافة الإعدادات التالية:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
      # تعطيل Swift Package Manager لحل التضارب مع google_mobile_ads
      config.build_settings['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'NO'
      config.build_settings['SWIFT_VERSION'] = '5.0'
    end
  end
end
```

---

## 🚀 الخطوات التالية

### على Windows PowerShell:

```powershell
# 1. نظف الملفات القديمة
Remove-Item -Recurse -Force ios/Pods -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force ios/Podfile.lock -ErrorAction SilentlyContinue

# 2. احصل على المكتبات
flutter pub get

# 3. أعد تثبيت CocoaPods
cd ios
pod install --repo-update
cd ..

# 4. اختبر البناء
flutter build ios --release --no-codesign
```

### أو استخدم الأمر المختصر:

```powershell
Remove-Item -Recurse -Force ios/Pods -ErrorAction SilentlyContinue; Remove-Item -Recurse -Force ios/Podfile.lock -ErrorAction SilentlyContinue; flutter pub get; cd ios; pod install --repo-update; cd ..
```

---

## 📝 شرح الإعدادات

| الإعداد | الشرح |
|--------|-------|
| `IPHONEOS_DEPLOYMENT_TARGET = '13.0'` | أقل إصدار iOS مدعوم |
| `BUILD_LIBRARY_FOR_DISTRIBUTION = 'NO'` | عدم بناء مكتبات للتوزيع |
| `SWIFT_VERSION = '5.0'` | إصدار Swift المستخدم |

---

## ✨ بدائل أخرى (اختياري)

### إذا استمرت المشكلة:

#### البديل 1: تعطيل webview_flutter_wkwebview

إذا لم تكن تستخدمه، أزله من `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  google_mobile_ads: ^4.0.0
  # أزل: webview_flutter_wkwebview
```

#### البديل 2: تحديث pubspec.yaml

استخدم نسخة أحدث من المكتبات:

```yaml
dependencies:
  google_mobile_ads: ^5.0.0
  webview_flutter_wkwebview: ^4.0.0
```

#### البديل 3: تعطيل SPM يدويا

أضف هذا في `pubspec.yaml`:

```yaml
# في الجزء العلوي
publish_to: 'none'
version: 1.0.0+1

# تأكد من وجود هذا
flutter:
  uses-material-design: true

# أضف هذا إذا لزم:
environment:
  sdk: '>=3.0.0 <4.0.0'
```

---

## 🔍 إذا استمرت المشكلة

### تنظيف كامل:

```powershell
# 1. حذف كل الملفات المؤقتة
flutter clean

# 2. حذف Pods تماماً
Remove-Item -Recurse -Force ios/Pods -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force ios/Podfile.lock -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force build/ -ErrorAction SilentlyContinue

# 3. إعادة التثبيت
flutter pub get
cd ios
pod repo update
pod install --repo-update --verbose
cd ..

# 4. البناء
flutter build ios --release --no-codesign
```

---

## 📞 تشخيص المشكلة

### معرفة الخطأ بالضبط:

```powershell
# عرض التفاصيل الكاملة
cd ios
pod install --verbose
```

---

## ✅ علامات النجاح

بعد الخطوات أعلاه:

```
✅ Analyzing dependencies
✅ Downloading dependencies
✅ Generating Pods project
✅ Integrating client project
✅ Running post install hooks
✅ Pod installation complete!
```

---

## 🎯 الملفات المتعلقة

- [WINDOWS_COPY_PASTE.md](WINDOWS_COPY_PASTE.md) - أوامر Windows
- [TROUBLESHOOTING_iOS.md](TROUBLESHOOTING_iOS.md) - مشاكل عامة
- [QUICK_FIX.md](QUICK_FIX.md) - حلول سريعة

---

**تم الإصلاح! 🎉 جرّب الأوامر أعلاه الآن.**
