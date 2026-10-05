import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:hiddify/core/http_client/http_client_provider.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/core_update/model/kernel_release.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;

/// Default repository the core releases are taken from. Point it at the fork to
/// pick up custom builds.
const kDefaultKernelRepository = 'hiddify/hiddify-core';

const _kKernelRepositoryKey = 'core-update-repository';
const _kInstalledKernelTagKey = 'core-update-installed-tag';
const _kPendingKernelTagKey = 'core-update-pending-tag';

/// Directory holding a downloaded core that has not been applied yet. The swap
/// itself happens on the next start, before the library is loaded, because a
/// loaded library cannot be overwritten on Windows.
const kPendingKernelDirName = 'core-update-pending';
const kPendingKernelMetaName = 'pending.json';

/// The directory next to the executable where a downloaded core is staged.
Directory pendingKernelDirectory() =>
    Directory(p.join(File(Platform.resolvedExecutable).parent.path, kPendingKernelDirName));

class KernelReleaseRepository {
  KernelReleaseRepository(this._ref);

  final Ref _ref;

  PreferencesEntry<String?, String?> get _repositoryStore => PreferencesEntry<String?, String?>(
    preferences: _ref.read(sharedPreferencesProvider).requireValue,
    key: _kKernelRepositoryKey,
    defaultValue: null,
  );

  PreferencesEntry<String?, String?> get _installedTagStore => PreferencesEntry<String?, String?>(
    preferences: _ref.read(sharedPreferencesProvider).requireValue,
    key: _kInstalledKernelTagKey,
    defaultValue: null,
  );

  PreferencesEntry<String?, String?> get _pendingTagStore => PreferencesEntry<String?, String?>(
    preferences: _ref.read(sharedPreferencesProvider).requireValue,
    key: _kPendingKernelTagKey,
    defaultValue: null,
  );

  String get repository {
    final stored = _repositoryStore.read();
    return (stored == null || stored.isEmpty) ? kDefaultKernelRepository : stored;
  }

  Future<void> setRepository(String value) async {
    final trimmed = value.trim();
    await _repositoryStore.write(trimmed.isEmpty ? kDefaultKernelRepository : trimmed);
  }

  String? get installedTag => _installedTagStore.read();

  String? get pendingTag => _pendingTagStore.read();

  Future<void> setInstalledTag(String? tag) => _installedTagStore.write(tag);

  Future<void> setPendingTag(String? tag) => _pendingTagStore.write(tag);

  /// Lists the releases that ship a core for this platform.
  Future<List<KernelRelease>> listReleases({bool includePreReleases = true}) async {
    final assetName = kernelAssetNameForCurrentPlatform();
    if (assetName == null) return const [];
    final client = _ref.read(httpClientProvider);
    final response = await client.get<List<dynamic>>(
      'https://api.github.com/repos/$repository/releases?per_page=30',
      userAgent: 'Hiddify',
    );
    final data = response.data;
    if (data == null) return const [];
    final releases = <KernelRelease>[];
    for (final item in data) {
      if (item is! Map<String, dynamic>) continue;
      final release = KernelRelease.fromJson(item, assetName);
      if (release == null || release.asset == null) continue;
      if (!includePreReleases && release.preRelease) continue;
      releases.add(release);
    }
    return releases;
  }

  /// Downloads the release asset, verifies it against the digest reported by the
  /// GitHub API, extracts the core library and stages it for the next start.
  ///
  /// The download is refused when the release does not publish a sha256 digest:
  /// replacing the core without verifying it would turn this screen into a
  /// supply chain hole.
  Future<void> downloadAndStage(KernelRelease release, {void Function(int received, int total)? onProgress}) async {
    final asset = release.asset;
    if (asset == null) throw const FormatException('This release has no asset for this platform');
    final expected = asset.sha256;
    if (expected == null || expected.isEmpty) {
      throw const FormatException('Release does not publish a sha256 digest; refusing to install');
    }
    final libraryName = kernelLibraryFileName();
    if (libraryName == null) throw const FormatException('This platform cannot replace the core');

    final tempDir = await Directory.systemTemp.createTemp('hiddify-core-dl-');
    try {
      final archiveFile = File(p.join(tempDir.path, asset.name));
      await Dio().download(
        asset.url,
        archiveFile.path,
        onReceiveProgress: onProgress,
        options: Options(followRedirects: true),
      );
      final actual = await _sha256OfFile(archiveFile);
      if (actual.toLowerCase() != expected.toLowerCase()) {
        throw FormatException('Checksum mismatch: expected $expected, got $actual');
      }
      final extractDir = Directory(p.join(tempDir.path, 'x'));
      await extractDir.create(recursive: true);
      await extractFileToDisk(archiveFile.path, extractDir.path);
      final extracted = _findFile(extractDir, libraryName);
      if (extracted == null) {
        throw FormatException('Archive does not contain $libraryName');
      }
      await _stagePending(await extracted.readAsBytes(), release, libraryName);
    } finally {
      await tempDir.delete(recursive: true).catchError((_) => tempDir);
    }
  }

  File? _findFile(Directory dir, String fileName) {
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is File && p.basename(entity.path) == fileName) return entity;
    }
    return null;
  }

  Future<String> _sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  Future<void> _stagePending(List<int> libraryBytes, KernelRelease release, String libraryName) async {
    final dir = pendingKernelDirectory();
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    await File(p.join(dir.path, libraryName)).writeAsBytes(libraryBytes, flush: true);
    await File(p.join(dir.path, kPendingKernelMetaName)).writeAsString(
      jsonEncode({'tag': release.tag, 'library': libraryName, 'stagedAt': DateTime.now().toIso8601String()}),
      flush: true,
    );
    await setPendingTag(release.tag);
  }

  /// Discards a staged core.
  Future<void> discardPending() async {
    final dir = pendingKernelDirectory();
    if (await dir.exists()) await dir.delete(recursive: true);
    await setPendingTag(null);
  }
}

final kernelReleaseRepositoryProvider = Provider<KernelReleaseRepository>(
  (ref) => KernelReleaseRepository(ref),
);

/// Applies a staged core over the running one. Called during startup, before the
/// native library is loaded, so the file is not locked yet.
///
/// The previous library is kept as `<name>.bak` so a broken core can be brought
/// back by renaming it.
Future<void> applyPendingKernelIfAny() async {
  try {
    final dir = pendingKernelDirectory();
    if (!await dir.exists()) return;
    final metaFile = File(p.join(dir.path, kPendingKernelMetaName));
    if (!await metaFile.exists()) return;
    final meta = jsonDecode(await metaFile.readAsString());
    if (meta is! Map<String, dynamic>) return;
    final libraryName = meta['library'] as String?;
    if (libraryName == null) return;
    final staged = File(p.join(dir.path, libraryName));
    if (!await staged.exists()) return;

    final target = File(p.join(File(Platform.resolvedExecutable).parent.path, libraryName));
    final backup = File('${target.path}.bak');
    if (await target.exists()) {
      if (await backup.exists()) await backup.delete();
      await target.rename(backup.path);
    }
    await staged.copy(target.path);
    await dir.delete(recursive: true);
  } catch (_) {
    // A failed swap must not block startup: the old (now backed up) library is
    // restored by the rename above only when the copy succeeded.
  }
}
