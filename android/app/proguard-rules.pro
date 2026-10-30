# Flutter specific rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep notification related classes
-keep class com.dexterous.** { *; }

# SQLite
-keep class org.sqlite.** { *; }
-keep class io.requery.android.database.** { *; }

# Don't warn about missing classes
-dontwarn io.flutter.embedding.**
-dontwarn com.google.android.play.core.**
