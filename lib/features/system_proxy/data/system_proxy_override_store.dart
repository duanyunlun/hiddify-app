import 'dart:io';

import 'package:hiddify/features/system_proxy/model/system_proxy_bypass.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:win32_registry/win32_registry.dart';

/// Reads and writes the Windows system proxy bypass list.
///
/// The core enables the system proxy itself (the mixed inbound is generated with
/// `set_system_proxy`) and passes an empty bypass list, and sing-box only writes
/// `ProxyOverride` when that list is non-empty. This app is therefore the only
/// writer of the value, which is what makes it safe to compose it from the local
/// entries plus the user's own: a list left behind by another tool is replaced
/// rather than silently kept.
///
/// The write does not need to notify WinINET: sing-box calls `InternetSetOption`
/// when it enables the proxy, which makes Windows re-read the whole setting,
/// including this value.
class SystemProxyOverrideStore with InfraLogger {
  /// [keyPath] is a parameter so a test can exercise real registry reads and
  /// writes against a scratch key instead of the live proxy settings.
  SystemProxyOverrideStore({String? keyPath}) : _keyPath = keyPath ?? internetSettingsKeyPath;

  static const internetSettingsKeyPath = r'Software\Microsoft\Windows\CurrentVersion\Internet Settings';
  static const _valueName = 'ProxyOverride';

  final String _keyPath;

  bool get isSupported => Platform.isWindows;

  /// The raw value currently in the registry, or null when unreadable.
  String? read() {
    if (!isSupported) return null;
    RegistryKey? key;
    try {
      key = Registry.openPath(RegistryHive.currentUser, path: _keyPath);
      return key.getStringValue(_valueName);
    } catch (e) {
      loggy.warning('could not read $_valueName: $e');
      return null;
    } finally {
      key?.close();
    }
  }

  /// The user entries currently in effect, i.e. whatever a previous tool left
  /// behind minus the entries this app maintains.
  List<String> currentUserEntries() => userSystemProxyBypassEntries(read());

  /// Writes the local entries plus [userEntries]. Returns false when the write
  /// failed or the platform has no such setting.
  bool write(List<String> userEntries) {
    if (!isSupported) return false;
    RegistryKey? key;
    try {
      // createKey opens the key when it exists and creates it otherwise, so the
      // write does not depend on the key already being there.
      key = Registry.currentUser.createKey(_keyPath);
      key.createValue(RegistryValue.string(_valueName, systemProxyOverrideValue(userEntries)));
      loggy.debug('wrote $_valueName: ${systemProxyOverrideValue(userEntries)}');
      return true;
    } catch (e) {
      loggy.error('could not write $_valueName: $e');
      return false;
    } finally {
      key?.close();
    }
  }
}
