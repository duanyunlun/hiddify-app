import 'dart:io';

import 'package:hiddify/features/system_proxy/data/mac_proxy_bypass_store.dart';
import 'package:hiddify/features/system_proxy/data/windows_proxy_override_store.dart';
import 'package:hiddify/features/system_proxy/model/system_proxy_bypass.dart';

/// Reads and writes the bypass list of the operating system proxy.
///
/// The routing decision belongs to the core, so the list normally holds nothing
/// but the entries the platform maintains itself. It exists because a bypass
/// list can also be inherited from another program, and an entry there keeps
/// traffic away from the proxy no matter what the app's rules say.
abstract interface class SystemProxyBypassStore {
  /// False when the platform has no such setting, in which case the list is only
  /// stored and shown.
  bool get isSupported;

  /// Entries the platform maintains itself and which cannot be removed.
  List<String> get localEntries;

  /// How the platform separates entries in its own representation.
  String get separator;

  /// The list currently in effect, exactly as the platform reports it.
  Future<String?> read();

  /// Everything in effect that this app does not own.
  Future<List<String>> currentUserEntries();

  /// Writes [localEntries] followed by [userEntries]. Returns false when the
  /// write failed.
  Future<bool> write(List<String> userEntries);
}

/// Used on the platforms that have no system proxy bypass list to manage.
class UnsupportedSystemProxyBypassStore implements SystemProxyBypassStore {
  const UnsupportedSystemProxyBypassStore();

  @override
  bool get isSupported => false;

  @override
  List<String> get localEntries => const [];

  @override
  String get separator => ';';

  @override
  Future<String?> read() async => null;

  @override
  Future<List<String>> currentUserEntries() async => const [];

  @override
  Future<bool> write(List<String> userEntries) async => false;
}

/// The store for the running platform.
SystemProxyBypassStore createSystemProxyBypassStore() {
  if (Platform.isWindows) return WindowsProxyOverrideStore();
  if (Platform.isMacOS) return MacProxyBypassStore();
  return const UnsupportedSystemProxyBypassStore();
}

/// Convenience for the local entries of a store, used by the editor to show what
/// is always kept.
List<String> localEntriesOf(SystemProxyBypassStore store) =>
    store.localEntries.isEmpty ? kLocalSystemProxyBypass : store.localEntries;
