import 'dart:async';
import 'dart:convert';

import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/system_proxy/data/system_proxy_bypass_store.dart';
import 'package:hiddify/features/system_proxy/model/system_proxy_bypass.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _kBypassKey = 'system-proxy-bypass';
const _kBypassAdoptedKey = 'system-proxy-bypass-adopted';

/// The user's own system proxy bypass entries.
class SystemProxyBypassState {
  const SystemProxyBypassState({this.entries = const [], this.applied = true, this.loaded = false});

  final List<String> entries;

  /// False when the list could not be written (for example on a platform without
  /// the setting, or without the privilege to change it), so the screen can say
  /// the list is only stored.
  final bool applied;

  /// False until the current value has been read back from the system.
  final bool loaded;

  SystemProxyBypassState copyWith({List<String>? entries, bool? applied, bool? loaded}) => SystemProxyBypassState(
    entries: entries ?? this.entries,
    applied: applied ?? this.applied,
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
    final applied = _store.isSupported && await _store.write(entries);
    if (!mounted) return;
    state = state.copyWith(entries: entries, applied: applied, loaded: true);
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

  Future<void> _commit(List<String> entries) async {
    _persist(entries);
    final applied = _store.isSupported && await _store.write(entries);
    if (!mounted) return;
    state = state.copyWith(entries: entries, applied: applied, loaded: true);
  }

  /// Replaces the whole list, as typed in the editor.
  Future<void> setEntries(List<String> entries) => _commit(entries);

  /// Removes every extra entry, leaving what the platform maintains.
  Future<void> clear() => _commit(const []);

  /// Reads the setting again, for the case where something else changed it.
  Future<void> reloadFromSystem() async => _commit(await _store.currentUserEntries());

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
