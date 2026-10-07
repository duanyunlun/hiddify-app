import 'dart:io';

import 'package:hiddify/features/system_proxy/data/system_proxy_bypass_store.dart';
import 'package:hiddify/features/system_proxy/model/system_proxy_bypass.dart';
import 'package:hiddify/utils/custom_loggers.dart';

/// Runs a command and collects its result. Injectable so the parsing and the
/// command lines can be tested without a Mac.
typedef SystemProxyCommandRunner = Future<ProcessResult> Function(String executable, List<String> arguments);

/// The macOS system proxy bypass list, which `networksetup` keeps per network
/// service rather than globally.
///
/// The core's darwin implementation accepts a bypass list but never uses it: it
/// only calls `-setwebproxy` / `-setsecurewebproxy` and `...state off`. Nothing
/// therefore maintains this value on macOS either, and a list inherited from
/// another tool has the same effect as on Windows, keeping traffic away from the
/// proxy whatever the rules say.
///
/// Entries are read and written with:
///   `networksetup -getproxybypassdomains <service>`
///   `networksetup -setproxybypassdomains <service> <entry>...`
/// The service is the one backing the current default route, because the list is
/// per service and that is the service the core configures.
class MacProxyBypassStore with InfraLogger implements SystemProxyBypassStore {
  MacProxyBypassStore({SystemProxyCommandRunner? runner}) : _run = runner ?? _defaultRunner;

  final SystemProxyCommandRunner _run;

  static Future<ProcessResult> _defaultRunner(String executable, List<String> arguments) =>
      Process.run(executable, arguments);

  @override
  bool get isSupported => Platform.isMacOS;

  @override
  List<String> get localEntries => kLocalMacSystemProxyBypass;

  @override
  String get separator => '\n';

  /// The network service the core configures, i.e. the one behind the default
  /// route. Returns null when it cannot be determined.
  Future<String?> activeService() async {
    if (!isSupported) return null;
    final device = await _defaultRouteInterface();
    if (device == null) {
      loggy.warning('could not determine the default route interface');
      return null;
    }
    return _serviceForDevice(device);
  }

  Future<String?> _defaultRouteInterface() async {
    try {
      final result = await _run('route', ['-n', 'get', 'default']);
      final output = '${result.stdout}';
      for (final line in output.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.startsWith('interface:')) return trimmed.substring('interface:'.length).trim();
      }
    } catch (e) {
      loggy.warning('could not read the default route: $e');
    }
    return null;
  }

  Future<String?> _serviceForDevice(String device) async {
    try {
      final result = await _run('networksetup', ['-listnetworkserviceorder']);
      final lines = '${result.stdout}'.split('\n').map((line) => line.trim()).toList();
      // Match the device exactly, so en0 does not also match en0.100 or en01.
      final devicePattern = RegExp('Device:\\s*${RegExp.escape(device)}(?=[,)\\s]|\$)');
      for (var index = 0; index < lines.length; index++) {
        // (Hardware Port: Wi-Fi, Device: en0)
        if (!devicePattern.hasMatch(lines[index])) continue;
        // The service name is the line above, shaped "(1) Wi-Fi".
        for (var back = index - 1; back >= 0; back--) {
          final match = RegExp(r'^\(\d+\)\s+(.*)$').firstMatch(lines[back]);
          if (match != null) return match.group(1)!.trim();
        }
      }
    } catch (e) {
      loggy.warning('could not list the network services: $e');
    }
    return null;
  }

  @override
  Future<String?> read() async {
    if (!isSupported) return null;
    final service = await activeService();
    if (service == null) return null;
    try {
      final result = await _run('networksetup', ['-getproxybypassdomains', service]);
      if (result.exitCode != 0) {
        loggy.warning('networksetup -getproxybypassdomains failed: ${result.stderr}');
        return null;
      }
      final output = '${result.stdout}';
      // An untouched service answers "There aren't any bypass domains set on
      // <service>." rather than an empty list.
      if (output.toLowerCase().contains("aren't any bypass domains")) return '';
      return output;
    } catch (e) {
      loggy.warning('could not read the bypass domains: $e');
      return null;
    }
  }

  @override
  Future<List<String>> currentUserEntries() async =>
      userSystemProxyBypassEntries(await read(), localEntries: localEntries, separator: separator);

  @override
  Future<bool> write(List<String> userEntries) async {
    if (!isSupported) return false;
    final service = await activeService();
    if (service == null) {
      loggy.error('could not determine the network service to write the bypass domains to');
      return false;
    }
    final entries = composeSystemProxyOverride(userEntries, localEntries: localEntries);
    try {
      final result = await _run('networksetup', ['-setproxybypassdomains', service, ...entries]);
      if (result.exitCode != 0) {
        // The usual cause is the missing privilege: changing a network service
        // needs an administrator.
        loggy.error('networksetup -setproxybypassdomains failed: ${result.stderr}');
        return false;
      }
      loggy.debug('wrote bypass domains for $service: ${entries.join(", ")}');
      return true;
    } catch (e) {
      loggy.error('could not write the bypass domains: $e');
      return false;
    }
  }
}
