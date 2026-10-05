import 'package:hiddify/features/core_update/data/kernel_release_repository.dart';
import 'package:hiddify/features/core_update/model/kernel_release.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class KernelUpdateNotifier extends StateNotifier<KernelUpdateState> {
  KernelUpdateNotifier(this._repo)
    : super(
        KernelUpdateState(
          currentTag: _repo.installedTag,
          pendingTag: _repo.pendingTag,
        ),
      );

  final KernelReleaseRepository _repo;

  String get repository => _repo.repository;

  Future<void> setRepository(String value) async {
    await _repo.setRepository(value);
    state = state.copyWith(releases: const [], clearError: true);
  }

  /// Loads the list of cores available for this platform.
  Future<void> loadReleases({bool includePreReleases = true}) async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, clearError: true, clearMessage: true);
    try {
      final releases = await _repo.listReleases(includePreReleases: includePreReleases);
      state = state.copyWith(releases: releases, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Downloads and stages a core. It takes effect after a restart.
  Future<bool> install(KernelRelease release) async {
    if (state.isWorking) return false;
    state = state.copyWith(isWorking: true, clearError: true, clearMessage: true);
    try {
      await _repo.downloadAndStage(release);
      state = state.copyWith(isWorking: false, pendingTag: release.tag);
      return true;
    } catch (e) {
      state = state.copyWith(isWorking: false, error: e.toString());
      return false;
    }
  }

  Future<void> discardPending() async {
    await _repo.discardPending();
    state = state.copyWith(isWorking: false, clearPending: true, clearError: true, clearMessage: true);
  }

  /// Records that the staged core is now the running one. Called after a
  /// successful restart.
  Future<void> markPendingAsCurrent() async {
    final pending = state.pendingTag;
    if (pending == null) return;
    await _repo.setInstalledTag(pending);
    await _repo.setPendingTag(null);
    state = state.copyWith(currentTag: pending, clearPending: true);
  }
}

final kernelUpdateProvider = StateNotifierProvider<KernelUpdateNotifier, KernelUpdateState>(
  (ref) => KernelUpdateNotifier(ref.watch(kernelReleaseRepositoryProvider)),
);
