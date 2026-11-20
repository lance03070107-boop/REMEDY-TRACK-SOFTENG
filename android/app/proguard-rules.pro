# ==============================================================================
# RemedyTrack Production R8 / ProGuard Configuration
# ==============================================================================

# --- Crashlytics Line Numbers & Stack Traces ---
-keepattributes SourceFile,LineNumberTable
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-keepattributes Signature

# --- Flutter Engine & Wrappers ---
-keep class io.flutter.** { *; }
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-dontwarn io.flutter.**

# --- Google Services & Firebase ---
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# --- Firebase Crashlytics ---
-keep public class * extends java.lang.Exception
-keepclassmembers class * {
    @com.google.firebase.crashlytics.** *;
}

# --- Cloud Firestore & Protobuf ---
-keep class com.google.firebase.firestore.** { *; }
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**
-dontwarn io.grpc.**
-keep class io.grpc.** { *; }

# --- flutter_local_notifications ---
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class androidx.core.app.NotificationCompat** { *; }

# --- WorkManager (Periodic Reconciler) ---
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**

# --- Biometrics / local_auth ---
-keep class androidx.biometric.** { *; }
-dontwarn androidx.biometric.**

# --- App Models & JSON Serialization ---
-keepclassmembers class * {
    *** fromJson(...);
    *** toJson(...);
}

