import 'package:PiliPlus/services/lan_cast/protocol.dart';

/// Only settings advertised by the current receiving page can be changed.
/// Values are scalars, never arbitrary player properties, URLs or file paths.
class LanCastSetting {
  const LanCastSetting({
    required this.key,
    required this.label,
    required this.group,
    required this.value,
    this.min,
    this.max,
    this.divisions,
    this.options = const {},
    this.readOnly = false,
  });

  final String key, label, group;
  final Object value;
  final double? min, max;
  final int? divisions;
  final Map<String, String> options;
  final bool readOnly;

  Object validate(Object? next) {
    if (readOnly) throw const LanCastException('此项为播放信息，无法修改');
    if (options.isNotEmpty) {
      if (next is String && options.containsKey(next)) return next;
    } else if (value is bool) {
      if (next is bool) return next;
    } else if (min != null && max != null) {
      final number = lanCastNumber(next, min!, max!);
      if (value is! int || number == number.roundToDouble()) {
        return value is int ? number.toInt() : number;
      }
    }
    throw const LanCastException('设置值无效或接收端不支持此选项');
  }

  factory LanCastSetting.fromJson(Map<String, dynamic> json) => LanCastSetting(
    key: lanCastText(json['key'], maxLength: 80),
    label: lanCastText(json['label']),
    group: lanCastText(json['group'], maxLength: 40),
    value: json['value'] as Object,
    min: (json['min'] as num?)?.toDouble(),
    max: (json['max'] as num?)?.toDouble(),
    divisions: json['divisions'] as int?,
    options: (json['options'] as Map?)?.cast<String, String>() ?? const {},
    readOnly: json['readOnly'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label,
    'group': group,
    'value': value,
    if (min != null) 'min': min,
    if (max != null) 'max': max,
    if (divisions != null) 'divisions': divisions,
    if (options.isNotEmpty) 'options': options,
    if (readOnly) 'readOnly': true,
  };
}

abstract interface class LanCastSettingsPlayback {
  Future<void> setSetting(String key, Object value);
}
