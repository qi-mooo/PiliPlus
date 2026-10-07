import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/services/lan_cast/protocol.dart';

class LanCastClient {
  LanCastClient(Uri uri) : uri = lanCastAddress(uri.toString()) {
    _http
      ..connectionTimeout = const Duration(seconds: 5)
      ..findProxy = (_) => 'DIRECT';
  }

  final Uri uri;
  final HttpClient _http = HttpClient();
  String? token;
  bool get paired => token != null;

  Future<Map<String, dynamic>> _request(
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    HttpClientRequest? request;
    var timedOut = false;
    try {
      return await (() async {
        request = await _http.openUrl(
          body == null ? 'GET' : 'POST',
          uri.replace(path: path),
        );
        final req = request!..followRedirects = false;
        if (timedOut) {
          req.abort();
          throw const LanCastException('连接超时', 408);
        }
        if (token != null) {
          req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        }
        if (body != null) {
          req.headers.contentType = ContentType.json;
          req.write(jsonEncode(body));
        }
        final response = await req.close();
        final result = await readLanCastJson(response);
        if (response.statusCode != 200) {
          throw LanCastException(
            result['error'] as String? ?? '设备返回了错误',
            response.statusCode,
          );
        }
        return result;
      })().timeout(Duration(seconds: path == '/load' ? 45 : 15));
    } on TimeoutException {
      timedOut = true;
      request?.abort();
      throw const LanCastException('连接超时，请检查设备是否在同一局域网且已开启接收', 408);
    } on SocketException {
      throw const LanCastException('无法连接设备，请检查网络和接收端地址', 503);
    } on HttpException {
      throw const LanCastException('连接已中断，请重试', 503);
    } on FormatException {
      throw const LanCastException('设备返回的内容无效，请检查地址', 502);
    }
  }

  Future<LanCastDevice> info() async {
    final result = await _request('/info');
    if (result['app'] != 'PiliPlus' ||
        result['protocol'] != lanCastProtocolVersion) {
      throw const LanCastException('此设备不支持当前版本的局域网推送');
    }
    return LanCastDevice(
      id: lanCastText(result['id']),
      name: lanCastText(result['name']),
      uri: uri,
    );
  }

  Future<void> pair(String code, String sender, String id) async {
    final result = await _request('/pair', {
      'code': code,
      'sender': sender,
      'id': id,
    });
    token = lanCastText(result['token']);
  }

  Future<void> connect() async {
    await _request('/connect', {});
  }

  Future<void> unpair() async {
    await _request('/unpair', {});
    token = null;
  }

  Future<LanCastStatus> load(LanCastMedia media) async =>
      LanCastStatus.fromJson(await _request('/load', media.toJson()));
  Future<LanCastStatus> status() async =>
      LanCastStatus.fromJson(await _request('/status'));
  Future<LanCastStatus> command(String action, [double? value]) async =>
      LanCastStatus.fromJson(
        await _request('/command', {'action': action, 'value': value}),
      );
  Future<void> disconnect() async {
    await _request('/disconnect', {});
  }

  Future<LanCastStatus> setSetting(
    String mediaKey,
    String key,
    Object value,
  ) async => LanCastStatus.fromJson(
    await _request('/settings', {
      'mediaKey': mediaKey,
      'key': key,
      'value': value,
    }),
  );

  void close() => _http.close(force: true);
}
