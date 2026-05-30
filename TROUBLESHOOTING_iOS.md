# 🔧 دليل استكشاف الأخطاء الشائعة في بناء iOS

## المشاكل الشائعة وحلولها

### 1. ❌ خطأ: "The following build commands failed: PhaseScriptExecution"

**السبب:** مشكلة في مرحلة Flutter Build

**الحل:**
```powershell
# نظف كل شيء
flutter clean
Remove-Item -Recurse -Force ios/Pods -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force ios/Podfile.lock -ErrorAction SilentlyContinue

# أعد البناء
flutter pub get
cd ios
pod install --repo-update
cd ..
flutter build ios --release --no-codesign
```

---

### 2. ❌ خطأ: "PROVISIONING_PROFILE requires a value"

**السبب:** لا توجد Provisioning Profile معدة

**الحل على CodeMagic:**
1. اذهب إلى **Team Settings** > **Code Signing**
2. انقر **Add** وأضف:
   - ✏️ iOS Certificate (.cer)
   - ✏️ Private Key (.p12)
   - ✏️ Provisioning Profile (.mobileprovision)

3. استخدم **Automatic Signing** بدلاً من Manual:
   ```yaml
   environment:
     ios_signing:
       use_automatic_profiles: true
   ```

---

### 3. ❌ خطأ: "Code Signing Identity does not match any signing certificate"

**السبب:** البيانات الموقعة غير متطابقة

**الحل:**
```xml
<!-- في ios/ExportOptions.plist -->
<key>signingStyle</key>
<string>automatic</string>

<key>codeSigningIdentity</key>
<string>iPhone Distribution</string>
```

---

### 4. ❌ خطأ: "Unable to resolve dependencies for 'GoogleMobileAds'"

**السبب:** مكتبة الإعلانات غير متوافقة مع iOS

**الحل:**
```bash
# في Podfile، تأكد من:
cd ios

# اسمح للكود القديم
pod repo update

# أعد install
pod install --repo-update
cd ..
```

أو غيّر إصدار المكتبة في pubspec.yaml:
```yaml
google_mobile_ads: ^5.0.0  # نسخة أحدث
```

---

### 5. ❌ خطأ: "Bitcode is disabled for target 'Runner'"

**السبب:** إعدادات Bitcode غير متطابقة

**الحل:**
```xml
<!-- في ios/ExportOptions.plist -->
<key>uploadBitcode</key>
<false/>
```

أو فعّل Bitcode في جميع الـ pods:

```bash
cd ios
pod install

# حرّر Podfile وأضف:
# post_install do |installer|
#   installer.pods_project.targets.each do |target|
#     target.build_configurations.each do |config|
#       config.build_settings['ENABLE_BITCODE'] = 'NO'
#     end
#   end
# end
```

---

### 6. ❌ خطأ: "Pod install failed"

**السبب:** مشكلة في CocoaPods

**الحل:**
```powershell
# نظف تماماً
cd ios
Remove-Item -Recurse -Force Pods -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force Podfile.lock -ErrorAction SilentlyContinue
cd ..

# أعد البناء
flutter clean
flutter pub get
flutter build ios --release --no-codesign
```

---

### 7. ❌ خطأ: "No bundle identifier found in GeneratedPluginRegistrant"

**السبب:** ملفات Flutter لم تُنشأ بشكل صحيح

**الحل:**
```bash
flutter clean
flutter pub get
flutter generate
flutter build ios --release --no-codesign
```

---

## 🔍 الملفات المهمة للتحقق منها

```
ios/
├── Runner/
│   ├── Info.plist                    ✅ تحقق من البندل ID
│   ├── Runner-Bridging-Header.h
│   └── GeneratedPluginRegistrant.m
├── Podfile                            ✅ تحقق من المنصة والإصدار
├── Runner.xcworkspace
│   └── contents.xcworkspacedata
└── Flutter/
    ├── Generated.xcconfig             ✅ يجب أن توجد
    ├── Debug.xcconfig
    └── Release.xcconfig
```

---

## ✅ قائمة تحقق قبل البناء

- [ ] `pubspec.yaml` محدثة بكل المكتبات
- [ ] `ios/Podfile` تحتوي على `platform :ios, '13.0'`
- [ ] `ios/Runner/Info.plist` تحتوي على الأذونات المطلوبة
- [ ] Bundle ID الصحيح: `com.example.wallpaper`
- [ ] لا توجد مشاكل في Dart code:
  ```bash
  flutter analyze
  ```
- [ ] كل الاختبارات تمر:
  ```bash
  flutter test
  ```

---

## 🚀 أوامر مفيدة

### عرض معلومات البناء
```bash
flutter build ios --verbose --no-codesign 2>&1 | head -100
```

### التحقق من CocoaPods
```bash
pod repo update
pod install --repo-update --verbose
```

### تنظيف كامل
```powershell
flutter clean
Remove-Item -Recurse -Force ios/Pods -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force ios/Podfile.lock -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force build/ -ErrorAction SilentlyContinue
flutter pub get
```

### بناء مفصل
```bash
flutter build ios --release --verbose --no-codesign
```

---

## 📞 متى تطلب المساعدة؟

إذا جربت كل هذا ولم ينجح:

1. **انسخ رسالة الخطأ الكاملة**
2. **شغّل الأوامر الآتية وحفظ النتائج:**
   ```bash
   flutter doctor -v
   flutter devices
   flutter build ios --verbose --no-codesign 2>&1 | tail -200
   ```
3. **قدّم المعلومات هذه للدعم**

---

## 🎯 ملخص سريع للحل الكامل

```bash
# 1. تنظيف
flutter clean
rm -rf ios/Pods ios/Podfile.lock

# 2. احصل على المكتبات
flutter pub get

# 3. فعّل CocoaPods
cd ios && pod install --repo-update && cd ..

# 4. بناء مبدئي (بدون توقيع)
flutter build ios --release --no-codesign

# 5. إذا نجح، استخدم CodeMagic للتوقيع والتصدير
```

---

**آمل أن تكون هذه القائمة مفيدة! 🎉**
