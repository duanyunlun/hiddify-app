import 'dart:async';
import 'dart:convert';

import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/system_proxy/data/system_proxy_bypass_store.dart';
import 'package:hiddify/features/system_proxy/model/system_proxy_bypass.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _kBypassKey = 'system-proxy-bypass';
const _kBypassAdoptedKey = 'system-proxy-bypass-adopted';

/// Where the list stands relative to the system.
enum SystemProxyBypassApplyState {
  /// The list is what the system has.
  synced,

  /// The user changed the list and it has not been written yet. macOS needs an
  /// authorisation prompt to write, so its edits are held until asked for.
  pending,

  /// The last write failed: no privilege, the prompt was dismissed, or the
  /// platform does not support the setting.
  failed,

  /// The platform has no system proxy bypass list at all.
  unsupported,
}

/// The user's own system proxy bypass entries.
class SystemProxyBypassState {
  const SystemProxyBypassState({
    this.entries = const [],
    this.applyState = SystemProxyBypassApplyState.synced,
    this.loaded = false,
  });

  final List<String> entries;
  final SystemProxyBypassApplyState applyState;

  /// False until the current value has been read back from the system.
  final bool loaded;

  bool get canApply => applyState == SystemProxyBypassApplyState.pending;
  bool get hasFailed => applyState == SystemProxyBypassApplyState.failed;

  SystemProxyBypassState copyWith({
    List<String>? entries,
    SystemProxyBypassApplyState? applyState,
    bool? loaded,
  }) => SystemProxyBypassState(
    entries: entries ?? this.entries,
    applyState: applyState ?? this.applyState,
    loaded: loaded ?? this.loaded,
  );
}

/// Keeps the operating system proxy bypass list in sync with a user editable
/// list.
///
/// The list is the user's *extra* entries only; the entries the platform
/// maintains itself are added on every write and cannot be removed by accident.
class SystemProxyBypassNotifier extends StateNotifier<SystemProxyBypassState> {
  SystemProxyBypassNotifier(this._ref, SystemProxyBypassStore? store)
    : _store = store ?? createSystemProxyBypassStore(),
      super(const SystemProxyBypassState()) {
    unawaited(_restore());
  }

  final Ref _ref;
  final SystemProxyBypassStore _store;

  /// False when the platform has no bypass list to manage.
  bool get isSupported => _store.isSupported;

  /// True when writing raises an authorisation prompt, so the screen offers an
  /// explicit apply instead of writing while the user types.
  bool get requiresAuthorisation => _store.requiresAuthorisationForWrite;

  /// Entries the platform keeps whatever the user does.
  List<String> get localEntries => localEntriesOf(_store);

  /// How the platform separates entries, for the editor's preview.
  String get separator => _store.separator;

  PreferencesEntry<String?, String?> get _entriesPref => PreferencesEntry<String?, String?>(
    preferences: _ref.read(sharedPreferencesProvider).requireValue,
    key: _kBypassKey,
    defaultValue: null,
  );

  PreferencesEntry<bool?, bool?> get _adoptedPref => PreferencesEntry<bool?, bool?>(
    preferences: _ref.read(sharedPreferencesProvider).requireValue,
    key: _kBypassAdoptedKey,
    defaultValue: null,
  );

  Future<void> _restore() async {
    if (!_store.isSupported) {
      state = state.copyWith(loaded: true, applyState: SystemProxyBypassApplyState.unsupported);
      return;
    }
    final adopted = _adoptedPref.read() ?? false;
    final List<String> entries;
    if (adopted) {
      entries = _decode(_entriesPref.read());
    } else {
      // First run: take over whatever a previous tool left in place instead of
      // discarding it silently. The user sees the entries in the list and
      // decides what to keep.
      entries = await _store.currentUserEntries();
      unawaited(_adoptedPref.write(true));
      _persist(entries);
    }
    // Writing at startup is only acceptable where it cannot prompt: on macOS the
    // system already holds whatever was read, so there is nothing to write.
    var applyState = SystemProxyBypassApplyState.synced;
    if (!_store.requiresAuthorisationForWrite && !await _store.write(entries)) {
      applyState = SystemProxyBypassApplyState.failed;
    }
    if (!mounted) return;
    state = state.copyWith(entries: entries, applyState: applyState, loaded: true);
  }

  List<String> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty).toList(growable: false);
      }
    } catch (_) {
      // A corrupt value must not stop the app from starting.
    }
    return const [];
  }

  void _persist(List<String> entries) => unawaited(_entriesPref.write(jsonEncode(entries)));

  /// Writes [entries] to the system and reports the outcome.
  Future<void> _apply(List<String> entries) async {
    final written = await _store.write(entries);
    if (!mounted) return;
    state = state.copyWith(
      applyState: written ? SystemProxyBypassApplyState.synced : SystemProxyBypassApplyState.failed,
    );
  }

  /// Replaces the whole list.
  ///
  /// Where writing is free the value is written straight away; where it prompts
  /// for authorisation the new list is only remembered, and [apply] performs the
  /// write when the user asks.
  Future<void> setEntries(List<String> entries) async {
    _persist(entries);
    if (_store.requiresAuthorisationForWrite) {
      if (!mounted) return;
      state = state.copyWith(
        entries: entries,
        loaded: true,
        applyState: _store.isSupported ? SystemProxyBypassApplyState.pending : SystemProxyBypassApplyState.unsupported,
      );
      return;
    }
    if (!mounted) return;
    state = state.copyWith(entries: entries, loaded: true);
    await _apply(entries);
  }

  /// Removes every extra entry, leaving what the platform maintains.
  Future<void> clear() => setEntries(const []);

  /// Writes the current list, raising the authorisation prompt where needed.
  Future<void> apply() => _apply(state.entries);

  /// Reads the setting again, for the case where something else changed it.
  Future<void> reloadFromSystem() async {
    final entries = await _store.currentUserEntries();
    _persist(entries);
    if (!mounted) return;
    state = state.copyWith(entries: entries, loaded: true, applyState: SystemProxyBypassApplyState.synced);
  }

  /// The value that is in effect, for display.
  List<String> get effectiveEntries =>
      composeSystemProxyOverride(state.entries, localEntries: localEntriesOf(_store));
}

/// Overridable so a test can point the store at a scratch registry key, or at a
/// fake command runner, instead of the machine's real network settings.
final systemProxyBypassStoreProvider = Provider<SystemProxyBypassStore>((ref) => createSystemProxyBypassStore());

final systemProxyBypassProvider = StateNotifierProvider<SystemProxyBypassNotifier, SystemProxyBypassState>(
  (ref) => SystemProxyBypassNotifier(ref, ref.read(systemProxyBypassStoreProvider)),
);
