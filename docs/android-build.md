# Android build versions

The project uses Gradle 9.6.0, Android Gradle Plugin 9.5.1 and Kotlin 2.4.21.
Flutter is configured on this workstation to use `/usr/lib/jvm/java-21-openjdk-amd64`.
The app compiles Java source to Java 17. Android SDK/NDK versions follow the
installed Flutter SDK. Keep pubspec.lock in version control for reproducible
package resolution.

## Compatibility

Built-in Kotlin is enabled. The Kotlin JVM plugin declaration in settings.gradle
is not applied; it places Kotlin 2.4.21 on the plugin classpath before AGP so
AGP's bundled older Kotlin does not win resolution.

The installed Flutter Gradle plugin still casts the Android extension to
AbstractAppExtension and uses applicationVariants. Therefore android.newDsl=false
remains required: enabling the new DSL causes a ClassCastException. This is an
SDK limitation, not a version-check bypass. AGP emits legacy DSL deprecation
warnings on direct Gradle runs. Revisit this flag when upgrading Flutter to a
version whose Gradle plugin supports the new Android DSL; AGP 10 removes legacy
support. No warning-suppression or dependency-validation bypass is configured.

Flutter's migrator restores disabled Kotlin defaults when flags are absent, so
android.builtInKotlin=true is explicit. Jetifier is no longer enabled.

All direct and development Dart packages were updated to the current resolvable
releases. cli_util, material_color_utilities and test_api remain constrained by
upstream packages/Flutter. Do not force them with dependency_overrides solely to
remove newer-version notices.

## Verification

Run `flutter build apk --debug`, `flutter test` and `flutter pub outdated`.
For direct Gradle commands use a compatible JDK (Java 21 on this workstation).
Do not use a skip-validation flag to conceal compatibility failures.
