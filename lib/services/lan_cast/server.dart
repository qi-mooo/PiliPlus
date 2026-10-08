import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:PiliPlus/services/lan_cast/protocol.dart';
import 'package:PiliPlus/services/lan_cast/settings.dart';
import 'package:PiliPlus/services/lan_cast/store.dart';

class LanCastServer {
  LanCastServer({
    required this.name,
    required this.playback,
    required this.store,
    this.onChanged,
  });

  final String name;
  final LanCastPlayback playback;
  final LanCastStore store;
  final void Function()? onChanged;
  String get id => store.id;
  String? pairingCode;
  Timer? _pairingTimer;
  String? _activePeer;
  DateTime? _lastSeen;
  String? get sender => store.peers[_activePeer]?['name'] as String?;
  HttpServer? _server;
  Future<void> _mutations = Future.value();
  final List<DateTime> _failedPairings = [];
  bool _closed = false;

  int get port => _server!.port;
  bool get paired => _activePeer != null;
  static String _newCode() =>
      Random.secure().nextInt(1000000).toString().padLeft(6, '0');

  void beginPairing() {
    pairingCode = _newCode();
    _pairingTimer?.cancel();
    _pairingTimer = Timer(const Duration(minutes: 2), endPairing);
    onChanged?.call();
  }

  void endPairing() {
    pairingCode = null;
    _pairingTimer?.cancel();
    onChanged?.call();
  }

  Future<void> revoke(String peer) => _serialize(() async {
    await store.remove('peers', peer);
    if (_activePeer == peer) await _release();
    onChanged?.call();
  });

