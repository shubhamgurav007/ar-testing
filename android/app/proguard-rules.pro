# Keep Sceneform classes for ar_flutter_plugin
-keep class com.google.ar.sceneform.** { *; }
-dontwarn com.google.ar.sceneform.**

# Keep Google AR Core classes
-keep class com.google.ar.core.** { *; }
-dontwarn com.google.ar.core.**

# Keep desugar runtime
-keep class com.google.devtools.build.android.desugar.runtime.** { *; }
-dontwarn com.google.devtools.build.android.desugar.runtime.**
