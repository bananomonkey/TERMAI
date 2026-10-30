# ProGuard rules for TERMAI (Flutter + Firebase)

# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.flutter_plugin_android_lifecycle.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# google_sign_in
-keep class io.flutter.plugins.googlesignin.** { *; }

# Keep names for reflection-based plugins
-keepnames class io.flutter.plugins.** { *; }

# Google Play Core (deferred components) — не используется, но Flutter Engine ссылается.
-dontwarn com.google.android.play.core.**

# Application classes
-keep class com.vlad.termai.** { *; }

# JSON serialization (if any reflection is used)
-keepnames class * extends io.flutter.plugins.** { *; }