  Future<void> start({InternetAddress? address}) async {
    _server = await HttpServer.bind(address ?? InternetAddress.anyIPv4, 0);
    _server!.idleTimeout = const Duration(seconds: 15);
    _server!.listen((request) => unawaited(_handle(request)));
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.contentType = ContentType.json;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    try {
      if (_closed) throw const LanCastException('接收已关闭', 503);
      final remote = request.connectionInfo?.remoteAddress;
      if (remote == null || !isLanCastAddress(remote)) {
        throw const LanCastException('仅支持局域网连接', 403);
      }
      if (request.headers.value('origin') != null) {
        throw const LanCastException('不支持浏览器请求', 403);
      }
      final path = request.uri.path;
      Map<String, dynamic> result;
      if (request.method == 'GET' && path == '/info') {
        result = {
          'protocol': lanCastProtocolVersion,
          'app': 'PiliPlus',
          'id': id,
          'name': name,
          'paired': paired,
          'pairing': pairingCode != null,
        };
      } else if (request.method == 'GET' && path == '/status') {
        _authorize(request, active: true);
        result = playback.status.toJson();
      } else if (request.method == 'POST' &&
          [
            '/pair',
            '/connect',
            '/load',
            '/command',
            '/settings',
            '/disconnect',
            '/unpair',
          ].contains(path)) {
        if (path != '/pair') _authorize(request);
        if (request.headers.contentType?.mimeType != 'application/json') {
          throw const LanCastException('需要 JSON 请求', 415);
        }
        final body = await readLanCastJson(request)
            .timeout(const Duration(seconds: 5));
        result = await _serialize(() => _mutate(request, body));
      } else {
        throw const LanCastException('未知的控制请求', 404);
      }
      response.write(jsonEncode(result));
    } on LanCastException catch (e) {
      response
        ..statusCode = e.statusCode
        ..write(jsonEncode({'error': e.message}));
    } on FormatException {
      response
        ..statusCode = 400
        ..write(jsonEncode({'error': '无效的请求内容'}));
    } catch (_) {
      response
        ..statusCode = 500
        ..write(jsonEncode({'error': '接收端暂时无法完成操作，请重试'}));
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _mutations.then((_) => action());
    _mutations = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  String _authorize(HttpRequest request, {bool active = false}) {
    final authorization = request.headers.value(
      HttpHeaders.authorizationHeader,
    );
    for (final peer in store.peers.entries) {
      if (authorization == 'Bearer ${peer.value['token']}') {
        if (active && _activePeer != peer.key) {
          throw const LanCastException('推送连接已结束，请重新选择设备', 409);
        }
        if (active) _lastSeen = DateTime.now();
        return peer.key;
      }
    }
    throw const LanCastException('此设备尚未配对或配对已取消，请重新配对', 401);
  }

  Future<Map<String, dynamic>> _mutate(
    HttpRequest request,
    Map<String, dynamic> body,
  ) async {
    if (_closed) throw const LanCastException('接收已关闭', 503);
    final path = request.uri.path;
    if (path == '/pair') {
      if (pairingCode == null) {
        throw const LanCastException('请先在接收端开启配对模式', 403);
      }
      final now = DateTime.now();
      _failedPairings.removeWhere(
        (time) => now.difference(time).inSeconds >= 60,
      );
      if (_failedPairings.length >= 6) {
        throw const LanCastException('连接码尝试过多，请一分钟后再试', 429);
      }
      if (body['code'] != pairingCode) {
        _failedPairings.add(now);
        throw const LanCastException('连接码不正确', 403);
      }
      final peer = lanCastText(body['id'], maxLength: 80);
      final name = lanCastText(body['sender'], maxLength: 80);
      final token = lanCastSecret();
      await store.put('peers', peer, {'name': name, 'token': token});
      endPairing();
      return {'token': token};
    }
    // Recheck after queued operations: a previous request may have revoked the token.
    final peer = _authorize(request);
    if (path == '/unpair') {
      await store.remove('peers', peer);
      if (_activePeer == peer) await _release();
      onChanged?.call();
      return {};
    }
    if (path == '/connect') {
      if (_activePeer != null &&
          _activePeer != peer &&
          DateTime.now().difference(_lastSeen!).inSeconds < 30) {
        throw const LanCastException('另一台设备正在推送，请先断开', 409);
      }
      _activePeer = peer;
      _lastSeen = DateTime.now();
      onChanged?.call();
      return playback.status.toJson();
    }
    _authorize(request, active: true);
    switch (path) {
      case '/load':
        await playback.load(LanCastMedia.fromJson(body));
      case '/command':
        if (body['mediaKey'] != null &&
            body['mediaKey'] != playback.status.mediaKey) {
          throw const LanCastException('视频已切换，请等待控制页更新', 422);
        }
        await _control(body['action'], body['value']);
      case '/settings':
        if (playback is! LanCastSettingsPlayback) {
          throw const LanCastException('请更新接收端以支持播放设置', 422);
        }
        final status = playback.status;
        if (body['mediaKey'] != status.mediaKey || status.mediaKey.isEmpty) {
          throw const LanCastException('视频已切换，请重新打开设置', 422);
        }
        final key = lanCastText(body['key'], maxLength: 80);
        final setting = status.settings.where((e) => e.key == key).firstOrNull;
        if (setting == null) throw const LanCastException('接收端不支持此设置', 422);
        await (playback as LanCastSettingsPlayback).setSetting(
          key,
          setting.validate(body['value']),
        );
      case '/disconnect':
        await _release();
    }
    return playback.status.toJson();
  }

  Future<void> _control(Object? action, Object? rawValue) async {
    if (_closed) throw const LanCastException('接收已关闭', 503);
    final double? value;
    switch (action) {
      case 'play':
      case 'pause':
        value = null;
      case 'seek':
        if (playback.status.isLive) throw const LanCastException('直播不支持调整进度');
        value = lanCastNumber(rawValue, 0, 2592000000);
      case 'volume':
        value = lanCastNumber(rawValue, 0, 100);
      case 'speed':
        if (playback.status.isLive) throw const LanCastException('直播不支持倍速');
        value = lanCastNumber(rawValue, 0.25, 4);
      case 'fullscreen':
        if (!playback.status.canFullscreen) {
          throw const LanCastException('接收端不支持远程全屏，请更新接收端');
        }
        value = lanCastNumber(rawValue, 0, 1);
        if (value != 0 && value != 1) throw const LanCastException('无效的全屏状态');
      default:
        throw const LanCastException('不支持的遥控操作');
    }
    await playback.command(action as String, value);
  }

  Future<void> _release() async {
    _activePeer = null;
    _lastSeen = null;
    await playback.stop();
    onChanged?.call();
  }

  Future<void> disconnect() => _serialize(_release);

  Future<void> close() async {
    _closed = true;
    endPairing();
    await _server?.close(force: true);
    await _serialize(_release);
  }
}
