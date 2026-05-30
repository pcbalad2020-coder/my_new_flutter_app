# 📱 شرح تصدير التطبيق كـ IPA عبر CodeMagic

## ✅ الخطوات الأساسية

### 1️⃣ إعداد Developer Account

قبل البدء، تأكد من:
- ✔️ حساب **Apple Developer** نشط
- ✔️ **Team ID** الخاص بك (من App Store Connect)
- ✔️ **Certificate** و **Provisioning Profile** معدة

---

### 2️⃣ إعدادات CodeMagic

#### أ) ربط GitHub Repository
1. اذهب إلى [codemagic.io](https://codemagic.io)
2. سجل دخول باستخدام حسابك
3. اختر `Repository` > **ربط GitHub**
4. اختر مشروعك: `flutter-apps/wallpaper`

#### ب) إضافة Apple Developer Account
1. من Dashboard، اختر `Team settings`
2. اذهب إلى `Code Signing Identities`
3. أضف **iOS Signing Certificate** و **Provisioning Profile**

#### ج) تحديث ملفات المشروع
تأكد من وجود الملفات التالية:
- ✔️ `codemagic.yaml` (تم إنشاؤه)
- ✔️ `ios/ExportOptions.plist` (تم إنشاؤه)

---

### 3️⃣ تعديلات مطلوبة في المشروع

#### ✏️ تحديث `ios/ExportOptions.plist`
استبدل `XXXXXXXXXX` برقم Team ID الخاص بك:

```xml
<key>teamID</key>
<string>YOUR_TEAM_ID_HERE</string>
```

**للحصول على Team ID:**
- اذهب إلى [developer.apple.com](https://developer.apple.com)
- اختر `Membership`
- انسخ **Team ID** من الأعلى

#### ✏️ تحديث `codemagic.yaml` 
إذا أردت البريد الإلكتروني:
- استبدل `$EMAIL_ADDRESS` بريدك الفعلي أو أضفه في Environment Variables

---

### 4️⃣ خطوات البناء على CodeMagic

#### الطريقة الأولى: عبر Dashboard

1. اذهب إلى مشروعك على CodeMagic
2. انقر **Create Workflow**
3. اختر **iOS App**
4. اختر **Release** من القائمة اليسرى
5. انقر **Start Building**

#### الطريقة الثانية: من ملف `codemagic.yaml`

- CodeMagic سيقرأ التكوين تلقائياً من `codemagic.yaml`
- ستجد workflow بسمة **"iOS Release Build"** في Dashboard

---

### 5️⃣ نتائج البناء

بعد اكتمال البناء، ستجد:
- 📥 **IPA File**: `Runner.ipa`
- 📦 **Archive**: `Runner.xcarchive`
- 📧 البريد الإلكتروني سيصل إليك برابط التحميل

---

## ⚠️ مشاكل شائعة وحلولها

### ❌ خطأ: "Certificate not found"
**الحل:**
- تأكد من تحميل الـ Certificate من Developer Account
- استخدم **Automatic** signing بدلاً من Manual

### ❌ خطأ: "Provisioning Profile not found"
**الحل:**
- اذهب إلى Apple Developer
- تأكد من أن Provisioning Profile متاح للـ Bundle ID: `com.example.wallpaper`

### ❌ خطأ: "Code signing failed"
**الحل:**
```bash
# نظف البناء
rm -rf ios/Pods ios/Podfile.lock
cd ios && pod install && cd ..

# ثم أعد المحاولة
```

### ❌ خطأ: "Bitcode compilation failed"
**الحل:**
- يمكنك تعطيل Bitcode في `ios/ExportOptions.plist`:
```xml
<key>uploadBitcode</key>
<false/>
```

---

## 🔐 الأذونات المطلوبة في Info.plist

تحقق من أن `ios/Runner/Info.plist` يحتوي على:

```xml
<!-- للصور -->
<key>NSPhotoLibraryUsageDescription</key>
<string>نحتاج الوصول للصور</string>

<!-- للإنترنت (للإعلانات) -->
<key>NSLocalNetworkUsageDescription</key>
<string>لتحميل الصور والإعلانات</string>
```

---

## 📝 أوامر للفحص المحلي (اختياري)

إذا أردت اختبار البناء محلياً على Mac:

```bash
# نظف البناء السابق
flutter clean

# احصل على المكتبات
flutter pub get

# بناء iOS Release
flutter build ios --release --no-codesign

# بناء الـ IPA (إذا كان لديك شهادة)
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

## 🚀 الخطوات الأخيرة

بعد الحصول على IPA:

### لـ TestFlight:
1. ارفع الـ IPA عبر App Store Connect
2. اختر Testers من Build الجديد

### لـ App Store:
1. اختر Build في App Store Connect
2. ملأ البيانات المطلوبة (Screenshots, Description, إلخ)
3. أرسل للمراجعة

---

## ✨ ملاحظات هامة

- 🔄 **Bundle ID**: `com.example.wallpaper` - غيره إذا أردت
- 📱 **iOS Deployment Target**: `13.0` (متوافق مع معظم الأجهزة)
- 🎯 **Architecture**: يدعم ARM64 (الأجهزة الحديثة)

---

## 📞 دعم إضافي

إذا واجهت مشاكل:
- 📖 اقرأ [Flutter iOS Documentation](https://flutter.dev/docs/deployment/ios)
- 🆘 تفقد [CodeMagic Support](https://docs.codemagic.io/ios-code-signing/)
- 💬 اطلب من فريق Apple Developer

---

**Good luck! 🎉**
