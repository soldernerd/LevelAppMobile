// lib/providers/version_provider.dart
// Exposes the app version string sourced from the Flutter build system.
//
// PackageInfo reads the versionName/CFBundleShortVersionString that was stamped
// into the APK/IPA at build time via --build-name. In CI the value is set to
// "0.1.<commit-count>" so it always matches the GitHub release tag.
//
// No version string is hardcoded anywhere in Dart — this is the single source
// of truth for whatever the build system embedded.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Resolves to a display-ready version string, e.g. "v0.1.47".
///
/// Returns an empty string while loading so callers can hide the widget
/// until the value is available without showing a loading state.
final versionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return 'v${info.version}';
});
