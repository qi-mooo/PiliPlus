import 'package:PiliPlus/services/lan_cast/protocol.dart';
import 'package:hive_ce/hive.dart';

/// Separate from exported settings: device identity and trust stay on this device.
class LanCastStore {
  LanCastStore(this.data, this.write);
  final Map<String, dynamic> data;
  final Future<void> Function(Map<String, dynamic>) write;
  static late LanCastStore instance;

  static Future<void> initialize() async {
    final box = await Hive.openBox('lanCastTrust');
    instance = LanCastStore(
      Map<String, dynamic>.from(
        box.get('state', defaultValue: <String, dynamic>{}) as Map,
      ),
      (data) => box.put('state', data),
    );
    await instance.initializeIdentity();
  }

  Future<void> initializeIdentity() async {
    data.putIfAbsent('id', () => lanCastSecret(12));
    await save();
  }

  String get id => data['id'] as String;
  bool get enabled => data['enabled'] == true;
  Map<String, Map<String, dynamic>> entries(String key) => {
    for (final entry in (data[key] as Map? ?? {}).entries)
      entry.key as String: Map<String, dynamic>.from(entry.value as Map),
  };
  Map<String, Map<String, dynamic>> get peers => entries('peers');
  Map<String, Map<String, dynamic>> get targets => entries('targets');
  Future<void> save() => write(Map<String, dynamic>.from(data));
  Future<void> put(String group, String id, Map<String, dynamic> value) async {
    data[group] = entries(group)..[id] = value;
    await save();
  }

  Future<void> remove(String group, String id) async {
    data[group] = entries(group)..remove(id);
    await save();
  }
}
