/// The Windows system proxy keeps a bypass list (`ProxyOverride`): hosts and
/// addresses in it are contacted directly instead of through the proxy.
///
/// This app deliberately keeps the *routing* decision inside the core, where the
/// rules live, so the system proxy should not pre-filter traffic. Two things
/// still make the list worth managing:
///
/// * the loopback and private ranges must stay, otherwise local services and the
///   LAN become unreachable;
/// * a list can be left behind by another tool. sing-box only writes
///   `ProxyOverride` when the core gives it a non-empty bypass list, which this
///   configuration does not, so a stale entry such as `*.steampowered.com` from
///   an earlier program keeps the browser away from the proxy and the site fails
///   with a connection reset while every rule in the app says it should work.
library;

/// Entries that are always kept: loopback, the private ranges and `<local>`.
///
/// Windows also skips local addresses on its own, but keeping them explicit is
/// what the platform's own tooling writes and costs nothing.
const kLocalSystemProxyBypass = <String>[
  'localhost',
  '127.*',
  '10.*',
  '172.16.*',
  '172.17.*',
  '172.18.*',
  '172.19.*',
  '172.20.*',
  '172.21.*',
  '172.22.*',
  '172.23.*',
  '172.24.*',
  '172.25.*',
  '172.26.*',
  '172.27.*',
  '172.28.*',
  '172.29.*',
  '172.30.*',
  '172.31.*',
  '192.168.*.*',
  '<local>',
];

/// Splits a `ProxyOverride` value into its entries.
List<String> parseSystemProxyOverride(String? raw) {
  if (raw == null) return const [];
  return raw.split(';').map((entry) => entry.trim()).where((entry) => entry.isNotEmpty).toList(growable: false);
}

/// True when [entry] is one of the entries this app always maintains itself.
bool isLocalSystemProxyBypassEntry(String entry) {
  final normalized = entry.trim().toLowerCase();
  return kLocalSystemProxyBypass.any((local) => local.toLowerCase() == normalized);
}

/// The user's own entries: whatever is in [raw] that the app does not own.
List<String> userSystemProxyBypassEntries(String? raw) =>
    parseSystemProxyOverride(raw).where((entry) => !isLocalSystemProxyBypassEntry(entry)).toList(growable: false);

/// Builds the value to write: the local entries followed by the user's.
///
/// Duplicates are dropped, local entries are matched case insensitively.
List<String> composeSystemProxyOverride(Iterable<String> userEntries) {
  final seen = <String>{};
  final result = <String>[];
  for (final entry in [...kLocalSystemProxyBypass, ...userEntries]) {
    final trimmed = entry.trim();
    if (trimmed.isEmpty) continue;
    if (seen.add(trimmed.toLowerCase())) result.add(trimmed);
  }
  return result;
}

/// The value written to the registry, i.e. [composeSystemProxyOverride] joined
/// with the separator Windows expects.
String systemProxyOverrideValue(Iterable<String> userEntries) => composeSystemProxyOverride(userEntries).join(';');

/// Parses the text the user typed into entries.
///
/// The list is edited as one semicolon separated string, which is how Windows
/// itself stores it. Both the half-width `;` and the full-width `；` are
/// accepted, because a Chinese keyboard produces the latter very easily and
/// rejecting it would look like the app lost the input.
List<String> parseUserEntryText(String? raw) {
  if (raw == null) return const [];
  final seen = <String>{};
  final result = <String>[];
  for (final part in raw.split(RegExp('[;；]'))) {
    final entry = part.trim();
    if (entry.isEmpty) continue;
    if (entry.contains(RegExp(r'\s'))) continue;
    if (seen.add(entry.toLowerCase())) result.add(entry);
  }
  return result;
}

/// The text to show in the editor for [entries].
String formatUserEntryText(Iterable<String> entries) => entries.join('; ');
