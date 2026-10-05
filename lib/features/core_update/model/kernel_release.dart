import 'dart:io';

/// A downloadable core (kernel) build.
class KernelRelease {
  const KernelRelease({
    required this.tag,
    required this.version,
    required this.preRelease,
    required this.publishedAt,
    required this.asset,
  });

  /// Release tag, for example `v4.1.0`.
  final String tag;

  /// Version without the leading `v`.
  final String version;

  final bool preRelease;
  final DateTime publishedAt;

  /// The asset matching the current platform, or null when the release does not
  /// ship one.
  final KernelAsset? asset;

  String get label => preRelease ? '$version (pre-release)' : version;

  static KernelRelease? fromJson(Map<String, dynamic> json, String assetName) {
    final tag = json['tag_name'] as String?;
    if (tag == null || tag.isEmpty) return null;
    final assets = json['assets'];
    KernelAsset? asset;
    if (assets is List) {
      for (final item in assets) {
        if (item is! Map<String, dynamic>) continue;
        if (item['name'] == assetName) {
          asset = KernelAsset.fromJson(item);
          break;
        }
      }
    }
    return KernelRelease(
      tag: tag,
      version: tag.startsWith('v') ? tag.substring(1) : tag,
      preRelease: (json['prerelease'] as bool?) ?? false,
      publishedAt: DateTime.tryParse((json['published_at'] as String?) ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      asset: asset,
    );
  }
}

/// One downloadable file of a release.
class KernelAsset {
  const KernelAsset({
    required this.name,
    required this.url,
    this.size = 0,
    this.sha256,
  });

  final String name;
  final String url;
  final int size;

  /// `sha256:<hex>` digest reported by the GitHub API, when available. Used to
  /// verify the download; an update is refused without it.
  final String? sha256;

  static KernelAsset? fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String?;
    final url = json['browser_download_url'] as String?;
    if (name == null || url == null) return null;
    final digest = json['digest'] as String?;
    String? sha256;
    if (digest != null && digest.startsWith('sha256:')) {
      sha256 = digest.substring('sha256:'.length);
    }
    return KernelAsset(
      name: name,
      url: url,
      size: (json['size'] as num?)?.toInt() ?? 0,
      sha256: sha256,
    );
  }
}

/// Which artefact name this platform needs. Mirrors the names the release
/// workflow publishes (see the core repository's `build.yml` matrix).
String? kernelAssetNameForCurrentPlatform() {
  if (Platform.isWindows) return 'hiddify-lib-windows-amd64.tar.gz';
  if (Platform.isLinux) return 'hiddify-lib-linux-amd64.tar.gz';
  if (Platform.isMacOS) return 'hiddify-lib-macos.tar.gz';
  return null;
}

/// The file the app loads at runtime, inside the downloaded archive.
String? kernelLibraryFileName() {
  if (Platform.isWindows) return 'hiddify-core.dll';
  if (Platform.isMacOS) return 'hiddify-core.dylib';
  if (Platform.isLinux) return 'hiddify-core.so';
  return null;
}

/// Whether the running core can be replaced by swapping a file.
///
/// On Android the core is compiled into the APK, so it cannot be swapped at
/// runtime and the whole feature is disabled there.
bool get isKernelReplaceable => kernelAssetNameForCurrentPlatform() != null && kernelLibraryFileName() != null;

/// State of the core version screen.
class KernelUpdateState {
  const KernelUpdateState({
    this.releases = const [],
    this.currentTag,
    this.isLoading = false,
    this.isWorking = false,
    this.pendingTag,
    this.error,
    this.message,
  });

  final List<KernelRelease> releases;

  /// Tag of the core that was last installed through this screen. The running
  /// core reports `unknown` for its version, so this is what the app can show.
  final String? currentTag;

  final bool isLoading;
  final bool isWorking;

  /// Tag staged on disk, waiting for a restart to take effect.
  final String? pendingTag;

  final String? error;
  final String? message;

  bool get hasPendingRestart => pendingTag != null;

  KernelUpdateState copyWith({
    List<KernelRelease>? releases,
    String? currentTag,
    bool? isLoading,
    bool? isWorking,
    String? pendingTag,
    String? error,
    String? message,
    bool clearPending = false,
    bool clearError = false,
    bool clearMessage = false,
  }) => KernelUpdateState(
    releases: releases ?? this.releases,
    currentTag: currentTag ?? this.currentTag,
    isLoading: isLoading ?? this.isLoading,
    isWorking: isWorking ?? this.isWorking,
    pendingTag: clearPending ? null : (pendingTag ?? this.pendingTag),
    error: clearError ? null : (error ?? this.error),
    message: clearMessage ? null : (message ?? this.message),
  );
}
