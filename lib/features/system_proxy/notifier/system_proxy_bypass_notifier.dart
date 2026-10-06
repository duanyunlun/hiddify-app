import 'dart:async';
import 'dart:convert';

import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/system_proxy/data/system_proxy_override_store.dart';
import 'package:hiddify/features/system_proxy/model/system_proxy_bypass.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _kBypassKey = 'system-proxy-bypass';
const _kBypassAdoptedKey = 'system-proxy-bypass-adopted';

/// The user's own system proxy bypass entries.
class SystemProxyBypassState {
  const SystemProxyBypassState({this.entries = const [], this.applied = true});

  final List<String> entries;

  /// False when the registry could not be written (for example on a platform
  /// without the setting), so the screen can say the list is only stored.
  final bool applied;

  SystemProxyBypassState copyWith({List<String>? entries, bool? applied}) =>
      SystemProxyBypassState(entries: entries ?? this.entries, applied: applied ?? this.applied);
}

/// Keeps the Windows `ProxyOverride` value in sync with a user editable list.
///
/// The list is the user's *extra* entries only; the loopback and private ranges
/// are added on every write and cannot be removed by accident.
class SystemProxyBypassNotifier extends StateNotifier<SystemProxyBypassState> {
  SystemProxyBypassNotifier(this._ref, [SystemProxyOverrideStore? store])
    : _store = store ?? SystemProxyOverrideStore(),
      super(const SystemProxyBypassState()) {
    _restore();
  }

  final Ref _ref;
  final SystemProxyOverrideStore _store;

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

  void _restore() {
    final adopted = _adoptedPref.read() ?? false;
    final List<String> entries;
    if (adopted) {
      entries = _decode(_entriesPref.read());
    } else {
      // First run: take over whatever a previous tool left in the registry
      // instead of discarding it silently. The user sees the entries in the
      // list and decides what to keep.
      entries = _store.currentUserEntries();
      unawaited(_adoptedPref.write(true));
      _persist(entries);
    }
    state = state.copyWith(entries: entries, applied: _store.isSupported && _store.write(entries));
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

  void _commit(List<String> entries) {
    _persist(entries);
    state = state.copyWith(entries: entries, applied: _store.isSupported && _store.write(entries));
  }

  /// Returns the reason the entry was rejected, or null when it was added.
  String? add(String entry) {
    final problem = validateSystemProxyBypassEntry(entry);
    if (problem != null) return problem;
    final trimmed = entry.trim();
    if (state.entries.any((existing) => existing.toLowerCase() == trimmed.toLowerCase())) return 'duplicate';
    _commit([...state.entries, trimmed]);
    return null;
  }

  void remove(String entry) =>
      _commit(state.entries.where((existing) => existing != entry).toList(growable: false));

  String? update(String previous, String entry) {
    final problem = validateSystemProxyBypassEntry(entry);
    if (problem != null) return problem;
    final trimmed = entry.trim();
    if (state.entries.any((existing) => existing != previous && existing.toLowerCase() == trimmed.toLowerCase())) {
      return 'duplicate';
    }
    _commit(state.entries.map((existing) => existing == previous ? trimmed : existing).toList(growable: false));
    return null;
  }

  /// Removes every extra entry, leaving the loopback and private ranges.
  void clear() => _commit(const []);

  /// Reads the registry again, for the case where something else changed it.
  void reloadFromSystem() => _commit(_store.currentUserEntries());

  /// The value that is in effect, for display.
  List<String> get effectiveEntries => composeSystemProxyOverride(state.entries);
}

final systemProxyBypassProvider = StateNotifierProvider<SystemProxyBypassNotifier, SystemProxyBypassState>(
  (ref) => SystemProxyBypassNotifier(ref),
);
