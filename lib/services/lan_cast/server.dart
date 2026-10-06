import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:PiliPlus/services/lan_cast/protocol.dart';

/// Only alive while the user has the receiving page open.
class LanCastServer {
  LanCastServer({required this.name, required this.playback});

  final String name;
  final LanCastPlayback playback;
  final String id = lanCastSecret(12);
  String pairingCode = _newCode();
  String? sender;
  String? _token;
  HttpServer? _server;
  Future<void> _mutations = Future.value();
  final List<DateTime> _failedPairings = [];
  bool _closed = false;

  int get port => _server!.port;
  bool get paired => _token != null;
  static String _newCode() =>
      Random.secure().nextInt(1000000).toString().padLeft(6, '0');

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
        };
      } else if (request.method == 'GET' && path == '/status') {
        _authorize(request);
        result = playback.status.toJson();
      } else if (request.method == 'POST' &&
          ['/pair', '/load', '/command', '/disconnect'].contains(path)) {
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

  void _authorize(HttpRequest request) {
    if (_token == null ||
        request.headers.value(HttpHeaders.authorizationHeader) !=
            'Bearer $_token') {
      throw const LanCastException('连接已结束，请重新连接设备', 401);
    }
  }

  Future<Map<String, dynamic>> _mutate(
    HttpRequest request,
    Map<String, dynamic> body,
  ) async {
    if (_closed) throw const LanCastException('接收已关闭', 503);
    final path = request.uri.path;
    if (path == '/pair') {
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
      if (paired) throw const LanCastException('设备正在接受其他设备的控制，请先在接收端断开', 409);
      sender = lanCastText(body['sender'], maxLength: 80);
      _token = lanCastSecret();
      return {'token': _token};
    }
    // Recheck after queued operations: a previous request may have revoked the token.
    _authorize(request);
    switch (path) {
      case '/load':
        await playback.load(LanCastMedia.fromJson(body));
      case '/command':
        await _control(body['action'], body['value']);
      case '/disconnect':
        await _release();
    }
    return playback.status.toJson();
  }

  // Local receiver controls share the same queue as network commands.
  Future<void> control(String action, [double? value]) =>
      _serialize(() => _control(action, value));

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
      default:
        throw const LanCastException('不支持的遥控操作');
    }
    await playback.command(action as String, value);
  }

  Future<void> _release() async {
    _token = null;
    sender = null;
    pairingCode = _newCode();
    await playback.stop();
  }

  Future<void> disconnect() => _serialize(_release);

  Future<void> close() async {
    _closed = true;
    await _server?.close(force: true);
    await _serialize(_release);
  }
}
