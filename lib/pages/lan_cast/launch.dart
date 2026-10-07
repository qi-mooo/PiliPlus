import 'package:PiliPlus/pages/lan_cast/view.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:PiliPlus/services/lan_cast/session.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

Future<void> showCastDevices(
  PlPlayerController player,
  String title, {
  Future<String> Function()? dlnaUrl,
}) async {
  if (player.processing) {
    SmartDialog.showToast('请等待当前视频加载完成');
    return;
  }
  if (player.videoPlayerController == null && dlnaUrl == null) {
    SmartDialog.showToast('请等待在线视频开始播放后再推送');
    return;
  }
  player.mediaTitle = title;
  final session = LanCastSession.instance;
  if (session.connected &&
      !session.busy &&
      player.dataSource is NetworkSource &&
      (session.mediaKey != player.castMediaKey ||
          !player.isCasting ||
          session.error != null)) {
    try {
      await player.castToConnectedDevice();
      return;
    } catch (e) {
      SmartDialog.showToast('切换投屏失败：$e');
    }
  }
  if (!identical(PlPlayerController.instance, player)) return;
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
