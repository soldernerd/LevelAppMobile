// lib/services/update_service.dart
// GitHub Releases self-update service.
//
// All platform I/O (HTTP, file, permissions, installer) is isolated here per
// CLAUDE.md architecture constraints — no flutter_blue_plus or platform SDK
// imports allowed in lib/ui/ or lib/providers/.

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _apiUrl =
    'https://api.github.com/repos/soldernerd/LevelAppMobile/releases/latest';
const _apkAssetName = 'app-release.apk';
const _skipKey = 'skipped_update_version';

/// Holds information about a newer GitHub release.
class UpdateInfo {
  /// Raw tag string as returned by the GitHub API, e.g. "v0.1.1".
  final String tagName;

  /// Direct download URL for the app-release.apk asset.
  final String downloadUrl;

  /// Version string with leading 'v' stripped, e.g. "0.1.1".
  final String version;

  const UpdateInfo({
    required this.tagName,
    required this.downloadUrl,
    required this.version,
  });
}

/// Service layer for GitHub Releases self-update.
///
/// All methods are static — no instance state. Follows the [StatePacket.parse]
/// static service convention established in lib/ble/ble_protocol.dart.
class UpdateService {
  /// Checks whether a newer GitHub release is available.
  ///
  /// Returns an [UpdateInfo] when a newer, non-skipped release with the
  /// expected APK asset exists.  Returns null when up-to-date, already
  /// skipped, or on any network/parse error (D-01: silent fail, UPD-05).
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final dio = Dio();
      final response = await dio.get(
        _apiUrl,
        options: Options(
          headers: {'User-Agent': 'soldernerd-inclinometer'},
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );

      // dio may return the body as a pre-decoded Map or as a raw JSON string.
      final data = response.data is String
          ? jsonDecode(response.data as String) as Map<String, dynamic>
          : response.data as Map<String, dynamic>;

      final tagName = data['tag_name'] as String; // e.g. "v0.1.1"
      final remoteVer = tagName.replaceFirst('v', ''); // "0.1.1"

      final packageInfo = await PackageInfo.fromPlatform();
      final localVer = packageInfo.version; // e.g. "0.1.0"

      if (!_isNewer(remoteVer, localVer)) return null;

      // Check whether user has already skipped this exact release (D-03).
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_skipKey) == tagName) return null;

      // Locate the app-release.apk asset in the release (D-10).
      final assets = data['assets'] as List<dynamic>;
      final asset = assets.firstWhere(
        (a) => (a as Map<String, dynamic>)['name'] == _apkAssetName,
        orElse: () => null,
      ) as Map<String, dynamic>?;

      if (asset == null) return null;

      return UpdateInfo(
        tagName: tagName,
        downloadUrl: asset['browser_download_url'] as String,
        version: remoteVer,
      );
    } catch (_) {
      // D-01: swallow ALL exceptions — network error, timeout, malformed JSON.
      return null;
    }
  }

  /// Downloads the APK to the app cache directory.
  ///
  /// [onProgress] receives a value in [0.0, 1.0] as bytes arrive.  When the
  /// server omits Content-Length the callback is not called (Pitfall 4 guard).
  /// May throw — the caller (dialog) handles failure state.
  static Future<String> downloadApk(
    String url,
    void Function(double progress) onProgress,
  ) async {
    final dir = await getTemporaryDirectory();
    final savePath = '${dir.path}/$_apkAssetName';
    final dio = Dio();
    await dio.download(
      url,
      savePath,
      deleteOnError: true,
      onReceiveProgress: (received, total) {
        // Guard: total == -1 when server omits Content-Length (Pitfall 4).
        if (total > 0) onProgress(received / total);
      },
      options: Options(receiveTimeout: const Duration(minutes: 10)),
    );
    return savePath;
  }

  /// Requests the install-unknown-apps permission then launches the installer.
  ///
  /// On Android 8+ (API 26+) [Permission.requestInstallPackages] does NOT
  /// show a dialog — it redirects to Settings (Pitfall 3 / UPD-06).  After
  /// the user returns the status is re-checked; if still denied the method
  /// returns silently.
  static Future<void> installApk(String apkPath) async {
    if (Platform.isAndroid) {
      final status = await Permission.requestInstallPackages.status;
      if (!status.isGranted) {
        await Permission.requestInstallPackages.request();
        final refreshed = await Permission.requestInstallPackages.status;
        if (!refreshed.isGranted) return; // user declined — abort silently
      }
    }
    // Non-done results (e.g. fileNotFound, permissionDenied) are swallowed —
    // consistent with the phase's fail-quiet posture.
    await OpenFilex.open(apkPath);
  }

  /// Persists [tagName] as the skipped version so the dialog is suppressed
  /// for this specific release on all future cold starts (D-03 / D-04).
  static Future<void> skipVersion(String tagName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_skipKey, tagName);
  }

  /// Compares two semver strings segment-by-segment using integer arithmetic.
  ///
  /// Returns true only when [remote] is strictly newer than [local].
  /// Absent segments are treated as 0 (e.g. "1.0" == "1.0.0").
  ///
  /// This avoids the lexicographic pitfall where "1.9.0" > "1.10.0".
  @visibleForTesting
  static bool isNewerForTest(String remote, String local) =>
      _isNewer(remote, local);

  static bool _isNewer(String remote, String local) {
    final r = remote.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final l = local.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final rv = i < r.length ? r[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (rv > lv) return true;
      if (rv < lv) return false;
    }
    return false; // equal — no update needed
  }
}
