# 🔴 الخطأ: CocoaPods - Swift Package Manager Conflict

## المشكلة الحالية

```
Error: A dependency conflict has occurred because google_mobile_ads uses CocoaPods 
while webview_flutter_wkwebview uses Swift Package Manager.
```

---

## ✅ الحل السريع (Windows PowerShell)

```powershell
# تنظيف كامل
Remove-Item -Recurse -Force ios/Pods -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force ios/Podfile.lock -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force build/ -ErrorAction SilentlyContinue

# إعادة التثبيت
flutter pub get
cd ios
pod repo update
pod install --repo-update
cd ..

# البناء
flutter build ios --release --no-codesign
```

---

## 📖 قراءة إضافية

للتفاصيل الكاملة: [FIX_COCOAPODS_SPM_CONFLICT.md](FIX_COCOAPODS_SPM_CONFLICT.md)

---

**الملف `ios/Podfile` تم تحديثه بالفعل! 🎉**
