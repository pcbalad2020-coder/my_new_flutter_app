import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.kasem.wallpapers"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = if (keystoreProperties["storeFile"] != null)
                rootProject.file(keystoreProperties["storeFile"] as String)
            else null
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    defaultConfig {
        applicationId = "com.kasem.wallpapers"

        // ✅ التصحيح #1: تثبيت minSdk = 23 بشكل صريح
        // firebase_messaging الحديثة تتطلب 23 كحد أدنى. إن كان flutter.minSdkVersion
        // أقل (الافتراضي القديم كان 21)، فإن مزامنة Gradle قد تفشل قبل حتى تجربة الإشعارات.
        minSdk = maxOf(flutter.minSdkVersion, 23)

        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // ✅ التصحيح #2: تفعيل multiDex
        // ضروري مع Firebase + AdMob + باقي المكتبات الكثيرة في هذا المشروع
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile>().configureEach {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    "coreLibraryDesugaring"("com.android.tools:desugar_jdk_libs:2.0.4")

    // ✅ التصحيح #3: إضافة مكتبة multidex الفعلية
    // (multiDexEnabled في defaultConfig يفعّل الخيار، لكن لمشاريع minSdk < 21 فقط يلزم
    // هذا السطر إجبارياً. بما أننا رفعنا minSdk إلى 23 فهو ليس إجبارياً تقنياً،
    // لكن إضافته آمنة ومستحسنة كحماية إضافية مع كثرة المكتبات هنا)
    implementation("androidx.multidex:multidex:2.0.1")
}