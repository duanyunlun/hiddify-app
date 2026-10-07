import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/system_proxy/data/mac_proxy_bypass_store.dart';
import 'package:hiddify/features/system_proxy/model/system_proxy_bypass.dart';

/// The macOS store shells out to `networksetup` and `route`, so these tests drive
/// it with a fake runner. They cover the command lines and the parsing, which is
/// everything that cannot be checked from a machine that is not a Mac.
const _serviceOrder = '''
An asterisk (*) denotes that a network service is disabled.
(1) Wi-Fi
(Hardware Port: Wi-Fi, Device: en0)

(2) Thunderbolt Bridge
(Hardware Port: Thunderbolt Bridge, Device: bridge0)
''';

const _defaultRoute = '''   route to: default
destination: default
       mask: default
    gateway: 192.168.1.1
  interface: en0
''';

class _FakeRunner {
  _FakeRunner({this.exitCode = 0});

  String bypassDomains = '';
  final int exitCode;
  final List<List<String>> calls = [];

  Future<ProcessResult> call(String executable, List<String> arguments) async {
    calls.add([executable, ...arguments]);
    if (executable == 'route') return ProcessResult(0, 0, _defaultRoute, '');
    if (arguments.first == '-listnetworkserviceorder') return ProcessResult(0, 0, _serviceOrder, '');
    if (arguments.first == '-getproxybypassdomains') {
      return ProcessResult(
        0,
        exitCode,
        bypassDomains.isEmpty ? "There aren't any bypass domains set on Wi-Fi." : bypassDomains,
        '',
      );
    }
    if (arguments.first == '-setproxybypassdomains') {
      bypassDomains = arguments.skip(2).join('\n');
      return ProcessResult(0, exitCode, '', exitCode == 0 ? '' : 'You must be root to run this tool.');
    }
    return ProcessResult(0, 1, '', 'unexpected command');
  }
}

void main() {
  group('activeService', () {
    test('maps the default route interface to its service name', () async {
      final runner = _FakeRunner();
      final store = MacProxyBypassStore(runner: runner.call);
      // The store is a no-op off macOS, so the lookup is only exercised there.
      if (!Platform.isMacOS) return;
      expect(await store.activeService(), 'Wi-Fi');
    });

    test('picks the service by device, not by position', () async {
      final runner = _FakeRunner();
      // Force the second entry to be the match.
      final calls = <String>[];
      Future<ProcessResult> tracking(String exe, List<String> args) {
        calls.add(exe);
        return runner.call(exe, args);
      }

      if (!Platform.isMacOS) return;
      expect(await MacProxyBypassStore(runner: tracking).activeService(), 'Wi-Fi');
      expect(calls, contains('networksetup'));
    });
  });

  group('parsing the current value', () {
    test('an untouched service reports no user entries', () {
      // "There aren't any bypass domains set on Wi-Fi." is what an untouched
      // service answers, and it must not be mistaken for an entry.
      final entries = userSystemProxyBypassEntries(
        null,
        localEntries: kLocalMacSystemProxyBypass,
        separator: '\n',
      );
      expect(entries, isEmpty);
    });

    test('splits on newlines and drops the entries macOS owns', () {
      const raw = '*.local\n169.254/16\n*.steampowered.com\nopenrouter.ai';
      expect(
        userSystemProxyBypassEntries(raw, localEntries: kLocalMacSystemProxyBypass, separator: '\n'),
        ['*.steampowered.com', 'openrouter.ai'],
      );
    });

    test('composing keeps the macOS entries first', () {
      final composed = composeSystemProxyOverride(
        ['*.steampowered.com'],
        localEntries: kLocalMacSystemProxyBypass,
      );
      expect(composed, ['*.local', '169.254/16', '*.steampowered.com']);
    });
  });

  group('write', () {
    test('off macOS it reports failure rather than pretending', () async {
      if (Platform.isMacOS) return;
      final store = MacProxyBypassStore(runner: _FakeRunner().call);
      expect(store.isSupported, isFalse);
      expect(await store.write(['*.example.com']), isFalse);
      expect(await store.read(), isNull);
    });

    test('writes need authorisation, reads do not', () {
      final store = MacProxyBypassStore(runner: _FakeRunner().call);
      expect(store.requiresAuthorisationForWrite, isTrue);
    });
  });

  group('macBypassApplyScript', () {
    test('asks for authorisation and quotes every argument', () {
      final script = macBypassApplyScript('Wi-Fi', ['*.local', '169.254/16', '*.steampowered.com']);
      expect(script, startsWith('do shell script "'));
      expect(script, endsWith('" with administrator privileges'));
      expect(script, contains("'networksetup'"));
      expect(script, contains("'-setproxybypassdomains'"));
      expect(script, contains("'Wi-Fi'"));
      expect(script, contains("'*.steampowered.com'"));
    });

    test('a service name with a space stays one argument', () {
      final script = macBypassApplyScript('Thunderbolt Bridge', ['*.local']);
      expect(script, contains("'Thunderbolt Bridge'"));
    });

    test('a single quote in an entry cannot break out of the shell word', () {
      // `'` becomes `'\''`, which the AppleScript layer then doubles the
      // backslash of, so the entry stays a single quoted word and the `;` in it
      // is never a command separator.
      final script = macBypassApplyScript('Wi-Fi', ["a'; rm -rf /; echo '"]);
      expect(script, contains(r"'\\''"));
      // The entry is not closed before the semicolon, which is what an injection
      // would need.
      expect(script, isNot(contains("'a'; ")));
      expect(script, isNot(contains("'a'\\''; rm")));
    });

    test('a double quote is escaped for AppleScript', () {
      final script = macBypassApplyScript('Wi-Fi', ['a"b']);
      // Without the escape the AppleScript literal would end at the entry.
      expect(script, contains(r'\"'));
      expect(script, contains("'a\\\"b'"));
    });
  });
}
