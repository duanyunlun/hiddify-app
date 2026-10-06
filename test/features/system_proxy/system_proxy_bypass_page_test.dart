@TestOn('windows')
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/system_proxy/data/system_proxy_override_store.dart';
import 'package:hiddify/features/system_proxy/notifier/system_proxy_bypass_notifier.dart';
import 'package:hiddify/features/system_proxy/overview/system_proxy_bypass_page.dart';
import 'package:hiddify/gen/translations.g.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win32_registry/win32_registry.dart';

/// The page writes to the registry, so the tests point it at a scratch key and
/// remove it afterwards. Nothing here may touch the machine's real proxy
/// settings.
const _scratchKeyPath = r'Software\hiddify-fork-tests\bypass-page';
const _scratchParentPath = r'Software\hiddify-fork-tests';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void deleteScratchKey() {
    for (final path in [_scratchKeyPath, _scratchParentPath]) {
      try {
        Registry.currentUser.deleteKey(path, recursive: true);
      } catch (_) {
        // Nothing to remove.
      }
    }
  }

  setUp(deleteScratchKey);
  tearDown(deleteScratchKey);

  Future<void> pumpPage(WidgetTester tester, {List<String> stored = const []}) async {
    SharedPreferences.setMockInitialValues({
      'system-proxy-bypass': jsonEncode(stored),
      'system-proxy-bypass-adopted': true,
    });
    final preferences = await SharedPreferences.getInstance();
    final translations = await AppLocale.en.build();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationsProvider.overrideWith((ref) => translations),
          sharedPreferencesProvider.overrideWith((ref) => preferences),
          systemProxyOverrideStoreProvider.overrideWithValue(
            SystemProxyOverrideStore(keyPath: _scratchKeyPath),
          ),
        ],
        child: const MaterialApp(home: SystemProxyBypassPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows one text field, pre-filled with the current entries', (tester) async {
    await pumpPage(tester, stored: ['*.a.com', '10.0.0.0/8']);

    expect(find.text('System proxy bypass'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('*.a.com; 10.0.0.0/8'), findsOneWidget);
  });

  testWidgets('typing saves once the typing pauses, and keeps the local entries', (tester) async {
    await pumpPage(tester);

    await tester.enterText(find.byType(TextField), '*.example.com; 10.0.0.0/8');
    // The startup write already put the local entries in place, so the check is
    // that the typed entries are not written yet while typing is still going on.
    await tester.pump(const Duration(milliseconds: 200));
    final beforePause = SystemProxyOverrideStore(keyPath: _scratchKeyPath).read();
    expect(beforePause, isNot(contains('*.example.com')));

    await tester.pump(const Duration(milliseconds: 700));
    final written = SystemProxyOverrideStore(keyPath: _scratchKeyPath).read();
    expect(written, isNotNull);
    expect(written, contains('*.example.com'));
    expect(written, contains('10.0.0.0/8'));
    // The loopback and private ranges survive whatever the user types.
    expect(written, contains('localhost'));
    expect(written, contains('<local>'));
  });

  testWidgets('the full width semicolon is accepted', (tester) async {
    await pumpPage(tester);

    await tester.enterText(find.byType(TextField), '*.a.com；*.b.com');
    await tester.pump(const Duration(milliseconds: 700));

    final written = SystemProxyOverrideStore(keyPath: _scratchKeyPath).read()!;
    expect(written, contains('*.a.com'));
    expect(written, contains('*.b.com'));
  });

  testWidgets('clearing leaves only the local entries', (tester) async {
    await pumpPage(tester, stored: ['*.a.com']);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    final written = SystemProxyOverrideStore(keyPath: _scratchKeyPath).read()!;
    expect(written, isNot(contains('*.a.com')));
    expect(written, contains('localhost'));
  });
}
