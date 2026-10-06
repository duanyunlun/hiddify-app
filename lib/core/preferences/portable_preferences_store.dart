import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

/// A [SharedPreferencesStorePlatform] backed by a JSON file.
///
/// The default Windows store writes to `%APPDATA%\<company>\<product>`, which is
/// outside the portable data directory. A portable build therefore shared its
/// settings with every other portable build on the machine, so copying the
/// package into a fresh folder did not produce a fresh application: rule sets
/// and other settings from an earlier run reappeared. Installing this store
/// before the first `SharedPreferences.getInstance()` keeps the preferences
/// inside the portable directory, which is what makes the copy self-contained.
class PortablePreferencesStore extends SharedPreferencesStorePlatform {
  PortablePreferencesStore(this.file);

  final File file;

  Map<String, Object>? _cache;

  Map<String, Object> get _values {
    final cached = _cache;
    if (cached != null) return cached;
    final loaded = <String, Object>{};
    try {
      if (file.existsSync()) {
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final key = entry.key;
            final value = entry.value;
            if (key is String && value != null) loaded[key] = value as Object;
          }
        }
      }
    } catch (_) {
      // A corrupt or unreadable file must not stop the app from starting; the
      // store simply begins empty and is rewritten on the next change.
      loaded.clear();
    }
    return _cache = loaded;
  }

  Future<void> _flush() async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(_values), flush: true);
  }

  bool _matches(String key, PreferencesFilter filter) {
    if (!key.startsWith(filter.prefix)) return false;
    final allowList = filter.allowList;
    return allowList == null || allowList.contains(key);
  }

  @override
  Future<bool> clear() async {
    _values.clear();
    await _flush();
    return true;
  }

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async {
    final values = _values;
    final matching = values.keys.where((key) => _matches(key, parameters.filter)).toList(growable: false);
    for (final key in matching) {
      values.remove(key);
    }
    await _flush();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => Map<String, Object>.from(_values);

  @override
  Future<Map<String, Object>> getAllWithParameters(GetAllParameters parameters) async => Map<String, Object>.fromEntries(
    _values.entries.where((entry) => _matches(entry.key, parameters.filter)),
  );

  @override
  Future<bool> remove(String key) async {
    _values.remove(key);
    await _flush();
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    _values[key] = value;
    await _flush();
    return true;
  }
}
