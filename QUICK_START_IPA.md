# ⚡ خطوات سريعة: تصدير IPA عبر CodeMagic

## 📋 قبل البدء - تأكد من وجود:

- ✅ Apple Developer Account (نشط)
- ✅ Team ID من App Store Connect
- ✅ iOS Certificate و Provisioning Profile

---

## 🚀 الخطوات (5 دقائق فقط)

### الخطوة 1️⃣: اذهب إلى CodeMagic
```
https://codemagic.io
```

### الخطوة 2️⃣: أضف مستودع GitHub
- اختر `Add Repository`
- اختر `flutter-apps/wallpaper`
- اختر `Configure for iOS`

### الخطوة 3️⃣: أضف البيانات الموقعة
**من Settings > Code Signing:**

```
1. اختر "Add Signing Identities"
2. اختر "iOS Signing Certificate" 
3. ارفع:
   - Certificate (.cer)
   - Private Key (.p12)
   - Provisioning Profile (.mobileprovision)
```

### الخطوة 4️⃣: ابدأ البناء
```
انقر "Start Workflow" 
اختر "iOS Release Build"
انقر "Build"
```

### الخطوة 5️⃣: انتظر و احصل على IPA
```
بعد 10-15 دقيقة:
✅ IPA جاهز للتحميل
📧 رابط سيُرسل لبريدك
```

---

## 🔑 البيانات الموقعة: من أين أحصل عليها؟

### للحصول على Certificate:

```
1. اذهب: https://developer.apple.com
2. Certificates, IDs & Profiles
3. Certificates > Create > App Store Distribution
4. اتبع الخطوات واحفظ كـ .cer
```

### للحصول على Private Key:

```
1. نفس الخطوات أعلاه
2. ستحتاج إلى Keychain Access على Mac
3. أو استخدم iOS Development Certificate مباشرة
4. احفظ كـ .p12
```

### للحصول على Provisioning Profile:

```
1. Certificates, IDs & Profiles
2. Provisioning Profiles > Distribution
3. Create > App Store
4. اختر Bundle ID: com.example.wallpaper
5. اختر Certificate (من الأعلى)
6. احفظ الملف
```

---

## ⚠️ في حالة عدم وجود بيانات موقعة

إذا لم تكن لديك بيانات موقعة (أول مرة):

```
1. CodeMagic يمكنه إنشاء signing معك تلقائياً
2. اختر "Create Signing" 
3. CodeMagic سيتولى بقية الخطوات
4. فقط وافق على الصلاحيات في Apple Developer
```

---

## 📥 تحميل IPA

بعد انتهاء البناء:

```
1. اذهب إلى Build History
2. ستجد IPA في الملفات
3. اضغط Download
4. أو استخدم الرابط من البريد الإلكتروني
```

---

## 🎯 ماذا تفعل بـ IPA؟

### ✅ خيار 1: رفع على App Store
```
1. اذهب: app.apple.com/appstore/connect
2. اختر My Apps
3. اختر تطبيقك
4. Build > Choose Build > اختر الإصدار الجديد
5. Submit for Review
```

### ✅ خيار 2: اختبار على TestFlight
```
1. نفس الخطوات أعلاه
2. لكن اختر Testers بدلاً من Review
3. وزع على فريقك للاختبار
```

### ✅ خيار 3: توزيع مباشر
```
1. استخدم "Ad Hoc" Provisioning Profile
2. أرسل IPA للأشخاص المصرح لهم
3. يمكنهم تثبيتها على أجهزتهم
```

---

## 🆘 أخطاء محتملة

### ❌ "No Provisioning Profile found"
```
الحل: تأكد من تحميل الملف الصحيح على CodeMagic
```

### ❌ "Certificate expired"
```
الحل: جدّد Certificate من Apple Developer
```

### ❌ "Bundle ID mismatch"
```
الحل: استخدم نفس Bundle ID في CodeMagic والـ Provisioning
الحالي: com.example.wallpaper
```

---

## 💡 نصائح مهمة

- 🔄 **Versioning**: كل مرة رفع جديد، غيّر version في `pubspec.yaml`
  ```yaml
  version: 1.0.0+2  # غيّر +1 إلى +2
  ```

- 🛡️ **Signing**: استخدم "Automatic" بدلاً من Manual

- ⏱️ **الوقت**: البناء الأول قد يستغرق 20 دقيقة

- 📝 **Logs**: احفظ logs في حالة حدوث خطأ

---

## ✨ هذا كل ما تحتاج!

الآن لديك:
- ✅ `codemagic.yaml` - ملف التكوين
- ✅ `ios/ExportOptions.plist` - إعدادات التصدير
- ✅ دليل كامل - شرح مفصّل

**الخطوة التالية: اتبع الخطوات الـ 5 أعلاه 🚀**

---

**Good luck! 🎉 أي سؤال آخر؟**
