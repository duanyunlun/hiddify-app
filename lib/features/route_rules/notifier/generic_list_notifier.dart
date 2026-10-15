import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/route_rules/notifier/rule_notifier.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'generic_list_notifier.g.dart';

@riverpod
class GenericListNotifier extends _$GenericListNotifier {
  late int? _ruleListOrder;
  late RuleEnum _ruleEnum;

  @override
  List<dynamic> build(int? ruleListOrder, RuleEnum ruleEnum) {
    _ruleListOrder = ruleListOrder;
    _ruleEnum = ruleEnum;
    final value = ref.read(ruleNotifierProvider(ruleListOrder)).writeToJsonMap()['${ruleEnum.getIndex()}'];
    if (value is List) return value;
    return [];
  }

  void add(dynamic value) {
    final normalized = _normalize(value);
    if (!_isValid(normalized)) return;
    state = [...state, normalized];
    _save();
  }

  void update(int index, dynamic value) {
    final normalized = _normalize(value);
    if (!_isValid(normalized)) return;
    state = List.from(state)..[index] = normalized;
    _save();
  }

  /// Accepts the spellings users actually type and stores the form sing-box
  /// matches against. A domain suffix is matched as a suffix, so `*.example.com`
  /// (which sing-box would never match literally) is stored as `.example.com`.
  dynamic _normalize(dynamic value) {
    if (_ruleEnum == RuleEnum.domainSuffix && value is String && value.startsWith('*.')) {
      return value.substring(1);
    }
    return value;
  }

  void remove(int index) {
    state = List.from(state)..removeAt(index);
    _save();
  }

  void reset() {
    state = [];
    _save();
  }

  void _save() => ref.read(ruleNotifierProvider(_ruleListOrder).notifier).update<List<dynamic>>(_ruleEnum, state);

  bool _isValid(dynamic value) {
    if (value == null) return false;
    if (state.contains(value)) {
      ref.read(inAppNotificationControllerProvider).showErrorToast('Value is exist');
      return false;
    }
    return true;
  }
}
