import 'package:PiliPlus/pages/lan_cast/view.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

void showCastDevices(
  PlPlayerController player,
  String title, {
  Future<String> Function()? dlnaUrl,
}) {
  if (player.videoPlayerController == null && dlnaUrl == null) {
    SmartDialog.showToast('请等待在线视频开始播放后再推送');
    return;
  }
  player.mediaTitle = title;
  showModalBottomSheet<void>(
    context: Get.context!,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.65,
      child: LanCastPage(player: player, dlnaUrl: dlnaUrl),
    ),
  );
}
