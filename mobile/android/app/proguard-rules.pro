# Keep plugin classes used through reflection (notifications, location service).
-keep class com.dexterous.** { *; }
-keep class com.baseflow.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn com.google.android.play.core.**
