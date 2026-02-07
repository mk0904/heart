# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Google Play Services
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**
-keep class com.google.common.** { *; }
-dontwarn com.google.common.**

# Firebase
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# AndroidX / Support Library
-keep class androidx.** { *; }
-keep interface androidx.** { *; }
-dontwarn androidx.**
-keep class android.support.** { *; }
-keep interface android.support.** { *; }
-dontwarn android.support.** 

# Squareup (OkHttp/Retrofit frequently used by plugins)
-keep class com.squareup.** { *; }
-dontwarn com.squareup.**
-dontwarn okio.** 

# Gson
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**

# Generated Bindings
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
