# 🖥️ مقارنة الأوامر: Windows vs Mac/Linux

## الفرق الأساسي

أنت على **Windows** وتستخدم **PowerShell**  
الأوامر القديمة كانت لـ **Mac/Linux (bash)**

---

## جدول المقارنة

### حذف المجلدات

| Mac/Linux | Windows PowerShell |
|-----------|-------------------|
| `rm -rf ios/Pods` | `Remove-Item -Recurse -Force ios/Pods` |
| `rm -rf build/` | `Remove-Item -Recurse -Force build/` |
| `rm -rf ios/Podfile.lock` | `Remove-Item -Recurse -Force ios/Podfile.lock` |

### الأوامر المشتركة (تعمل على الاثنين)

| الأمر | Windows | Mac/Linux |
|------|---------|----------|
| `flutter clean` | ✅ | ✅ |
| `flutter pub get` | ✅ | ✅ |
| `flutter build ios --release --no-codesign` | ✅ | ✅ |
| `cd ios` | ✅ | ✅ |
| `cd ..` | ✅ | ✅ |
| `pod install` | ✅ (يحتاج Ruby) | ✅ |

---

## 🔄 الترجمة السريعة

### 📝 ترجمة الأمر

**Windows:**
```powershell
Remove-Item -Recurse -Force ios/Pods -ErrorAction SilentlyContinue
```

**هذا يعني:**
- `Remove-Item` = حذف عنصر
- `-Recurse` = بشكل متكرر (الملفات والمجلدات داخلها)
- `-Force` = بدون سؤال
- `-ErrorAction SilentlyContinue` = تجاهل الأخطاء

**Mac يقول نفس الشيء بطريقة مختلفة:**
```bash
rm -rf ios/Pods
```

- `rm` = remove
- `-r` = recursive
- `-f` = force

---

## 🎯 القاعدة الذهبية

**أنت على Windows:**
- ❌ لا تستخدم `rm -rf`
- ✅ استخدم `Remove-Item -Recurse -Force`

**إذا كان لديك Mac:**
- ✅ استخدم `rm -rf`
- ✅ استخدم `Remove-Item` أيضاً (يعمل)

---

## 📋 الخطوات السليمة على Windows

```powershell
# 1. تنظيف Flutter
flutter clean

# 2. حذف Pods
Remove-Item -Recurse -Force ios/Pods -ErrorAction SilentlyContinue

# 3. حذف Podfile.lock
Remove-Item -Recurse -Force ios/Podfile.lock -ErrorAction SilentlyContinue

# 4. تحميل المكتبات
flutter pub get

# 5. دخول مجلد iOS
cd ios

# 6. تثبيت المكتبات
pod install --repo-update

# 7. الخروج
cd ..

# 8. بناء الـ iOS
flutter build ios --release --no-codesign
```

---

## 🤔 ماذا يعني `-ErrorAction SilentlyContinue`؟

```powershell
Remove-Item -Recurse -Force ios/Pods -ErrorAction SilentlyContinue
```

هذا يعني: "حاول حذف المجلد، وإذا لم يكن موجوداً، لا تظهر رسالة خطأ"

**بدون هذا:**
```powershell
Remove-Item -Recurse -Force ios/Pods
# ❌ إذا لم يكن موجوداً: PathNotFound error
```

**مع هذا:**
```powershell
Remove-Item -Recurse -Force ios/Pods -ErrorAction SilentlyContinue
# ✅ بدون أخطاء حتى لو لم يكن موجوداً
```

---

## 🚀 الطريقة الأسهل

إذا كنت تريد استخدام أوامر bash على Windows:

### الخيار 1: استخدم Git Bash
1. ثبّت [Git for Windows](https://git-scm.com/download/win)
2. افتح Git Bash
3. استخدم الأوامر العادية

### الخيار 2: استخدم WSL
1. ثبّت [Windows Subsystem for Linux](https://docs.microsoft.com/en-us/windows/wsl/)
2. شغّل WSL
3. استخدم bash

### الخيار 3: استخدم PowerShell (الحالي)
1. استخدم الأوامر أعلاه
2. أسهل وأسرع

---

## ✨ الملخص

| النقطة | الإجابة |
|-------|---------|
| أنا على أي نظام؟ | Windows |
| أي PowerShell؟ | نعم |
| ماذا أستخدم؟ | `Remove-Item` بدل `rm -rf` |
| أين أنسخ الأوامر؟ | من [WINDOWS_COPY_PASTE.md](WINDOWS_COPY_PASTE.md) |
| هل هذا معقد؟ | لا! فقط نسخ والصق |

---

**الآن انطلق واستخدم الأوامر الصحيحة! 🎉**

**الملف المهم: [WINDOWS_COPY_PASTE.md](WINDOWS_COPY_PASTE.md) ⬅️ نسخ من هنا!**
