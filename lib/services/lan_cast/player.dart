import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/http/constants.dart';
import 'package:PiliPlus/services/lan_cast/protocol.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class LanCastPlayer extends ChangeNotifier implements LanCastPlayback {
  Player? _player;
  VideoController? video;
  LanCastMedia? _media;
  String? _error;
  Timer? _timer;
  StreamSubscription<String>? _errors;
  bool _loading = false;
  AudioSession? _audioSession;
  StreamSubscription<AudioInterruptionEvent>? _interruptions;
  StreamSubscription<void>? _noisy;

  Future<void> initialize() async {
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      _audioSession = await AudioSession.instance;
      _interruptions = _audioSession!.interruptionEventStream.listen((event) {
        if (event.begin) unawaited(_pauseForInterruption());
      });
      _noisy = _audioSession!.becomingNoisyEventStream.listen((_) {
        unawaited(_pauseForInterruption());
      });
    }
    final player = _player = await Player.create();
    video = await VideoController.create(player);
    player.setMediaHeader(userAgent: BrowserUa.pc, referer: HttpString.baseUrl);
    _errors = player.stream.error.listen((_) {
      _error = '视频加载失败，请在发送端重新推送';
      notifyListeners();
    });
    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => notifyListeners(),
    );
  }

  @override
  LanCastStatus get status {
    final state = _player?.state;
    return LanCastStatus(
      title: _media?.title ?? '',
      position: state?.position.inMilliseconds ?? 0,
      duration: state?.duration.inMilliseconds ?? 0,
      playing: state?.playing ?? false,
      buffering: _loading || (state?.buffering ?? false),
      volume: (state?.volume ?? 100).clamp(0, 100),
      speed: state?.rate ?? 1,
      isLive: _media?.isLive ?? false,
      error: _error,
    );
  }

  @override
  Future<void> load(LanCastMedia media) async {
    final player = _player!;
    _error = null;
    _loading = true;
    _media = media;
    notifyListeners();
    final loaded = Completer<void>();
    final sizeSubscription = player.stream.size.listen((size) {
      if (size.$1 > 0 && size.$2 > 0 && !loaded.isCompleted) loaded.complete();
    });
    final errorSubscription = player.stream.error.listen((_) {
      if (!loaded.isCompleted) {
        loaded.completeError(const LanCastException('视频加载失败，请重新推送'));
      }
    });
    // Install an error handler immediately, including while open() is pending.
    final ready = loaded.future.timeout(const Duration(seconds: 10));
    unawaited(ready.catchError((Object _) {}));
    try {
      await player.open(
        Media(
          media.playableUrl,
          start: media.isLive ? null : Duration(milliseconds: media.position),
        ),
        play: false,
      );
      await player.setRate(media.isLive ? 1 : media.speed);
      await _activateAudio();
      await player.play();
      await ready;
      if (_error != null) throw LanCastException(_error!);
    } catch (_) {
      _error = '视频加载失败，请在发送端重新推送';
      await player.stop();
      rethrow;
    } finally {
      await sizeSubscription.cancel();
      await errorSubscription.cancel();
      _loading = false;
      notifyListeners();
    }
  }

  @override
  Future<void> command(String action, double? value) async {
    final player = _player!;
    switch (action) {
      case 'play':
        await _activateAudio();
        await player.play();
      case 'pause':
        await player.pause();
      case 'seek':
        if (_media?.isLive == false) {
          final duration = player.state.duration.inMilliseconds;
          await player.seek(
            Duration(
              milliseconds: value!.round().clamp(
                0,
                duration > 0 ? duration : value.round(),
              ),
            ),
          );
        }
      case 'volume':
        await player.setVolume(value!.clamp(0, 100));
      case 'speed':
        if (_media?.isLive == false) {
          await player.setRate(value!.clamp(0.25, 4));
        }
    }
    notifyListeners();
  }

  Future<void> _activateAudio() async {
    if (_audioSession != null && !await _audioSession!.setActive(true)) {
      throw const LanCastException('接收端暂时无法播放音频，请稍后重试');
    }
  }

  Future<void> _pauseForInterruption() async {
    try {
      await _player?.pause();
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    await _player?.stop();
    await _audioSession?.setActive(false);
    _media = null;
    _error = null;
    notifyListeners();
  }

  Future<void> close() async {
    _timer?.cancel();
    await _errors?.cancel();
    await _interruptions?.cancel();
    await _noisy?.cancel();
    await _player?.dispose();
    super.dispose();
  }
}
