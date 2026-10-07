import 'dart:async';

import 'package:PiliPlus/models/common/super_resolution_type.dart';
import 'package:PiliPlus/models/common/video/audio_quality.dart';
import 'package:PiliPlus/models/common/video/cdn_type.dart';
import 'package:PiliPlus/models/common/video/video_decode_type.dart';
import 'package:PiliPlus/models/common/video/video_quality.dart';
import 'package:PiliPlus/pages/live_room/controller.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_repeat.dart';
import 'package:PiliPlus/plugin/pl_player/models/video_fit_type.dart';
import 'package:PiliPlus/plugin/pl_player/utils/danmaku_options.dart';
import 'package:PiliPlus/services/lan_cast/protocol.dart';
import 'package:PiliPlus/services/lan_cast/settings.dart';
import 'package:PiliPlus/services/shutdown_timer_service.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:get/get.dart';

typedef _Entry = (LanCastSetting, FutureOr<void> Function(Object));

/// Adapts the receiving page's existing controls. Sender preferences are never
/// used for the snapshot and are never changed when displaying it.
class LanCastPageSettings {
  LanCastPageSettings(this.player);
  final PlPlayerController player;

  Map<String, _Entry> _entries() {
    final entries = <String, _Entry>{};
    var group = '播放设置';
    void add(
      String key,
      String label,
      Object value,
      FutureOr<void> Function(Object) apply, {
      double? min,
      double? max,
      int? divisions,
      Map<String, String> options = const {},
    }) {
      entries[key] = (
        LanCastSetting(
          key: key,
          label: label,
          group: group,
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          options: options,
        ),
        apply,
      );
    }

    void toggle(
      String key,
      String label,
      bool value,
      void Function(bool) apply,
    ) => add(key, label, value, (v) => apply(v as bool));
    void number(
      String key,
      String label,
      num value,
      double min,
      double max,
      int divisions,
      FutureOr<void> Function(num) apply,
    ) => add(
      key,
      label,
      value,
      (v) => apply(v as num),
      min: min,
      max: max,
      divisions: divisions,
    );
    void choice(
      String key,
      String label,
      String value,
      Map<String, String> options,
      FutureOr<void> Function(String) apply,
    ) {
      if (options.isNotEmpty) {
        add(key, label, value, (v) => apply(v as String), options: options);
      }
    }

    final tag = player.playbackPageTag;
    final video =
        !player.isLive &&
            tag != null &&
            Get.isRegistered<VideoDetailController>(tag: tag)
        ? Get.find<VideoDetailController>(tag: tag)
        : null;
    final live =
        player.isLive &&
            tag != null &&
            Get.isRegistered<LiveRoomController>(tag: tag)
        ? Get.find<LiveRoomController>(tag: tag)
        : null;

    choice('fit', '画面比例', player.videoFit.value.name, {
      for (final e in VideoFitType.values) e.name: e.desc,
    }, (v) => player.toggleVideoFit(VideoFitType.values.byName(v)));
    toggle('flipX', '左右翻转', player.flipX.value, (v) => player.flipX.value = v);
    toggle('flipY', '上下翻转', player.flipY.value, (v) => player.flipY.value = v);
    choice('shader', '超分辨率', player.superResolutionType.value.name, {
      for (final e in SuperResolutionType.values) e.name: e.label,
    }, (v) => player.setShader(SuperResolutionType.values.byName(v)));
    toggle('background', '后台播放', player.continuePlayInBackground.value, (v) {
      if (v != player.continuePlayInBackground.value) {
        player.setContinuePlayInBackground();
      }
    });
    add('audioOnly', '听视频', player.onlyPlayAudio.value, (v) async {
      final value = v as bool;
      if (value == player.onlyPlayAudio.value) return;
      player.onlyPlayAudio.value = value;
      if (live != null) {
        await live.queryLiveUrl();
      } else if (video != null) {
        final native = player.videoPlayerController!;
        if (!value && native.state.tracks.video.length <= 2) {
          await video.playerInit();
        } else {
          native.setProperty('file-local-options/vid', value ? 'no' : 'auto');
        }
      }
    });
    number(
      'volume',
      '播放音量 (%)',
      player.volume.value * 100,
      0,
      100,
      100,
      (v) => player.setVolume(v.toDouble() / 100),
    );
    final native = player.videoPlayerController;
    if (native != null) {
      number(
        'gain',
        '播放器音量增益 (%)',
        double.tryParse(native.getProperty('volume')) ?? 100,
        0,
        300,
        300,
        (v) => native.setVolume(v.toDouble()),
      );
    }
    if (!player.isLive) {
      number(
        'speed',
        '播放速度',
        player.playbackSpeed,
        0.25,
        4,
        15,
        (v) => player.setPlaybackSpeed(v.toDouble()),
      );
      choice(
        'repeat',
        '播放顺序',
        (player.receivingCastRepeat ?? PlayRepeat.pause).name,
        {
          for (final e in [PlayRepeat.pause, PlayRepeat.singleCycle])
            e.name: e.label,
        },
        (v) => player.setPlayRepeat(PlayRepeat.values.byName(v)),
      );
    }
    if (video != null || live != null) {
      add('reload', '重载视频', false, (_) async {
        if (video != null) await video.queryVideoUrl(fromReset: true);
        if (live != null) await live.queryLiveUrl();
      });
    }

    if (video != null) {
      final dash = video.data.dash;
      final qualities = dash?.video?.map((e) => e.id).toSet() ?? <int>{};
      choice(
        'quality',
        '选择画质',
        '${video.currentVideoQa.value?.code}',
        {
          for (final e in video.data.supportFormats ?? [])
            if (qualities.contains(e.quality))
              '${e.quality}': e.newDesc ?? '${e.quality}',
        },
        (v) async {
          final qa = VideoQuality.fromCode(int.parse(v));
          video.currentVideoQa.value = qa;
          player.cacheVideoQa = qa.code;
          await video.updatePlayer();
        },
      );
      choice(
        'audioQuality',
        '选择音质',
        '${video.currentAudioQa?.code}',
        {
          for (final e in dash?.audio ?? []) '${e.id}': e.quality,
        },
        (v) async {
          final qa = AudioQuality.fromCode(int.parse(v));
          video.currentAudioQa = qa;
          player.cacheAudioQa = qa.code;
          await video.updatePlayer();
        },
      );
      if (dash != null) {
        final codecs = <VideoDecodeFormatType>{
          for (final format in VideoDecodeFormatType.values)
            if (dash.video?.any(
                  (e) =>
                      e.id == video.currentVideoQa.value?.code &&
                      e.codecs != null &&
                      format.codes.any(e.codecs!.startsWith),
                ) ==
                true)
              format,
        };
        choice(
          'codec',
          '解码格式',
          video.currentDecodeFormats.name,
          {for (final e in codecs) e.name: e.description},
          (v) async {
            video.currentDecodeFormats = VideoDecodeFormatType.values.byName(v);
            await video.updatePlayer();
          },
        );
      }
      choice(
        'cdn',
        'CDN 设置',
        VideoUtils.cdnService.name,
        {for (final e in CDNService.values) e.name: e.desc},
        (v) async {
          VideoUtils.cdnService = CDNService.values.byName(v);
          await video.queryVideoUrl(fromReset: true);
        },
      );
      if (video.languages.value?.isNotEmpty == true) {
        choice(
          'translation',
          '翻译',
          video.currLang.value ?? '',
          {
            '': '关闭翻译',
            for (final e in video.languages.value!)
              if (e.lang != null) e.lang!: e.title ?? e.lang!,
          },
          (v) async {
            video.currLang.value = v;
            await video.queryVideoUrl(fromReset: true);
          },
        );
      }
    }
    if (live != null) {
      choice('quality', '选择画质', '${live.currentQn}', {
        for (final e in live.acceptQnList) '${e.code}': e.desc,
      }, (v) async => await live.changeQn(int.parse(v)));
      final routes = <String, String>{};
      for (var s = 0; s < live.stream.length; s++) {
        final stream = live.stream[s];
        for (var f = 0; f < stream.format.length; f++) {
          final format = stream.format[f];
          for (var c = 0; c < format.codec.length; c++) {
            final codec = format.codec[c];
            for (var u = 0; u < codec.urlInfo.length; u++) {
              routes['$s:$f:$c:$u'] =
                  '${stream.protocolName} / ${format.formatName} / ${codec.codecName} / 线路 ${u + 1}';
            }
          }
        }
      }
      choice(
        'liveRoute',
        '切换路线',
        '${live.streamIndex}:${live.formatIndex}:${live.codecIndex}:${live.liveUrlIndex}',
        routes,
        (v) async {
          final ids = v.split(':').map(int.parse).toList();
          await live.initLiveUrl(
            streamIndex: ids[0],
            formatIndex: ids[1],
            codecIndex: ids[2],
            liveUrlIndex: ids[3],
          );
        },
      );
    }

    group = '弹幕设置';
    toggle(
      'danmaku',
      '显示弹幕',
      player.enableShowDanmakuAdaptive.value,
      player.setDanmakuEnabled,
    );
    number(
      'dmOpacity',
      '不透明度 (%)',
      player.danmakuOpacity.value * 100,
      0,
      100,
      100,
      (v) => player.danmakuOpacity.value = v / 100,
    );
    number(
      'dmScale',
      '字体大小 (%)',
      DanmakuOptions.danmakuFontScale * 100,
      50,
      600,
      550,
      (v) => DanmakuOptions.danmakuFontScale = v / 100,
    );
    number(
      'dmScaleFS',
      '全屏字体大小 (%)',
      DanmakuOptions.danmakuFontScaleFS * 100,
      50,
      600,
      550,
      (v) => DanmakuOptions.danmakuFontScaleFS = v / 100,
    );
    number(
      'dmWeight',
      '字体粗细',
      DanmakuOptions.danmakuFontWeight + 1,
      1,
      9,
      8,
      (v) => DanmakuOptions.danmakuFontWeight = v.toInt() - 1,
    );
    number(
      'dmStroke',
      '描边粗细',
      DanmakuOptions.danmakuStrokeWidth,
      0,
      5,
      10,
      (v) => DanmakuOptions.danmakuStrokeWidth = v.toDouble(),
    );
    number(
      'dmArea',
      '显示区域 (%)',
      DanmakuOptions.danmakuShowArea * 100,
      10,
      100,
      9,
      (v) => DanmakuOptions.danmakuShowArea = v / 100,
    );
    number(
      'dmDuration',
      '滚动弹幕时长 (秒)',
      DanmakuOptions.danmakuDuration,
      1,
      50,
      49,
      (v) => DanmakuOptions.danmakuDuration = v.toDouble(),
    );
    number(
      'dmStaticDuration',
      '静态弹幕时长 (秒)',
      DanmakuOptions.danmakuStaticDuration,
      1,
      50,
      49,
      (v) => DanmakuOptions.danmakuStaticDuration = v.toDouble(),
    );
    number(
      'dmLineHeight',
      '弹幕行高',
      DanmakuOptions.danmakuLineHeight,
      1,
      3,
      20,
      (v) => DanmakuOptions.danmakuLineHeight = v.toDouble(),
    );
    if (!player.isLive) {
      number(
        'dmFilter',
        '智能云屏蔽',
        DanmakuOptions.danmakuWeight,
        0,
        11,
        11,
        (v) => DanmakuOptions.danmakuWeight = v.toInt(),
      );
    }
    for (final e in {2: '滚动', 5: '顶部', 4: '底部', 6: '彩色', 7: '高级'}.entries) {
      toggle(
        'dmBlock${e.key}',
        '屏蔽${e.value}弹幕',
        DanmakuOptions.blockTypes.contains(e.key),
        (v) {
          if (v) {
            DanmakuOptions.blockTypes.add(e.key);
          } else {
            DanmakuOptions.blockTypes.remove(e.key);
          }
          DanmakuOptions.blockColorful = DanmakuOptions.blockTypes.contains(6);
        },
      );
    }
    toggle(
      'dmMassive',
      '海量弹幕',
      DanmakuOptions.danmakuMassiveMode,
      (v) => DanmakuOptions.danmakuMassiveMode = v,
    );
    toggle(
      'dmStaticScroll',
      '固定转滚动',
      DanmakuOptions.danmakuStatic2Scroll,
      (v) => DanmakuOptions.danmakuStatic2Scroll = v,
    );
    toggle(
      'dmFixed',
      '滚动弹幕固定速度',
      DanmakuOptions.danmakuFixedV,
      (v) => DanmakuOptions.danmakuFixedV = v,
    );

    if (!player.isLive) {
      group = '字幕设置';
      if (video != null) {
        choice('subtitle', '字幕', '${video.vttSubtitlesIndex.value}', {
          '0': '关闭字幕',
          for (var i = 0; i < video.subtitles.length; i++)
            '${i + 1}': video.subtitles[i].lanDoc ?? video.subtitles[i].lan,
        }, (v) => video.setSubtitle(int.parse(v)));
      }
      number(
        'subScale',
        '字体大小 (%)',
        player.subtitleFontScale * 100,
        50,
        600,
        550,
        (v) => player.subtitleFontScale = v / 100,
      );
      number(
        'subScaleFS',
        '全屏字体大小 (%)',
        player.subtitleFontScaleFS * 100,
        50,
        600,
        550,
        (v) => player.subtitleFontScaleFS = v / 100,
      );
      number(
        'subWeight',
        '字体粗细',
        player.subtitleFontWeight + 1,
        1,
        9,
        8,
        (v) => player.subtitleFontWeight = v.toInt() - 1,
      );
      number(
        'subStroke',
        '描边粗细',
        player.subtitleStrokeWidth,
        0,
        5,
        10,
        (v) => player.subtitleStrokeWidth = v.toDouble(),
      );
      number(
        'subPaddingH',
        '左右边距',
        player.subtitlePaddingH,
        0,
        100,
        100,
        (v) => player.subtitlePaddingH = v.toInt(),
      );
      number(
        'subPaddingB',
        '底部边距',
        player.subtitlePaddingB,
        0,
        200,
        200,
        (v) => player.subtitlePaddingB = v.toInt(),
      );
      number(
        'subOpacity',
        '背景不透明度 (%)',
        player.subtitleBgOpacity * 100,
        0,
        100,
        100,
        (v) => player.subtitleBgOpacity = v / 100,
      );
    }

    group = '定时关闭';
    final timer = shutdownTimerService;
    number(
      'timerMinutes',
      '定时关闭 (分钟，0 为取消)',
      timer.remainingMinutes,
      0,
      1499,
      1499,
      (v) => timer.scheduleCast(v.toInt()),
    );
    if (!player.isLive) {
      toggle(
        'timerWait',
        '额外等待视频播放完毕',
        timer.waitUntilCompleted,
        (v) => timer.waitUntilCompleted = v,
      );
    }
    toggle(
      'timerExit',
      '倒计时结束退出接收端 APP',
      timer.exitOnTimeout,
      (v) => timer.exitOnTimeout = v,
    );
    if (native != null) {
      final state = native.state;
      for (final item in {
        'resolution': ('分辨率', '${state.width} × ${state.height}'),
        'videoParams': ('视频参数', '${state.videoParams}'),
        'audioParams': ('音频参数', '${state.audioParams}'),
        'hwdec': ('硬件解码', native.getProperty('hwdec-current')),
      }.entries) {
        entries[item.key] = (
          LanCastSetting(
            key: item.key,
            label: item.value.$1,
            group: '播放信息',
            value: item.value.$2,
            readOnly: true,
          ),
          (_) {},
        );
      }
    }
    return entries;
  }

  List<LanCastSetting> get snapshot =>
      _entries().values.map((e) => e.$1).toList();

  Future<void> apply(String key, Object value) async {
    final entry = _entries()[key];
    if (entry == null) throw const LanCastException('接收端不支持此设置', 422);
    await entry.$2(entry.$1.validate(value));
    if (entry.$1.group == '弹幕设置') {
      player.danmakuController?.updateOption(
        DanmakuOptions.get(
          notFullscreen: !player.isFullScreen.value,
          speed: player.playbackSpeed,
        ),
      );
      if (!player.tempPlayerConf) {
        await DanmakuOptions.save(player.danmakuOpacity.value);
      }
    } else if (entry.$1.group == '字幕设置') {
      player.updateSubtitleStyle();
      if (!player.tempPlayerConf) player.putSubtitleSettings();
    }
  }
}
