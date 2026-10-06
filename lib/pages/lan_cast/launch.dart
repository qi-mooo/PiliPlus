import 'package:PiliPlus/pages/lan_cast/view.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:PiliPlus/services/lan_cast/protocol.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

void showLanCast(PlPlayerController player, String title) {
  if (player.videoPlayerController == null ||
      player.dataSource is! NetworkSource) {
    SmartDialog.showToast('请等待在线视频开始播放后再推送');
    return;
  }
  // A plain route leaves the video's GetPageRoute observer untouched: merely
  // browsing devices must not pause playback or resume it when the remote closes.
  Navigator.of(Get.context!).push(
    MaterialPageRoute<void>(
      builder: (_) => LanCastPage(
        media: () {
          if (player.videoPlayerController == null ||
              player.dataSource is! NetworkSource) {
            throw const LanCastException('当前视频已关闭，请重新打开视频后推送');
          }
          return LanCastMedia.fromJson(
            LanCastMedia(
              title: title.isEmpty ? 'PiliPlus 视频' : title,
              videoUrl: player.dataSource.videoSource,
              audioUrl: player.dataSource.audioSource?.isEmpty == true
                  ? null
                  : player.dataSource.audioSource,
              position: player.positionInMilliseconds,
              speed: player.playbackSpeed.clamp(0.25, 4),
              isLive: player.isLive,
            ).toJson(),
          );
        },
        onPushed: () => player.pause(),
      ),
    ),
  );
}
