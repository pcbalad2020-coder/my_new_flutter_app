# 🚨 الخطأ الشائع وحله الفوري

## المشكلة: "خطأ في البناء عند محاولة تصدير IPA"

### الأخطاء الشائعة:

```
❌ "Pod install failed"
❌ "Bitcode compilation failed"
❌ "Certificate not found"
❌ "Provisioning Profile required"
❌ "PhaseScriptExecution failed"
```

---

## ✅ الحل الفوري (3 خطوات)

### الخطوة 1️⃣: نظّف المشروع

**على Windows PowerShell:**
```powershell
# 1. حذف الملفات المؤقتة
flutter clean

# 2. حذف Pods (ملفات iOS)
Remove-Item -Recurse -Force ios/Pods -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force ios/Podfile.lock -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force build/ -ErrorAction SilentlyContinue

# 3. تحديث المكتبات
flutter pub get
```

**على Mac/Linux:**
```bash
# 1. حذف الملفات المؤقتة
flutter clean

# 2. حذف Pods (ملفات iOS)
rm -rf ios/Pods
rm -rf ios/Podfile.lock
rm -rf build/

# 3. تحديث المكتبات
flutter pub get
```

### الخطوة 2️⃣: أعد تثبيت المكتبات

```bash
# الدخول لمجلد iOS
cd ios

# تحديث والتثبيت
pod repo update
pod install --repo-update

# الرجوع
cd ..
```

### الخطوة 3️⃣: اختبر البناء

```bash
# بناء iOS بدون توقيع (للاختبار)
flutter build ios --release --no-codesign
```

---

## 🔍 إذا استمر الخطأ

### للخطأ: "Bitcode"

في `ios/ExportOptions.plist`:
```xml
<key>uploadBitcode</key>
<false/>
```

### للخطأ: "Certificate"

على CodeMagic:
1. اذهب Settings > Code Signing
2. أضف نمط جديد:
   - Certificate (.cer)
   - Private Key (.p12)
   - Provisioning Profile

### للخطأ: "Pod"

```bash
cd ios
rm -rf Pods Podfile.lock
pod install --repo-update --verbose
cd ..
```

---

## 🎯 ملخص الحل

| الخطأ | السبب | الحل |
|------|-----|------|
| Pod install | مكتبات قديمة | `pod install --repo-update` |
| Bitcode | إعدادات | عطّل Bitcode |
| Certificate | بيانات | أضفها على CodeMagic |
| PhaseScript | ملفات | `flutter clean` |

---

## 💡 نصيحة ذهبية

**قبل أي بناء جديد:**

**Windows PowerShell:**
```powershell
flutter clean; Remove-Item -Recurse -Force ios/Pods -ErrorAction SilentlyContinue; Remove-Item -Recurse -Force ios/Podfile.lock -ErrorAction SilentlyContinue; flutter pub get; cd ios; pod install --repo-update; cd ..
```

**Mac/Linux:**
```bash
flutter clean && rm -rf ios/Pods ios/Podfile.lock && flutter pub get && cd ios && pod install --repo-update && cd ..
```

---

## ✨ الخطوات الأساسية مجددا

```
1. ✅ flutter clean
2. ✅ rm -rf ios/Pods ios/Podfile.lock
3. ✅ flutter pub get
4. ✅ cd ios && pod install --repo-update && cd ..
5. ✅ flutter build ios --release --no-codesign
6. ✅ الآن على CodeMagic للتصدير النهائي
```

---

**بعد هذه الخطوات، 99% من المشاكل تحتل! 🎉**

إذا استمرت المشكلة، اقرأ `TROUBLESHOOTING_iOS.md` للمزيد من التفاصيل.
