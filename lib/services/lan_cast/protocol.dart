import 'dart:convert';
import 'dart:io';
import 'dart:math';

const lanCastServiceType = '_piliplus._tcp';
const lanCastProtocolVersion = 1;
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

String _mediaUrl(Object? value) {
  final text = lanCastText(value, maxLength: 16000);
  final uri = Uri.tryParse(text);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      text.contains(RegExp(r'[\x00-\x20]'))) {
    throw const LanCastException('仅支持 HTTP 或 HTTPS 在线视频');
  }
  return text;
}

class LanCastMedia {
  const LanCastMedia({
    required this.title,
    required this.videoUrl,
    this.audioUrl,
    this.position = 0,
    this.speed = 1,
    this.isLive = false,
  });

  final String title;
  final String videoUrl;
  final String? audioUrl;
  final int position;
  final double speed;
  final bool isLive;

  factory LanCastMedia.fromJson(Map<String, dynamic> json) {
    if (json['isLive'] is! bool) {
      throw const LanCastException('无效的播放类型');
    }
    return LanCastMedia(
      title: lanCastText(json['title']),
      videoUrl: _mediaUrl(json['videoUrl']),
      audioUrl: json['audioUrl'] == null ? null : _mediaUrl(json['audioUrl']),
      position: lanCastNumber(json['position'], 0, 2592000000).round(),
      speed: lanCastNumber(json['speed'], 0.25, 4),
      isLive: json['isLive'] as bool,
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'videoUrl': videoUrl,
    'audioUrl': audioUrl,
    'position': position,
    'speed': speed,
    'isLive': isLive,
  };

  // Length prefixes keep signed URLs (including commas/semicolons) intact.
  String get playableUrl => audioUrl == null
      ? videoUrl
      : 'edl://!no_chapters;'
            '%${utf8.encode(videoUrl).length}%$videoUrl;'
            '!new_stream;!no_chapters;'
            '%${utf8.encode(audioUrl!).length}%$audioUrl';
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
