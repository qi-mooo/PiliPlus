import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/pages/lan_cast/controls.dart';
import 'package:PiliPlus/services/lan_cast/client.dart';
import 'package:PiliPlus/services/lan_cast/discovery.dart';
import 'package:PiliPlus/services/lan_cast/protocol.dart';
import 'package:PiliPlus/services/lan_cast/permission.dart';
import 'package:PiliPlus/services/lan_cast/session.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class LanCastPage extends StatefulWidget {
  const LanCastPage({super.key, this.media, this.onPushed});
  final LanCastMedia Function()? media;
  final Future<void> Function()? onPushed;

  @override
  State<LanCastPage> createState() => _LanCastPageState();
}

class _LanCastPageState extends State<LanCastPage> {
  final _discovery = LanCastDiscovery();
  final _session = LanCastSession.instance;
  String? _error;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    if (!_session.connected) _discovery.start();
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
          onChanged: (value) => input = value,
          autofocus: true,
          maxLength: code ? 6 : 80,
          keyboardType: code ? TextInputType.number : TextInputType.url,
          inputFormatters: code
              ? [FilteringTextInputFormatter.digitsOnly]
              : null,
          decoration: InputDecoration(
            labelText: label,
            hintText: code ? null : '192.168.1.8:54321',
          ),
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
    final address = await _input(title: '手动连接', label: '接收端地址');
    if (address == null || !mounted) return;
    LanCastClient? client;
    try {
      await ensureLanCastPermission();
      if (!mounted) return;
      client = LanCastClient(lanCastAddress(address));
      setState(() {
        _connecting = true;
        _error = null;
      });
      final device = await client.info();
      if (!mounted) return;
      setState(() => _connecting = false);
      await _connect(device);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      client?.close();
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _connect(LanCastDevice device) async {
    if (widget.media == null) return;
    final code = await _input(
      title: '连接 ${device.name}',
      label: '接收端显示的 6 位连接码',
      code: true,
    );
    if (code == null || !mounted) return;
    if (code.length != 6) {
      setState(() => _error = '请输入 6 位连接码');
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      final media = widget.media!();
      await _session.connect(device, code, media);
      await widget.onPushed?.call();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _pushCurrent() async {
    try {
      if (await _session.load(widget.media!())) await widget.onPushed?.call();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_discovery, _session]),
    builder: (context, _) {
      final connected = _session.connected;
      final busy = _connecting || _session.busy;
      return SimpleScaffold(
        appBar: AppBar(
          title: Text(connected ? '播放遥控器' : '局域网推送'),
          actions: [
            if (!connected)
              IconButton(
                tooltip: '重新搜索',
                onPressed: _discovery.searching ? null : _discovery.start,
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (busy || _discovery.searching)
                    const LinearProgressIndicator(),
                  if (_error ?? _session.error case final error?)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        error,
                        style: TextStyle(color: ColorScheme.of(context).error),
                      ),
                    ),
                  if (connected) ...[
                    const SizedBox(height: 20),
                    Icon(
                      _session.online ? Icons.cast_connected : Icons.wifi_off,
                      size: 56,
                      color: ColorScheme.of(context).primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _session.device!.name,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(_session.status.title, textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    LanCastControls(
                      status: _session.status,
                      onCommand: _session.command,
                      enabled: _session.online && !busy,
                    ),
                    if (!_session.online)
                      OutlinedButton.icon(
                        onPressed: busy ? null : _session.refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('重新连接'),
                      ),
                    if (widget.media != null)
                      TextButton.icon(
                        onPressed: busy ? null : _pushCurrent,
                        icon: const Icon(Icons.send_to_mobile),
                        label: const Text('推送当前视频'),
                      ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : _session.disconnect,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('结束推送并停止播放'),
                    ),
                    if (!_session.online)
                      TextButton(
                        onPressed: busy ? null : _session.forget,
                        child: const Text('关闭遥控器（接收端可能继续播放）'),
                      ),
                    const SizedBox(height: 12),
                    const Text(
                      '返回后远端继续播放，可从播放器或“设置 → 播放设置 → 局域网推送”重新打开遥控器。',
                      textAlign: TextAlign.center,
                    ),
                  ] else ...[
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.devices),
                      title: Text('推送到另一台 PiliPlus'),
                      subtitle: Text(
                        '两台设备连接同一局域网，在接收端打开“设置 → 播放设置 → 局域网推送 → 接收播放”。',
                      ),
                    ),
                    if (widget.media == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('发送视频时，请从视频或直播播放器上的“局域网推送”按钮进入。'),
                      ),
                    if (_discovery.error case final error?) Text(error),
                    if (_discovery.devices.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 36),
                        child: Column(
                          children: [
                            Icon(Icons.wifi_find, size: 48),
                            SizedBox(height: 12),
                            Text('正在等待接收设备…'),
                            Text('请开启接收播放并允许本地网络访问'),
                          ],
                        ),
                      ),
                    for (final device in _discovery.devices.values)
                      ListTile(
                        leading: const Icon(Icons.connected_tv),
                        title: Text(device.name),
                        subtitle: Text('${device.uri.host}:${device.uri.port}'),
                        trailing: const Icon(Icons.chevron_right),
                        enabled: !busy && widget.media != null,
                        onTap: () => _connect(device),
                      ),
                    if (widget.media != null)
                      OutlinedButton.icon(
                        onPressed: busy ? null : _manual,
                        icon: const Icon(Icons.add_link),
                        label: const Text('手动输入设备地址'),
                      ),
                    const Divider(height: 40),
                    FilledButton.icon(
                      onPressed: busy
                          ? null
                          : () => Get.toNamed('/lanCastReceiver'),
                      icon: const Icon(Icons.tv),
                      label: const Text('在此设备接收播放'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
