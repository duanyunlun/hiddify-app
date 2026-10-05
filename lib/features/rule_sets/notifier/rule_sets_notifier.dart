import 'dart:convert';

import 'package:hiddify/core/http_client/http_client_provider.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/rule_sets/model/rule_set.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Default catalog. The format is the one `GUI-for-Cores/Ruleset-Hub` publishes
/// (`{geosite, geoip, list[]}`) and the address is user configurable, so this
/// repository is a convenience default rather than a hard dependency.
const kDefaultRuleSetCatalogUrl =
    'https://github.com/GUI-for-Cores/Ruleset-Hub/releases/download/latest/sing-full.json';

const _kRuleSetsKey = 'custom-rule-sets';
const _kCatalogUrlKey = 'rule-set-catalog-url';

/// State of the rule set feature: the rule sets that are part of the active
/// configuration plus the (remote) list of rule sets available to add.
class RuleSetsState {
  const RuleSetsState({
    this.ruleSets = const [],
    this.catalog = const RuleSetCatalog(baseUrls: {}, entries: []),
    this.catalogUrl = kDefaultRuleSetCatalogUrl,
    this.isLoadingCatalog = false,
    this.catalogError,
  });

  final List<RuleSetEntry> ruleSets;
  final RuleSetCatalog catalog;
  final String catalogUrl;
  final bool isLoadingCatalog;
  final String? catalogError;

  /// The rule sets that should be sent to the core.
  List<RuleSetEntry> get enabledRuleSets => ruleSets.where((e) => e.enabled).toList(growable: false);

  bool containsTag(String tag) => ruleSets.any((e) => e.tag == tag);

  RuleSetsState copyWith({
    List<RuleSetEntry>? ruleSets,
    RuleSetCatalog? catalog,
    String? catalogUrl,
    bool? isLoadingCatalog,
    String? catalogError,
    bool clearError = false,
  }) => RuleSetsState(
    ruleSets: ruleSets ?? this.ruleSets,
    catalog: catalog ?? this.catalog,
    catalogUrl: catalogUrl ?? this.catalogUrl,
    isLoadingCatalog: isLoadingCatalog ?? this.isLoadingCatalog,
    catalogError: clearError ? null : (catalogError ?? this.catalogError),
  );
}

/// A plain [StateNotifier] instead of a generated provider, so that this feature
/// does not depend on `build_runner`.
class RuleSetsNotifier extends StateNotifier<RuleSetsState> {
  RuleSetsNotifier(this._ref) : super(const RuleSetsState()) {
    _restore();
  }

  final Ref _ref;

  PreferencesEntry<String?, String?> get _store => PreferencesEntry<String?, String?>(
    preferences: _ref.read(sharedPreferencesProvider).requireValue,
    key: _kRuleSetsKey,
    defaultValue: null,
  );

  PreferencesEntry<String?, String?> get _catalogUrlStore => PreferencesEntry<String?, String?>(
    preferences: _ref.read(sharedPreferencesProvider).requireValue,
    key: _kCatalogUrlKey,
    defaultValue: null,
  );

  void _restore() {
    final rawCatalogUrl = _catalogUrlStore.read();
    final raw = _store.read();
    final restored = <RuleSetEntry>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              final entry = RuleSetEntry.fromJson(item);
              if (entry.tag.isNotEmpty) restored.add(entry);
            }
          }
        }
      } catch (_) {
        // A corrupt value must not break startup; fall back to an empty list.
      }
    }
    state = state.copyWith(
      ruleSets: restored,
      catalogUrl: (rawCatalogUrl == null || rawCatalogUrl.isEmpty) ? kDefaultRuleSetCatalogUrl : rawCatalogUrl,
    );
  }

  void _persist() {
    final payload = jsonEncode(state.ruleSets.map((e) => {...e.toJson(), 'enabled': e.enabled}).toList());
    _store.write(payload);
  }

  /// Adds a rule set. Returns false when the tag is already taken.
  bool add(RuleSetEntry entry) {
    if (entry.tag.isEmpty || state.containsTag(entry.tag)) return false;
    state = state.copyWith(ruleSets: [...state.ruleSets, entry]);
    _persist();
    return true;
  }

  void remove(String tag) {
    state = state.copyWith(ruleSets: state.ruleSets.where((e) => e.tag != tag).toList(growable: false));
    _persist();
  }

  void setEnabled(String tag, bool enabled) {
    state = state.copyWith(
      ruleSets: state.ruleSets.map((e) => e.tag == tag ? e.copyWith(enabled: enabled) : e).toList(growable: false),
    );
    _persist();
  }

  void replace(RuleSetEntry entry) {
    state = state.copyWith(
      ruleSets: state.ruleSets.map((e) => e.tag == entry.tag ? entry : e).toList(growable: false),
    );
    _persist();
  }

  void clear() {
    state = state.copyWith(ruleSets: const []);
    _persist();
  }

  Future<void> setCatalogUrl(String url) async {
    final trimmed = url.trim();
    await _catalogUrlStore.write(trimmed.isEmpty ? kDefaultRuleSetCatalogUrl : trimmed);
    state = state.copyWith(catalogUrl: trimmed.isEmpty ? kDefaultRuleSetCatalogUrl : trimmed, clearError: true);
  }

  /// Downloads and parses the catalog.
  Future<void> loadCatalog() async {
    if (state.isLoadingCatalog) return;
    state = state.copyWith(isLoadingCatalog: true, clearError: true);
    try {
      // Reuse the shared client so the download honours the proxy/direct
      // fallback and the retry policy used everywhere else in the app.
      final client = _ref.read(httpClientProvider);
      final response = await client.get<String>(state.catalogUrl);
      final body = response.data;
      if (body == null || body.isEmpty) {
        state = state.copyWith(isLoadingCatalog: false, catalogError: 'empty response');
        return;
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        state = state.copyWith(isLoadingCatalog: false, catalogError: 'unexpected catalog format');
        return;
      }
      state = state.copyWith(
        catalog: RuleSetCatalog.fromJson(decoded),
        isLoadingCatalog: false,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(isLoadingCatalog: false, catalogError: e.toString());
    }
  }

  /// Adds a catalog entry, resolving its download URL from the catalog itself.
  bool addFromCatalog(RuleSetCatalogEntry entry) {    final url = state.catalog.urlFor(entry);
    if (url == null) return false;
    return add(RuleSetEntry(tag: entry.tag, url: url));
  }
}

final ruleSetsProvider = StateNotifierProvider<RuleSetsNotifier, RuleSetsState>(
  (ref) => RuleSetsNotifier(ref),
);
