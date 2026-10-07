@TestOn('windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/system_proxy/data/windows_proxy_override_store.dart';
import 'package:win32_registry/win32_registry.dart';

/// Exercises the real registry, but against a scratch key rather than the live
/// internet settings, so running the tests cannot change how this machine
/// reaches the network.
const _scratchKeyPath = r'Software\hiddify-fork-tests\system-proxy-bypass';
const _scratchParentPath = r'Software\hiddify-fork-tests';

void main() {
  final store = WindowsProxyOverrideStore(keyPath: _scratchKeyPath);

  void deleteScratchKey() {
    try {
      Registry.currentUser.deleteKey(_scratchKeyPath, recursive: true);
    } catch (_) {
      // Nothing to remove.
    }
    // createKey creates the parents, so remove them as well and leave no trace
    // of the test run in the user's registry.
    try {
      Registry.currentUser.deleteKey(_scratchParentPath, recursive: true);
    } catch (_) {
      // Nothing to remove.
    }
  }

  setUp(deleteScratchKey);

  tearDown(deleteScratchKey);

  test('is supported on windows', () {
    expect(store.isSupported, isTrue);
  });

  test('reads back what it wrote', () async {
    expect(await store.write(['*.example.com']), isTrue);
    final written = await store.read();
    expect(written, isNotNull);
    expect(written, endsWith(';*.example.com'));
    expect(written, contains('localhost'));
  });

  test('replaces a value left behind by another tool', () async {
    // Simulate another program having written its own list.
    final key = Registry.currentUser.createKey(_scratchKeyPath);
    key.createValue(const RegistryValue.string('ProxyOverride', 'localhost;*.steampowered.com;openrouter.ai'));
    key.close();

    // What the app adopts, then what it writes back once the user clears it.
    expect(await store.currentUserEntries(), ['*.steampowered.com', 'openrouter.ai']);
    expect(await store.write(const []), isTrue);

    final written = (await store.read())!;
    expect(written, isNot(contains('steampowered')));
    expect(written, isNot(contains('openrouter')));
    expect(written, contains('localhost'));
    expect(await store.currentUserEntries(), isEmpty);
  });

  test('write survives a value that was never set', () async {
    expect(await store.read(), isNull);
    expect(await store.write(['10.0.0.0/8']), isTrue);
    expect(await store.currentUserEntries(), ['10.0.0.0/8']);
  });

  test('is a no-op off windows', () async {
    // Guarded rather than asserted as false: this file only runs on windows, so
    // the branch documents the intended behaviour on the other platforms.
    if (!Platform.isWindows) {
      expect(await store.write(['*.example.com']), isFalse);
      expect(await store.read(), isNull);
    }
  });
}
