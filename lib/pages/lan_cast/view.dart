import 'package:PiliPlus/pages/lan_cast/receiver.dart';
import 'package:PiliPlus/pages/dlna/view.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:PiliPlus/services/lan_cast/client.dart';
import 'package:PiliPlus/services/lan_cast/discovery.dart';
import 'package:PiliPlus/services/lan_cast/permission.dart';
import 'package:PiliPlus/services/lan_cast/protocol.dart';
import 'package:PiliPlus/services/lan_cast/session.dart';
import 'package:PiliPlus/services/lan_cast/store.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:material_ui/material_ui.dart';

class LanCastPage extends StatefulWidget {
  const LanCastPage({super.key, this.player, this.dlnaUrl});
  final PlPlayerController? player;
  final Future<String> Function()? dlnaUrl;
  @override
  State<LanCastPage> createState() => _LanCastPageState();
}

class _LanCastPageState extends State<LanCastPage> {
  final _discovery = LanCastDiscovery();
  final _session = LanCastSession.instance;
  final _store = LanCastStore.instance;
  String? _error;
  bool _connecting = false;
  bool _dlnaConnecting = false;

  @override
  void initState() {
    super.initState();
    if (widget.player != null) _discovery.start();
  }

  @override
  void dispose() {
    _discovery.dispose();
    super.dispose();
  }

  Future<String?> _input({
    required String title,
    required String label,
    bool code = false,
  }) {
    var input = '';
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          autofocus: true,
          maxLength: code ? 6 : 80,
          keyboardType: code ? TextInputType.number : TextInputType.url,
          inputFormatters: code
              ? [FilteringTextInputFormatter.digitsOnly]
              : null,
          decoration: InputDecoration(labelText: label),
          onChanged: (value) => input = value,
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, input.trim()),
            child: const Text('连接'),
          ),
        ],
      ),
    );
  }

  Future<void> _manual() async {
    final address = await _input(title: '手动连接', label: '接收端 IP 地址和端口');
    if (address == null || !mounted) return;
    LanCastClient? client;
    try {
      await ensureLanCastPermission();
      client = LanCastClient(lanCastAddress(address));
      setState(() => _connecting = true);
      final device = await client.info();
      if (mounted) await _connect(device);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      client?.close();
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _connect(LanCastDevice device) async {
    final player = widget.player;
    if (player == null) return;
    if (player.videoPlayerController == null ||
        player.dataSource is! NetworkSource) {
      setState(() => _error = '请先开始在线视频播放，再推送到 PiliPlus');
      return;
    }
    String? code;
    if (!_store.targets.containsKey(device.id)) {
      code = await _input(
        title: '配对 ${device.name}',
        label: '接收端配对模式显示的 6 位码',
        code: true,
      );
      if (code == null || !mounted) return;
      if (code.length != 6) {
        setState(() => _error = '请输入 6 位配对码');
        return;
      }
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    final key = player.castMediaKey;
    final wasPlaying = player.playerStatus.isPlaying;
    try {
      final media = player.castMedia;
      await player.pause(localOnly: true);
      await _session.connect(device, code, media);
      if (!identical(PlPlayerController.instance, player) ||
          player.castMediaKey != key) {
        await _session.disconnect();
        return;
      }
      await player.attachCast(_session);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (wasPlaying &&
          identical(PlPlayerController.instance, player) &&
          player.castMediaKey == key) {
        await player.play();
      }
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.player == null) return const LanCastReceiverPage();
    return ListenableBuilder(
      listenable: Listenable.merge([_discovery, _session]),
      builder: (context, _) {
        final devices = <String, LanCastDevice>{
          for (final entry in _store.targets.entries)
            entry.key: LanCastDevice(
              id: entry.key,
              name: entry.value['name'] as String,
              uri: Uri.parse(entry.value['uri'] as String),
            ),
          for (final device in _discovery.devices.values)
            if (device.id != _store.id) device.id: device,
        };
        final busy = _connecting || _dlnaConnecting || _session.busy;
        return PopScope(
          canPop: !_connecting && !_dlnaConnecting,
          child: Material(
            child: SafeArea(
              top: false,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text('投屏', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  if (busy || _discovery.searching)
                    const LinearProgressIndicator(),
                  if (_error ?? _session.error case final error?)
                    Text(
                      error,
                      style: TextStyle(color: ColorScheme.of(context).error),
                    ),
                  if (_session.connected) ...[
                    ListTile(
                      leading: const Icon(Icons.cast_connected),
                      title: Text(_session.device!.name),
                      subtitle: Text(_session.status.title),
                    ),
                    if (!_session.online)
                      TextButton(
                        onPressed: _session.refresh,
                        child: const Text('重试连接'),
                      ),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () async {
                              await widget.player!.disconnectCast();
                              if (context.mounted) Navigator.pop(context);
                            },
                      child: const Text('断开推送（保留配对）'),
                    ),
                  ] else ...[
                    const ListTile(
                      title: Text('PiliPlus 设备'),
                    ),
                    if (_discovery.error case final error?) Text(error),
                    for (final device in devices.values)
                      ListTile(
                        leading: const Icon(Icons.connected_tv),
                        title: Text(device.name),
                        subtitle: Text(
                          _store.targets.containsKey(device.id)
                              ? 'PiliPlus · 已配对'
                              : 'PiliPlus · 未配对',
                        ),
                        enabled: !busy,
                        onTap: () => _connect(device),
                      ),
                    if (devices.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('正在查找局域网中的 PiliPlus…'),
                      ),
                    TextButton.icon(
                      onPressed: busy ? null : _discovery.start,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新搜索'),
                    ),
                    TextButton.icon(
                      onPressed: busy ? null : _manual,
                      icon: const Icon(Icons.add_link),
                      label: const Text('手动输入设备地址'),
                    ),
                    if (widget.dlnaUrl case final dlnaUrl?) ...[
                      const Divider(),
                      DLNADeviceList(
                        enabled: !_connecting && !_session.busy,
                        mediaUrl: dlnaUrl,
                        title: widget.player!.mediaTitle,
                        onBusyChanged: (value) =>
                            setState(() => _dlnaConnecting = value),
                        onConnected: () async {
                          if (identical(
                            PlPlayerController.instance,
                            widget.player,
                          )) {
                            await widget.player!.pause(localOnly: true);
                          }
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
