import 'package:flutter/services.dart' show appFlavor;

/// Distribution channel this binary was built for, from `flutter build --flavor`.
///
/// - **`github`** (also the value when no `--flavor` is passed — plain
///   `flutter run`, `flutter test`): sideload builds published to GitHub
///   Releases. The in-app self-updater is active.
/// - **`play`**: Google Play build. The self-updater is compiled out and the
///   `REQUEST_INSTALL_PACKAGES` / `INTERNET` permissions and the `FileProvider`
///   are absent from the merged manifest (see `android/app/src/github/`).
///   Google Play forbids apps that update themselves outside Play.
const bool kIsPlayBuild = appFlavor == 'play';

/// Whether the GitHub Releases self-update feature is available in this build.
///
/// Guards [updateCheckProvider] and the update dialog. When false the app never
/// contacts GitHub and never attempts an APK install.
const bool kSelfUpdateEnabled = !kIsPlayBuild;
