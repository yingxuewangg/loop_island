import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------- 发布签名
// 口令与密钥路径放在 `android/key.properties`（该文件与 `android/keystore/` 都在
// .gitignore 里，不会入库）。读不到时**自动退回 debug 签名**，
// 这样别人 clone 下来不改任何东西也能 `flutter build apk`。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.example.loop_island"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications 的定时通知在低版本 Android 上依赖
        // Java 8+ API 脱糖（java.time 等），不开这一项直接构建不过。
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // 应用商店身份标识。用户原本想要 `loop_island_yxw`，但 Android 的清单合并器
        // **强制要求包名至少含一个点**（否则报：
        // "should contain at least one '.' (dot) character"），
        // 所以取最接近的合法形式：在原来的字符串中间加一个点 → loop_island.yxw
        //
        // 另外两点：
        // 1. 改这里**不会**改代码命名空间 namespace（仍是 com.example.loop_island，
        //    MainActivity 也在那个包里）——两者本来就可以不同；
        // 2. 改完系统会把它当成另一个应用，手机上旧版（com.example.loop_island）要先卸载。
        applicationId = "loop_island.yxw"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                // storeFile 相对 android/ 解析（key.properties 里写的是 keystore/xxx.jks）
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                // 没配签名时的兜底：只为了让构建能跑通，这种包不能上架。
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
