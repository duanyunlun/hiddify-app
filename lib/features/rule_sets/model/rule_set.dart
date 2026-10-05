/// Models for the custom rule set feature.
///
/// These are plain classes with hand written JSON (de)serialization on purpose:
/// the repository has a history of `build_runner` deadlocks, and a plain class
/// keeps this feature independent of code generation.
library;

/// A rule set the user has added to the active configuration.
///
/// The wire shape is what the core expects under the top level `rule-set` key:
///
/// ```json
/// {"tag": "my-cn", "type": "remote", "format": "binary",
///  "url": "https://…/cn.srs", "update_interval": "120h"}
/// ```
class RuleSetEntry {
  const RuleSetEntry({
    required this.tag,
    required this.url,
    this.type = RuleSetType.remote,
    this.format = RuleSetFormat.binary,
    this.updateInterval = defaultUpdateInterval,
    this.enabled = true,
    this.localPath,
  });

  /// Identifier referenced by routing rules.
  final String tag;

  /// Download URL. Empty for local rule sets.
  final String url;

  final RuleSetType type;
  final RuleSetFormat format;

  /// Go duration string (for example `120h`) or a bare number of seconds.
  final String updateInterval;

  /// Disabled entries stay in the list but are not sent to the core.
  final bool enabled;

  /// Path for [RuleSetType.local].
  final String? localPath;

  static const defaultUpdateInterval = '120h';

  RuleSetEntry copyWith({
    String? tag,
    String? url,
    RuleSetType? type,
    RuleSetFormat? format,
    String? updateInterval,
    bool? enabled,
    String? localPath,
  }) => RuleSetEntry(
    tag: tag ?? this.tag,
    url: url ?? this.url,
    type: type ?? this.type,
    format: format ?? this.format,
    updateInterval: updateInterval ?? this.updateInterval,
    enabled: enabled ?? this.enabled,
    localPath: localPath ?? this.localPath,
  );

  Map<String, dynamic> toJson() => {
    'tag': tag,
    if (url.isNotEmpty) 'url': url,
    'type': type.key,
    'format': format.key,
    if (updateInterval.isNotEmpty) 'update_interval': updateInterval,
    if (localPath != null && localPath!.isNotEmpty) 'path': localPath,
  };

  /// Converts to the shape expected by the core (`rule-set` entries). Disabled
  /// entries are filtered out by the caller.
  Map<String, dynamic> toCoreJson() => {
    'tag': tag,
    'type': type.key,
    'format': format.key,
    if (url.isNotEmpty) 'url': url,
    if (localPath != null && localPath!.isNotEmpty) 'path': localPath,
    if (updateInterval.isNotEmpty) 'update_interval': updateInterval,
    'download_detour': 'select',
  };

  static RuleSetEntry fromJson(Map<String, dynamic> json) => RuleSetEntry(
    tag: (json['tag'] as String?) ?? '',
    url: (json['url'] as String?) ?? '',
    type: RuleSetType.fromKey(json['type'] as String?),
    format: RuleSetFormat.fromKey(json['format'] as String?),
    updateInterval: (json['update_interval'] as String?) ?? defaultUpdateInterval,
    enabled: (json['enabled'] as bool?) ?? true,
    localPath: json['path'] as String?,
  );  @override
  bool operator ==(Object other) =>
      other is RuleSetEntry &&
      other.tag == tag &&
      other.url == url &&
      other.type == type &&
      other.format == format &&
      other.updateInterval == updateInterval &&
      other.enabled == enabled &&
      other.localPath == localPath;

  @override
  int get hashCode => Object.hash(tag, url, type, format, updateInterval, enabled, localPath);

  @override
  String toString() => 'RuleSetEntry($tag, ${type.key}, $url)';
}

enum RuleSetType {
  remote('remote'),
  local('local');

  const RuleSetType(this.key);

  final String key;

  static RuleSetType fromKey(String? value) =>
      RuleSetType.values.firstWhere((e) => e.key == value, orElse: () => RuleSetType.remote);
}

enum RuleSetFormat {
  binary('binary'),
  source('source');

  const RuleSetFormat(this.key);

  final String key;

  static RuleSetFormat fromKey(String? value) =>
      RuleSetFormat.values.firstWhere((e) => e.key == value, orElse: () => RuleSetFormat.binary);
}

/// One entry of a rule set catalog (a "store" of ready to use rule sets).
class RuleSetCatalogEntry {
  const RuleSetCatalogEntry({
    required this.name,
    required this.type,
    this.description = '',
    this.count = 0,
  });

  /// File name inside the catalog source, for example `cn` or `geolocation-!cn`.
  final String name;

  /// Which source directory the entry lives in (`geosite` or `geoip`).
  final String type;

  final String description;

  /// Number of rules, when the catalog reports it.
  final int count;

  /// Tag used when the entry is added to the configuration.
  String get tag => '$type-$name';

  static RuleSetCatalogEntry? fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String?;
    final type = json['type'] as String?;
    if (name == null || name.isEmpty || type == null || type.isEmpty) return null;
    return RuleSetCatalogEntry(
      name: name,
      type: type,
      description: (json['description'] as String?) ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  String toString() => 'RuleSetCatalogEntry($type/$name, $count)';
}

/// The catalog itself, compatible with the `Ruleset-Hub` `sing-full.json`
/// format:
///
/// ```json
/// {"geosite": "https://…/geo/geosite/", "geoip": "https://…/geo/geoip/",
///  "list": [{"name": "cn", "type": "geosite", "count": 111224}]}
/// ```
///
/// The base URLs are kept in the payload rather than hardcoded so that the
/// catalog can point at any mirror.
class RuleSetCatalog {
  const RuleSetCatalog({required this.baseUrls, required this.entries});

  final Map<String, String> baseUrls;
  final List<RuleSetCatalogEntry> entries;

  /// Builds the download URL for an entry.
  String? urlFor(RuleSetCatalogEntry entry) {
    final base = baseUrls[entry.type];
    if (base == null || base.isEmpty) return null;
    final normalized = base.endsWith('/') ? base : '$base/';
    return '$normalized${entry.name}.srs';
  }

  static RuleSetCatalog fromJson(Map<String, dynamic> json) {
    final baseUrls = <String, String>{};
    for (final key in const ['geosite', 'geoip']) {
      final value = json[key];
      if (value is String && value.isNotEmpty) baseUrls[key] = value;
    }
    final rawList = json['list'];
    final entries = <RuleSetCatalogEntry>[];
    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map<String, dynamic>) {
          final entry = RuleSetCatalogEntry.fromJson(item);
          if (entry != null) entries.add(entry);
        }
      }
    }
    return RuleSetCatalog(baseUrls: baseUrls, entries: entries);
  }
}
