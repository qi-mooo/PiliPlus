import 'dart:async';

import 'package:PiliPlus/services/lan_cast/client.dart';
import 'package:PiliPlus/services/lan_cast/discovery.dart';
import 'package:PiliPlus/services/lan_cast/protocol.dart';
import 'package:flutter/foundation.dart';

/// Kept across navigation so the remote can be reopened from the player/settings.
class LanCastSession extends ChangeNotifier {
  static final instance = LanCastSession();

  LanCastClient? _client;
  LanCastDevice? device;
  LanCastStatus status = const LanCastStatus();
  String? error;
  bool busy = false;
  bool online = false;
  Timer? _poll;
  bool _polling = false;
  int _generation = 0;
  bool _disposed = false;

  bool get connected => _client != null;

  Future<void> connect(
    LanCastDevice target,
    String code,
    LanCastMedia media,
  ) async {
    if (busy || connected) throw const LanCastException('请先结束当前推送');
    final client = LanCastClient(target.uri);
    busy = true;
    error = null;
    notifyListeners();
    try {
      final verified = await client.info();
      if (verified.id != target.id) {
        throw const LanCastException('接收端已重新启动，请重新选择设备');
      }
      await client.pair(code, lanCastDeviceName);
      final state = await client.load(media);
      if (_disposed) {
        await client.disconnect();
        client.close();
        return;
      }
      _client = client;
      device = verified;
      status = state;
      online = true;
      _generation++;
      _poll = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(refresh()),
      );
    } catch (_) {
      if (client.paired) {
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
      status = state;
      online = true;
      error = null;
    } catch (e) {
      if (generation != _generation || busy) return;
      online = false;
      error = e.toString();
      if (e is LanCastException && [408, 503].contains(e.statusCode)) {
        online = false;
      }
      if (e is LanCastException && e.statusCode == 401) forget();
    } finally {
      _polling = false;
      notifyListeners();
    }
  }

  Future<bool> _operate(
    Future<LanCastStatus> Function(LanCastClient) action,
  ) async {
    final client = _client;
    if (client == null || busy) return false;
    busy = true;
    _generation++;
    error = null;
    notifyListeners();
    try {
      status = await action(client);
      online = connected;
      return true;
    } catch (e) {
      error = e.toString();
      if (e is LanCastException && [408, 503].contains(e.statusCode)) {
        online = false;
      }
      if (e is LanCastException && e.statusCode == 401) forget();
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> command(String action, [double? value]) async {
    await _operate((client) => client.command(action, value));
  }

  Future<bool> load(LanCastMedia media) =>
      _operate((client) => client.load(media));

  Future<void> disconnect() async {
    if (_client == null || busy) return;
    await _operate((client) async {
      await client.disconnect();
      forget();
      return const LanCastStatus();
    });
  }

  void forget() {
    _generation++;
    _poll?.cancel();
    _client?.close();
    _client = null;
    device = null;
    online = false;
    status = const LanCastStatus();
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    forget();
    super.dispose();
  }
}
