import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/services/lan_cast/session.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class LanCastFullscreenButton extends StatelessWidget {
  const LanCastFullscreenButton({
    super.key,
    required this.player,
    this.width = 34,
    this.height = 34,
    this.style,
    this.session,
  });
  final PlPlayerController player;
  final double width, height;
  final ButtonStyle? style;
  final LanCastSession? session;

  @override
  Widget build(BuildContext context) {
    final session = this.session ?? LanCastSession.instance;
    return Obx(() {
      if (player.castDevice.value.isEmpty) return const SizedBox.shrink();
      return ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final state = session.status;
          return SizedBox(
            width: width,
            height: height,
            child: IconButton(
              style: style,
              tooltip: !state.canFullscreen
                  ? '接收端需更新以支持远程全屏'
                  : state.fullscreen
                  ? '退出接收端全屏'
                  : '接收端全屏',
              onPressed:
                  session.connected &&
                      session.online &&
                      !session.busy &&
                      state.canFullscreen
                  ? () =>
                        session.command('fullscreen', state.fullscreen ? 0 : 1)
                  : null,
              icon: Icon(
                state.fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                size: 20,
                color: Colors.white,
              ),
            ),
          );
        },
      );
    });
  }
}
