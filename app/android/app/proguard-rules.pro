# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Flutter Local Notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Desugaring & Timezone
-dontwarn java.time.**
-dontwarn java.lang.invoke.**

# Keep annotations and line numbers for stack traces
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
