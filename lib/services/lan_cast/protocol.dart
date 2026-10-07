import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:PiliPlus/services/lan_cast/settings.dart';

const lanCastServiceType = '_piliplus._tcp';
const lanCastProtocolVersion = 2;
const lanCastBodyLimit = 64 * 1024;

String lanCastSecret([int bytes = 24]) {
  final random = Random.secure();
  return base64Url.encode(List.generate(bytes, (_) => random.nextInt(256)));
}

class LanCastException implements Exception {
  const LanCastException(this.message, [this.statusCode = 400]);
  final String message;
  final int statusCode;
  @override
  String toString() => message;
}

String lanCastText(Object? value, {int maxLength = 300}) {
  if (value is! String || value.trim().isEmpty || value.length > maxLength) {
    throw const LanCastException('无效的文本参数');
  }
  return value.trim();
}

double lanCastNumber(Object? value, double min, double max) {
  if (value is! num || !value.isFinite || value < min || value > max) {
    throw const LanCastException('控制参数超出范围');
  }
  return value.toDouble();
}

class LanCastMedia {
  const LanCastMedia({
    required this.title,
    this.kind = 'ugc',
    this.aid,
    this.bvid,
    this.cid,
    this.epId,
    this.seasonId,
    this.pgcType,
    this.roomId,
    this.position = 0,
    this.speed = 1,
  });

  final String title;
  final String kind;
  final int? aid, cid, epId, seasonId, pgcType, roomId;
  final String? bvid;
  final int position;
  final double speed;
  bool get isLive => kind == 'live';
  String get key => isLive ? 'live:$roomId' : '$kind:$aid:$cid:$epId';

  factory LanCastMedia.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'];
    if (!['ugc', 'pgc', 'pugv', 'live'].contains(kind)) {
      throw const LanCastException('无效的播放类型');
    }
    int? id(String name, {bool required = false}) {
      final value = json[name];
      if (value == null && !required) return null;
      if (value is! int || value <= 0 || value > 9007199254740991) {
        throw const LanCastException('无效的视频标识');
      }
      return value;
    }

    final bvid = json['bvid'];
    if (bvid != null &&
        (bvid is! String || !RegExp(r'^BV[0-9A-Za-z]{10}$').hasMatch(bvid))) {
      throw const LanCastException('无效的视频标识');
    }
    return LanCastMedia(
      title: lanCastText(json['title']),
      kind: kind as String,
      aid: id('aid', required: kind != 'live'),
      bvid: bvid as String?,
      cid: id('cid', required: kind != 'live'),
      epId: id('epId', required: kind == 'pgc' || kind == 'pugv'),
      seasonId: id('seasonId'),
      pgcType: id('pgcType'),
      roomId: id('roomId', required: kind == 'live'),
      position: lanCastNumber(json['position'], 0, 2592000000).round(),
      speed: lanCastNumber(json['speed'], 0.25, 4),
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'kind': kind,
    'aid': aid,
    'bvid': bvid,
    'cid': cid,
    'epId': epId,
    'seasonId': seasonId,
    'pgcType': pgcType,
    'roomId': roomId,
    'position': position,
    'speed': speed,
  };
}

class LanCastStatus {
  const LanCastStatus({
    this.title = '',
    this.position = 0,
    this.duration = 0,
    this.playing = false,
    this.buffering = false,
    this.volume = 100,
    this.speed = 1,
    this.isLive = false,
    this.error,
    this.mediaKey = '',
    this.fullscreen = false,
    this.canFullscreen = false,
    this.settings = const [],
  });

  final String title;
  final int position;
  final int duration;
  final bool playing;
  final bool buffering;
  final double volume;
  final double speed;
  final bool isLive;
  final String? error;
  final String mediaKey;
  final bool fullscreen;
  final bool canFullscreen;
  final List<LanCastSetting> settings;

  factory LanCastStatus.fromJson(Map<String, dynamic> json) => LanCastStatus(
    title: json['title'] as String,
    position: lanCastNumber(json['position'], 0, 2592000000).round(),
    duration: lanCastNumber(json['duration'], 0, 2592000000).round(),
    playing: json['playing'] as bool,
    buffering: json['buffering'] as bool,
    volume: lanCastNumber(json['volume'], 0, 100),
    speed: lanCastNumber(json['speed'], 0.25, 4),
    isLive: json['isLive'] as bool,
    error: json['error'] as String?,
    mediaKey: json['mediaKey'] as String? ?? '',
    fullscreen: json['fullscreen'] as bool? ?? false,
    canFullscreen: json['canFullscreen'] as bool? ?? false,
    settings: (json['settings'] as List? ?? const [])
        .map((e) => LanCastSetting.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'position': position,
    'duration': duration,
    'playing': playing,
    'buffering': buffering,
    'volume': volume,
    'speed': speed,
    'isLive': isLive,
    'error': error,
    'mediaKey': mediaKey,
    'fullscreen': fullscreen,
    'canFullscreen': canFullscreen,
    'settings': settings.map((e) => e.toJson()).toList(),
  };
}

abstract interface class LanCastPlayback {
  LanCastStatus get status;
  Future<void> load(LanCastMedia media);
  Future<void> command(String action, double? value);
  Future<void> stop();
}

class LanCastDevice {
  const LanCastDevice({
    required this.id,
    required this.name,
    required this.uri,
  });
  final String id;
  final String name;
  final Uri uri;
}

Uri lanCastAddress(String input) {
  final value = input.trim();
  final uri = Uri.tryParse(value.contains('://') ? value : 'http://$value');
  if (uri == null ||
      uri.scheme != 'http' ||
      uri.host.isEmpty ||
      !uri.hasPort ||
      uri.port < 1 ||
      uri.port > 65535 ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw const LanCastException('请输入接收端显示的 IP 地址和端口');
  }
  final address = InternetAddress.tryParse(uri.host);
  if (address == null || !isLanCastAddress(address)) {
    throw const LanCastException('请输入局域网 IP 地址');
  }
  return uri.replace(path: '');
}

bool isLanCastAddress(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal) return true;
  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    return bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168);
  }
  return (bytes[0] & 0xfe) == 0xfc;
}

Future<Map<String, dynamic>> readLanCastJson(Stream<List<int>> stream) async {
  final bytes = <int>[];
  await for (final chunk in stream.timeout(const Duration(seconds: 5))) {
    if (bytes.length + chunk.length > lanCastBodyLimit) {
      throw const LanCastException('请求内容过大', 413);
    }
    bytes.addAll(chunk);
  }
  final value = jsonDecode(utf8.decode(bytes));
  if (value is! Map<String, dynamic>) {
    throw const LanCastException('无效的请求内容');
  }
  return value;
}
