import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// Keep renderer state alive for resuming local playback, without drawing or
/// intercepting touches while this page controls another device.
class PlaybackOverlay extends StatelessWidget {
  const PlaybackOverlay({super.key, required this.player, required this.child});
  final PlPlayerController player;
  final Widget child;

  @override
  Widget build(BuildContext context) => Obx(
    () => Visibility(
      visible: player.playbackOverlaysVisible,
      maintainState: true,
      child: child,
    ),
  );
}
