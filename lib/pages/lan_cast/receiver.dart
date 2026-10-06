import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/pages/lan_cast/controls.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/services/lan_cast/discovery.dart';
import 'package:PiliPlus/services/lan_cast/player.dart';
import 'package:PiliPlus/services/lan_cast/protocol.dart';
import 'package:PiliPlus/services/lan_cast/permission.dart';
import 'package:PiliPlus/services/lan_cast/server.dart';
import 'package:bonsoir/bonsoir.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class LanCastReceiverPage extends StatefulWidget {
  const LanCastReceiverPage({super.key});
  @override
  State<LanCastReceiverPage> createState() => _LanCastReceiverPageState();
}

class _LanCastReceiverPageState extends State<LanCastReceiverPage> {
  final _player = LanCastPlayer();
  late final _server = LanCastServer(
    name: lanCastDeviceName,
    playback: _player,
  );
  late final Future<void> _starting;
  BonsoirBroadcast? _broadcast;
  StreamSubscription<BonsoirBroadcastEvent>? _broadcastEvents;
  List<String> _addresses = [];
  String? _error;
  String? _discoveryError;
  bool _ready = false;
  bool _fullscreen = false;
  bool _closing = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _starting = _start();
  }

  Future<void> _start() async {
    try {
      await ensureLanCastPermission();
      if (_closing) return;
      await PlPlayerController.pauseIfExists();
      await _player.initialize();
      if (_closing) return;
      await _server.start();
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      _addresses = [
        for (final interface in interfaces)
          for (final address in interface.addresses)
            if (isLanCastAddress(address)) '${address.address}:${_server.port}',
      ];
      if (_closing) return;
      await WakelockPlus.enable();
      final broadcast = _broadcast = BonsoirBroadcast(
        service: BonsoirService(
          name: _server.name,
          type: lanCastServiceType,
          port: _server.port,
          attributes: {'v': '$lanCastProtocolVersion', 'id': _server.id},
        ),
        printLogs: false,
      );
      try {
        await broadcast.initialize();
        if (_closing) return;
        _broadcastEvents = broadcast.eventStream?.listen(
          (event) {
            if (event is BonsoirBroadcastUnknownEvent && mounted) {
              setState(() => _discoveryError = '设备广播不可用，请在发送端手动输入地址');
            }
          },
          onError: (Object _) {
            if (mounted) {
              setState(() => _discoveryError = '设备广播不可用，请在发送端手动输入地址');
            }
          },
        );
        await broadcast.start();
      } catch (_) {
        _discoveryError = '自动发现不可用，请在发送端手动输入下方地址';
      }
      _ready = true;
    } catch (e) {
      _error = e is LanCastException ? e.message : '无法开启接收，请检查网络权限后重新打开此页面';
    }
    if (mounted) setState(() {});
  }

  Future<void> _command(String action, [double? value]) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _server.control(action, value);
    } catch (_) {
      if (mounted) setState(() => _error = '操作失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    try {
      await _server.disconnect();
    } catch (_) {
      _error = '停止播放失败，请关闭接收页面';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    await _starting;
    await _broadcastEvents?.cancel();
    final broadcast = _broadcast;
    if (broadcast != null && broadcast.isReady && !broadcast.isStopped) {
      try {
        await broadcast.stop();
      } catch (_) {}
    }
    try {
      await _server.close();
    } catch (_) {}
    await _player.close();
    if (PlPlayerController.getPlayerStatusIfExists()?.isPlaying != true) {
      await WakelockPlus.disable();
    }
  }

  @override
  void dispose() {
    _closing = true;
    unawaited(_close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _fullscreen) setState(() => _fullscreen = false);
      },
      child: ListenableBuilder(
        listenable: _player,
        builder: (context, _) {
          final status = _player.status;
          Widget video() => Video(
            controller: _player.video!,
            controls: null,
            wakelock: false,
            pauseUponEnteringBackgroundMode: false,
          );
          if (_fullscreen && _player.video != null) {
            return Material(
              color: Colors.black,
              child: Stack(
                children: [
                  Positioned.fill(child: video()),
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + 8,
                    right: 12,
                    child: IconButton(
                      tooltip: '退出全屏',
                      onPressed: () => setState(() => _fullscreen = false),
                      icon: const Icon(
                        Icons.fullscreen_exit,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          return SimpleScaffold(
            appBar: AppBar(title: const Text('接收播放')),
            body: SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_error case final error?)
                        Text(
                          error,
                          style: TextStyle(
                            color: ColorScheme.of(context).error,
                          ),
                        )
                      else if (!_ready)
                        const Center(child: CircularProgressIndicator()),
                      if (_ready) ...[
                        if (status.title.isNotEmpty) ...[
                          AspectRatio(
                            aspectRatio: 16 / 9,
                            child: ColoredBox(
                              color: Colors.black,
                              child: video(),
                            ),
                          ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(status.title),
                            subtitle: Text('来自 ${_server.sender ?? '局域网设备'}'),
                            trailing: IconButton(
                              tooltip: '全屏',
                              onPressed: () =>
                                  setState(() => _fullscreen = true),
                              icon: const Icon(Icons.fullscreen),
                            ),
                          ),
                          LanCastControls(
                            status: status,
                            onCommand: _command,
                            enabled: !_busy,
                          ),
                        ] else ...[
                          const SizedBox(height: 32),
                          const Icon(Icons.connected_tv, size: 72),
                          const SizedBox(height: 16),
                          Center(
                            child: Text(
                              _server.name,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            '在另一台 PiliPlus 的播放器中点击“局域网推送”，选择此设备。接收期间请保持此页面打开。',
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 20),
                        if (!_server.paired) ...[
                          const Center(child: Text('连接码')),
                          Center(
                            child: SelectableText(
                              _server.pairingCode,
                              style: Theme.of(context).textTheme.displaySmall
                                  ?.copyWith(letterSpacing: 6),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        if (_discoveryError case final error?) Text(error),
                        const Text('手动连接地址', textAlign: TextAlign.center),
                        for (final address in _addresses)
                          Center(child: SelectableText(address)),
                        if (_addresses.isEmpty)
                          const Text('未找到局域网地址，请连接 Wi-Fi 或有线网络后重新打开此页面。'),
                        if (_server.paired)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : _disconnect,
                              icon: const Icon(Icons.link_off),
                              label: const Text('断开并停止播放'),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
