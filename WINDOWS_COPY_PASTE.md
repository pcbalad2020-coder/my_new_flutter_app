# 🪟 نسخ والصق مباشرة - Windows PowerShell

## ⚡ الحل الفوري (نسخ ولصق)

افتح **PowerShell** وانسخ الأوامر التالية مباشرة:

---

## 📋 أوامر جاهزة للنسخ واللصق

### 1️⃣ التنظيف والتحضير الكامل

```powershell
flutter clean; Remove-Item -Recurse -Force ios/Pods -ErrorAction SilentlyContinue; Remove-Item -Recurse -Force ios/Podfile.lock -ErrorAction SilentlyContinue; Remove-Item -Recurse -Force build/ -ErrorAction SilentlyContinue; flutter pub get; cd ios; pod install --repo-update; cd ..
```

**أو خطوة بخطوة (أسهل للمبتدئين):**

```powershell
flutter clean
```

ثم:
```powershell
Remove-Item -Recurse -Force ios/Pods -ErrorAction SilentlyContinue
```

ثم:
```powershell
Remove-Item -Recurse -Force ios/Podfile.lock -ErrorAction SilentlyContinue
```

ثم:
```powershell
flutter pub get
```

ثم:
```powershell
cd ios
```

ثم:
```powershell
pod install --repo-update
```

ثم:
```powershell
cd ..
```

---

### 2️⃣ اختبر البناء

```powershell
flutter build ios --release --no-codesign
```

---

## ✅ النتيجة المتوقعة

**عند انتهاء الأوامر:**
```
✅ Build completed successfully!
```

**إذا حصل خطأ، اقرأ:**
- [QUICK_FIX.md](QUICK_FIX.md)
- [TROUBLESHOOTING_iOS.md](TROUBLESHOOTING_iOS.md)

---

## 🎯 شرح الأوامر

| الأمر | الشرح |
|------|-------|
| `flutter clean` | تنظيف الملفات المؤقتة |
| `Remove-Item -Recurse -Force ios/Pods` | حذف مجلد Pods |
| `Remove-Item -Recurse -Force ios/Podfile.lock` | حذف ملف Podfile.lock |
| `flutter pub get` | تحميل المكتبات |
| `pod install --repo-update` | تثبيت CocoaPods |
| `flutter build ios --release --no-codesign` | بناء التطبيق |

---

## 🚀 الخطوة التالية

بعد نجاح الأوامر أعلاه:

1. اذهب إلى [codemagic.io](https://codemagic.io)
2. أكمل الخطوات الموضحة في [QUICK_START_IPA.md](QUICK_START_IPA.md)

---

## ⚠️ نصائح مهمة

- ✅ نسخ الأمر بالكامل (بدون تجزئة)
- ✅ لا تضيف أي رموز إضافية
- ✅ اضغط Enter بعد النسخ واللصق
- ✅ انتظر انتهاء الأمر قبل الأمر التالي

---

## 💡 إذا حصل خطأ

### أكثر الأخطاء شيوعاً:

```
❌ "pod install failed"
✅ الحل: شغّل الأمر الأول مرة أخرى

❌ "Remove-Item : Cannot find path"
✅ الحل: لا توجد مشكلة، الأمر يحاول حذف ملف غير موجود
      (الـ -ErrorAction SilentlyContinue يتجاهل هذا)

❌ "pod: command not found"
✅ الحل: أنت تحتاج Mac (يحتاج Xcode و CocoaPods)
```

---

## 📞 شيء آخر؟

اقرأ الملفات التالية:
- [WINDOWS_POWERSHELL_GUIDE.md](WINDOWS_POWERSHELL_GUIDE.md) - شرح أوامر Windows
- [QUICK_START_IPA.md](QUICK_START_IPA.md) - خطوات CodeMagic
- [TROUBLESHOOTING_iOS.md](TROUBLESHOOTING_iOS.md) - حل المشاكل

---

**الآن نسخ والصق وسهل! 🎉**
