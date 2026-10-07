import 'dart:async';

import 'package:PiliPlus/services/lan_cast/client.dart';
import 'package:PiliPlus/services/lan_cast/discovery.dart';
import 'package:PiliPlus/services/lan_cast/protocol.dart';
import 'package:PiliPlus/services/lan_cast/store.dart';
import 'package:flutter/foundation.dart';

/// One outgoing session. Trust survives disconnects; playback does not auto-start.
class LanCastSession extends ChangeNotifier {
  LanCastSession({this.trustStore});
  static final instance = LanCastSession();
  final LanCastStore? trustStore;
  LanCastStore get store => trustStore ?? LanCastStore.instance;
  LanCastClient? _client;
  LanCastDevice? device;
  LanCastStatus status = const LanCastStatus();
  String? mediaKey;
  String? error;
  bool busy = false;
  bool online = false;
  Timer? _poll;
  bool _polling = false;
  int _generation = 0;
  bool _disposed = false;
  Future<void> _commands = Future.value();
  bool get connected => _client != null;

  Future<void> connect(
    LanCastDevice target,
    String? code,
    LanCastMedia media,
  ) async {
    if (busy || connected) throw const LanCastException('请先断开当前推送');
    if (target.id == store.id) throw const LanCastException('不能向本机推送');
    final client = LanCastClient(target.uri);
    busy = true;
    error = null;
    notifyListeners();
    var claimed = false;
    try {
      final verified = await client.info();
      if (verified.id != target.id) {
        throw const LanCastException('设备地址已变化，请重新搜索');
      }
      client.token = store.targets[target.id]?['token'] as String?;
      if (client.token == null) {
        if (code == null) throw const LanCastException('请先配对此设备', 401);
        await client.pair(code, lanCastDeviceName, store.id);
      }
      await store.put('targets', target.id, {
        'name': verified.name,
        'uri': verified.uri.toString(),
        'token': client.token,
      });
      await client.connect();
      claimed = true;
      final state = await client.load(media);
      if (state.mediaKey != media.key || state.error != null) {
        throw LanCastException(state.error ?? '接收端未打开指定视频', 422);
      }
      _client = client;
      device = verified;
      mediaKey = media.key;
      status = state;
      online = true;
      _generation++;
      _poll = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(refresh()),
      );
    } catch (e) {
      if (e is LanCastException && e.statusCode == 401) {
        await store.remove('targets', target.id);
      }
      if (claimed) {
        try {
          await client.disconnect();
        } catch (_) {}
      }
      client.close();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    final client = _client;
    if (client == null || busy || _polling) return;
    _polling = true;
    final generation = _generation;
    try {
      final state = await client.status();
      if (generation != _generation || busy) return;
      online = true;
      error = state.error;
      if (state.mediaKey != mediaKey || state.error != null) {
        error ??= '接收端已切换视频，推送已结束';
        forget();
      } else {
        status = state;
      }
    } catch (e) {
      if (generation != _generation || busy) return;
      online = false;
      error = e.toString();
      if (e is LanCastException && e.statusCode == 401 && device != null) {
        await store.remove('targets', device!.id);
      }
      if (e is LanCastException && [401, 409].contains(e.statusCode)) forget();
    } finally {
      _polling = false;
      notifyListeners();
    }
  }

  // Queue gestures, including long-press speed restore and seek followed by play.
  Future<void> command(String action, [double? value]) {
    final client = _client;
    if (client == null) return Future.value();
    final result = _commands.then((_) async {
      if (_client != client) return;
      busy = true;
      _generation++;
      try {
        final state = await client.command(action, value);
        if (_client != client) return;
        status = state;
        online = true;
        error = null;
      } catch (e) {
        if (_client != client) return;
        error = e.toString();
        online = false;
        if (e is LanCastException && e.statusCode == 401 && device != null) {
          await store.remove('targets', device!.id);
        }
        if (e is LanCastException && [401, 409].contains(e.statusCode)) {
          forget();
        }
      } finally {
        if (_client == client) busy = false;
        notifyListeners();
      }
    });
    _commands = result;
    return result;
  }

  Future<void> disconnect() async {
    final client = _client;
    if (client == null) return;
    busy = true;
    _generation++;
    _poll?.cancel();
    _client = null;
    device = null;
    online = false;
    notifyListeners();
    try {
      await _commands;
      await client.disconnect();
    } catch (e) {
      error = '$e（接收端可能继续播放）';
      notifyListeners();
    } finally {
      client.close();
      busy = false;
      notifyListeners();
    }
  }

  void forget() {
    busy = false;
    _generation++;
    _poll?.cancel();
    _client?.close();
    _client = null;
    device = null;
    online = false;
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    forget();
    _disposed = true;
    super.dispose();
  }
}
