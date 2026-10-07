import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/services/lan_cast/settings.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/theme_utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// A settings sheet within the existing playback page, using receiver values.
void showLanCastSettings(
  BuildContext context,
  PlPlayerController player, {
  String? group,
  String? settingKey,
}) {
  PageUtils.showVideoBottomSheet(
    context,
    maxWidth: 512,
    child: Theme(
      data: player.darkVideoPage ? ThemeUtils.darkTheme : Theme.of(context),
      child: LanCastSettingsSheet(
        player: player,
        group: group,
        settingKey: settingKey,
      ),
    ),
  );
}

class LanCastSettingsSheet extends StatefulWidget {
  const LanCastSettingsSheet({
    super.key,
    required this.player,
    this.group,
    this.settingKey,
    this.embedded = false,
  });
  final PlPlayerController player;
  final String? group, settingKey;
  final bool embedded;
  @override
  State<LanCastSettingsSheet> createState() => _LanCastSettingsSheetState();
}

class _LanCastSettingsSheetState extends State<LanCastSettingsSheet> {
  late final mediaKey = widget.player.castMediaKey;

  @override
  Widget build(BuildContext context) => Obx(() {
    final player = widget.player;
    final connected =
        player.castDevice.value.isNotEmpty && player.castMediaKey == mediaKey;
    final settings = player.castSettings.values
        .where(
          (e) =>
              (widget.group == null || e.group == widget.group) &&
              (widget.settingKey == null || e.key == widget.settingKey),
        )
        .toList();
    final isRoot = widget.group == null && widget.settingKey == null;
    final shown = isRoot
        ? settings.where((e) => e.group == '播放设置').toList()
        : settings;
    final groups = isRoot
        ? settings.map((e) => e.group).where((e) => e != '播放设置').toSet()
        : <String>{};
    return Material(
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      clipBehavior: Clip.hardEdge,
      child: ListView(
        shrinkWrap: widget.embedded,
        physics: widget.embedded ? const NeverScrollableScrollPhysics() : null,
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.group ??
                (settings.length == 1 ? settings.first.label : '播放设置'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            connected ? player.castDevice.value : '投屏已结束或视频已切换',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (connected && settings.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('接收端暂不支持此设置，请更新接收端后重试'),
            ),
          if (connected)
            for (final setting in shown)
              _SettingTile(
                key: ValueKey(setting.key),
                setting: setting,
                onChanged: (value) => player.setCastSetting(
                  setting.key,
                  value,
                  mediaKey: mediaKey,
                ),
              ),
          if (connected)
            for (final group in groups)
              ListTile(
                title: Text(group),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showLanCastSettings(context, player, group: group),
              ),
        ],
      ),
    );
  });
}

class _SettingTile extends StatefulWidget {
  const _SettingTile({
    super.key,
    required this.setting,
    required this.onChanged,
  });
  final LanCastSetting setting;
  final Future<void> Function(Object) onChanged;
  @override
  State<_SettingTile> createState() => _SettingTileState();
}

class _SettingTileState extends State<_SettingTile> {
  double? _dragValue;
  bool _busy = false;

  Future<void> _change(Object value) async {
    setState(() => _busy = true);
    try {
      await widget.onChanged(value);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _dragValue = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final setting = widget.setting;
    if (setting.readOnly) {
      return ListTile(
        title: Text(setting.label),
        subtitle: Text('${setting.value}'),
      );
    }
    if (setting.key == 'reload') {
      return ListTile(
        title: Text(setting.label),
        leading: const Icon(Icons.refresh),
        onTap: _busy ? null : () => _change(true),
      );
    }
    if (setting.options.isNotEmpty) {
      return ListTile(
        title: Text(setting.label),
        subtitle: Text(setting.options[setting.value] ?? '未选择'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _busy
            ? null
            : () async {
                final value = await showDialog<String>(
                  context: context,
                  builder: (context) => SimpleDialog(
                    title: Text(setting.label),
                    children: [
                      for (final item in setting.options.entries)
                        SimpleDialogOption(
                          onPressed: () => Navigator.pop(context, item.key),
                          child: Row(
                            children: [
                              Expanded(child: Text(item.value)),
                              if (item.key == setting.value)
                                const Icon(Icons.check, size: 20),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
                if (value != null && mounted) await _change(value);
              },
      );
    }
    if (setting.value is bool) {
      return SwitchListTile(
        title: Text(setting.label),
        value: setting.value as bool,
        onChanged: _busy ? null : _change,
      );
    }
    final value = (_dragValue ?? (setting.value as num).toDouble()).clamp(
      setting.min!,
      setting.max!,
    );
    final label = value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${setting.label}  $label'),
          Slider(
            value: value,
            min: setting.min!,
            max: setting.max!,
            divisions: setting.divisions,
            label: label,
            onChanged: _busy ? null : (v) => setState(() => _dragValue = v),
            onChangeEnd: (v) => _change(setting.value is int ? v.round() : v),
          ),
        ],
      ),
    );
  }
}

/// Used by the original bottom controls so receiver-only choices remain usable.
class LanCastSettingButton extends StatelessWidget {
  const LanCastSettingButton({
    super.key,
    required this.player,
    required this.settingKey,
    required this.label,
    this.icon,
  });
  final PlPlayerController player;
  final String settingKey, label;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Obx(() {
    final setting = player.castSettings[settingKey];
    return TextButton(
      onPressed: () =>
          showLanCastSettings(context, player, settingKey: settingKey),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(30, 30),
      ),
      child: icon != null
          ? Icon(icon, size: 20)
          : Text(
              setting?.options[setting.value] ?? label,
              style: const TextStyle(fontSize: 13),
            ),
    );
  });
}
