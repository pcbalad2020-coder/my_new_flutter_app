# 🪟 أوامر Windows PowerShell لـ Flutter iOS

## المشكلة
على Windows، أوامر bash (`rm -rf`) لا تعمل. نحتاج إلى أوامر PowerShell.

---

## ✅ الحل: الأوامر الصحيحة للـ Windows PowerShell

### 🔧 تنظيف كامل للمشروع

```powershell
# 1. حذف المجلدات المؤقتة
Remove-Item -Recurse -Force -Path ios/Pods
Remove-Item -Recurse -Force -Path ios/Podfile.lock
Remove-Item -Recurse -Force -Path build/

# 2. احصل على المكتبات
flutter pub get

# 3. فعّل CocoaPods
cd ios
pod install --repo-update
cd ..

# 4. بناء iOS (بدون توقيع)
flutter build ios --release --no-codesign
```

---

## 📝 أوامر PowerShell البديلة

| bash | PowerShell |
|------|-----------|
| `rm -rf folder` | `Remove-Item -Recurse -Force folder` |
| `mkdir folder` | `New-Item -ItemType Directory -Path folder` |
| `ls` | `Get-ChildItem` أو `ls` |
| `cd folder` | `Set-Location folder` أو `cd` |

---

## 🚀 الحل السريع (نسخ والصق)

**انسخ هذا مباشرة في PowerShell:**

```powershell
# الحل الكامل في سطر واحد:
Remove-Item -Recurse -Force ios/Pods; Remove-Item -Recurse -Force ios/Podfile.lock; Remove-Item -Recurse -Force build/; flutter pub get; cd ios; pod install --repo-update; cd ..; flutter build ios --release --no-codesign
```

**أو خطوة بخطوة:**

```powershell
# خطوة 1: حذف Pods
Remove-Item -Recurse -Force ios/Pods

# خطوة 2: حذف Podfile.lock
Remove-Item -Recurse -Force ios/Podfile.lock

# خطوة 3: حذف build
Remove-Item -Recurse -Force build/

# خطوة 4: احصل على Flutter packages
flutter pub get

# خطوة 5: أعد تثبيت CocoaPods
cd ios
pod install --repo-update
cd ..

# خطوة 6: اختبر البناء
flutter build ios --release --no-codesign
```

---

## ⚡ اختصار مفيد (اختياري)

قم بإنشاء ملف `.ps1` للأوامر المتكررة:

1. أنشئ ملف اسمه `clean-ios.ps1` في مجلد المشروع:

```powershell
# clean-ios.ps1
Remove-Item -Recurse -Force ios/Pods -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force ios/Podfile.lock -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force build/ -ErrorAction SilentlyContinue
flutter pub get
Set-Location ios
pod install --repo-update
Set-Location ..
Write-Host "✅ التنظيف اكتمل!"
```

2. شغّله بكتابة:
```powershell
.\clean-ios.ps1
```

---

## 🛠️ جدول مقارنة

| النظام | الأمر |
|--------|------|
| **macOS/Linux** | `rm -rf ios/Pods` |
| **Windows (PowerShell)** | `Remove-Item -Recurse -Force ios/Pods` |
| **Windows (WSL)** | `rm -rf ios/Pods` |

---

## 💡 نصيحة: استخدام WSL

إذا كنت تريد استخدام bash على Windows:

### تثبيت WSL:
```powershell
wsl --install Ubuntu-22.04
```

### ثم داخل WSL استخدم أوامر bash:
```bash
rm -rf ios/Pods
rm -rf ios/Podfile.lock
rm -rf build/
```

---

## ✨ الخيارات المتاحة

### ✅ الخيار 1: PowerShell (الحالي - الأسهل)
استخدم الأوامر أعلاه مباشرة

### ✅ الخيار 2: WSL (Recommended للمتقدمين)
1. ثبّت WSL
2. استخدم bash كالمعتاد

### ✅ الخيار 3: Git Bash
1. ثبّت Git for Windows
2. افتح Git Bash
3. استخدم bash commands

---

## 🎯 التلخيص

**على Windows PowerShell، استخدم هذا:**

```powershell
# نسخ والصق هذا:
Remove-Item -Recurse -Force ios/Pods -ErrorAction SilentlyContinue; 
Remove-Item -Recurse -Force ios/Podfile.lock -ErrorAction SilentlyContinue; 
Remove-Item -Recurse -Force build/ -ErrorAction SilentlyContinue; 
flutter pub get; 
cd ios; 
pod install --repo-update; 
cd ..
```

---

**الآن استخدم هذه الأوامر وستعمل بدون مشاكل! ✅**
