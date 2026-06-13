# حماية ملفات وأكواد فلاتر الداخلية
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# حماية مكاتب جافا وكوتلن الخارجية (مثل مكاتب جلب الصور والمعلومات والاعلانات)
-keep class com.mhz.savegallery.** { *; }
-keep class dev.fluttercommunity.plus.** { *; }
-keep class io.flutter.plugins.googlemobileads.** { *; }
-keep class com.google.android.gms.ads.** { *; }

# منع حذف أو تغيير أسماء الكلاسات الحساسة
-dontwarn io.flutter.plugins.**
-dontwarn com.google.android.gms.ads.**
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod