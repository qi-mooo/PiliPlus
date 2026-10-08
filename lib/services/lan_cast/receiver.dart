import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_status.dart';
import 'package:PiliPlus/services/lan_cast/discovery.dart';
import 'package:PiliPlus/services/lan_cast/navigation.dart';
import 'package:PiliPlus/services/lan_cast/page_settings.dart';
import 'package:PiliPlus/services/lan_cast/permission.dart';
import 'package:PiliPlus/services/lan_cast/protocol.dart';
import 'package:PiliPlus/services/lan_cast/server.dart';
import 'package:PiliPlus/services/lan_cast/session.dart';
import 'package:PiliPlus/services/lan_cast/settings.dart';
import 'package:PiliPlus/services/lan_cast/store.dart';
import 'package:PiliPlus/utils/desktop_window.dart';
import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

/// Opens normal video routes; playback belongs to their existing controller.
class LanCastPagePlayback implements LanCastPlayback, LanCastSettingsPlayback {
  LanCastMedia? _media;
  PlPlayerController? _player;
  bool _loading = false;

  PlPlayerController? get _current {
    final player = PlPlayerController.instance;
    return player != null &&
            identical(player, _player) &&
            player.isReceivingCast
        ? player
        : null;
  }

  @override
  LanCastStatus get status {
    final player = _current;
    final loading = _loading || (player?.processing ?? false);
    // A normal episode change keeps the same receiver/player. Unrelated page
    // navigation clears isReceivingCast and must still end the session.
    if (player != null &&
        !loading &&
        player.dataStatus.value == DataStatus.loaded) {
      _media = player.castMedia;
    }
    return LanCastStatus(
      title: _media?.title ?? '',
      mediaKey: player == null ? '' : _media?.key ?? '',
      position: player?.positionInMilliseconds ?? 0,
      duration: player?.durationInMilliseconds ?? 0,
      playing: player?.playerStatus.isPlaying ?? false,
      buffering: loading || (player?.isBuffering.value ?? false),
      volume: ((player?.volume.value ?? 1) * 100).clamp(0, 100),
      speed: (player?.playbackSpeed ?? 1).clamp(0.25, 4),
      isLive: _media?.isLive ?? false,
      fullscreen: player?.isFullScreen.value ?? false,
      canFullscreen: true,
      currentMedia: player == null || loading ? null : _media,
      settings: player == null || loading
          ? const []
          : LanCastPageSettings(player).snapshot,
      error: _media != null && !loading && player == null
          ? '接收端已关闭或切换视频'
          : null,
    );
  }

  @override
  Future<void> load(LanCastMedia media) async {
    if (LanCastSession.instance.connected) {
      throw const LanCastException('此设备正在向其他设备推送，请先断开', 409);
    }
    if (Get.key.currentState == null) {
      throw const LanCastException('接收端尚未就绪', 503);
    }
    await showDesktopWindow();
    final fullscreen = _current?.isFullScreen.value;
    final repeat = _current?.receivingCastRepeat;
    _loading = true;
    _media = media;
    _player = null;
    final previous = PlPlayerController.instance;
    previous?.clearReceivingCast();
    final previousGeneration = previous?.sourceGeneration;
    final deadline = DateTime.now().add(const Duration(seconds: 35));
    try {
      if (previous?.isFullScreen.value == true) {
        await previous!.triggerFullScreen(status: false);
      }
      if (media.isLive &&
          Get.currentRoute == '/liveRoom' &&
          previous?.castMediaKey == media.key &&
          previous?.dataStatus.value == DataStatus.loaded) {
        _player = previous;
        previous!.receivingCastMediaKey = media.key;
        previous.receivingCastRepeat = repeat;
        await previous.play();
        if (fullscreen != null) {
          await previous.triggerFullScreen(status: fullscreen);
        }
        return;
      }
      await openLanCastVideo(media, receiving: true);
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final player = PlPlayerController.instance;
        if (player == null ||
            player.castMediaKey != media.key ||
            (identical(player, previous) &&
                player.sourceGeneration == previousGeneration)) {
          continue;
        }
        if (player.processing) continue;
        if (player.dataStatus.value == DataStatus.error) break;
        if (player.dataStatus.value != DataStatus.loaded) continue;
        _player = player;
        player
          ..receivingCastMediaKey = media.key
          ..receivingCastRepeat = repeat;
        if (!media.isLive) {
          await player.seek(Duration(milliseconds: media.position));
          await player.setPlaybackSpeed(media.speed);
        }
        await player.play();
        if (fullscreen != null) {
          await player.triggerFullScreen(status: fullscreen);
        }
        return;
      }
      throw const LanCastException('接收端未能打开视频，请检查该设备的登录状态和播放权限', 422);
    } finally {
      _loading = false;
    }
  }

  @override
  Future<void> command(String action, double? value) async {
    final player = _current;
    if (player == null) throw const LanCastException('接收端已关闭或切换视频', 409);
    if (player.processing) throw const LanCastException('正在切换视频，请稍后重试', 422);
    switch (action) {
      case 'play':
        await player.play();
      case 'pause':
        await player.pause();
      case 'seek':
        await player.seek(Duration(milliseconds: value!.round()));
      case 'volume':
        await player.setVolume(value! / 100);
      case 'speed':
        await player.setPlaybackSpeed(value!);
      case 'fullscreen':
        await player.triggerFullScreen(status: value == 1);
    }
  }

  @override
  Future<void> setSetting(String key, Object value) async {
    final player = _current;
    if (player == null) throw const LanCastException('接收端已关闭或切换视频', 409);
    if (player.processing) throw const LanCastException('正在切换视频，请稍后重试', 422);
    _loading = true;
    try {
      await LanCastPageSettings(player).apply(key, value);
    } finally {
      _loading = false;
    }
  }

  @override
  Future<void> stop() async {
    final player = _current;
    _player?.clearReceivingCast();
    await player?.pause();
    await _player?.restoreCastWindowTopmost();
    _media = null;
    _player = null;
  }
}

/// Independent of the pairing/settings route, so opening a video keeps receiving.
class LanCastReceiver extends ChangeNotifier {
  static final instance = LanCastReceiver();
  LanCastServer? server;
  BonsoirBroadcast? _broadcast;
  StreamSubscription<BonsoirBroadcastEvent>? _events;
  List<String> addresses = [];
  String? error;
  bool busy = false;
  bool get enabled => server != null;

  Future<void> restore() async {
    if (LanCastStore.instance.enabled) await setEnabled(true);
  }

  Future<void> setEnabled(bool value) async {
    if (busy || value == enabled) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (value) {
        await ensureLanCastPermission();
        final receiver = LanCastServer(
          name: lanCastDeviceName,
          playback: LanCastPagePlayback(),
          store: LanCastStore.instance,
          onChanged: notifyListeners,
        );
        await receiver.start();
        server = receiver;
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
        );
        addresses = [
          for (final interface in interfaces)
            for (final address in interface.addresses)
              if (isLanCastAddress(address))
                '${address.address}:${receiver.port}',
        ];
        final broadcast = _broadcast = BonsoirBroadcast(
          service: BonsoirService(
            name: receiver.name,
            type: lanCastServiceType,
            port: receiver.port,
            attributes: {'v': '$lanCastProtocolVersion', 'id': receiver.id},
          ),
          printLogs: false,
        );
        try {
          await broadcast.initialize();
          _events = broadcast.eventStream?.listen(
            (_) {},
            onError: (Object _) {
              error = '设备广播不可用，请手动输入地址';
              notifyListeners();
            },
          );
          await broadcast.start();
        } catch (_) {
          error = '自动发现不可用，请手动输入下方地址';
        }
      } else {
        await _events?.cancel();
        final broadcast = _broadcast;
        if (broadcast != null && broadcast.isReady && !broadcast.isStopped) {
          try {
            await broadcast.stop();
          } catch (_) {}
        }
        _broadcast = null;
        await server?.close();
        server = null;
        addresses = [];
      }
      LanCastStore.instance.data['enabled'] = value;
      await LanCastStore.instance.save();
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
