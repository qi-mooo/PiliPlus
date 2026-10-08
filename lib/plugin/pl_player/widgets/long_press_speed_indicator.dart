import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class LongPressSpeedIndicator extends StatelessWidget {
  const LongPressSpeedIndicator({
    super.key,
    required this.player,
    required this.isFullScreen,
    this.autoHideWithControls = false,
  });

  final PlPlayerController player;
  final bool isFullScreen;
  final bool autoHideWithControls;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: Padding(
      padding: EdgeInsets.fromLTRB(12, isFullScreen ? 48 : 24, 12, 0),
      child: Obx(() {
        final pressed = player.longPressStatus.value;
        final locked = player.longPressSpeedLocked.value;
        final progress = player.longPressLockProgress.value;
        final visible =
            (pressed ||
                (locked &&
                    (!autoHideWithControls || player.showControls.value))) &&
            !player.controlsLock.value &&
            !player.isSeeking.value;
        final canUnlock = visible && locked && !pressed;
        final speed = player.activeLongPressSpeed;
        final speedText = speed == speed.truncateToDouble()
            ? speed.toInt().toString()
            : speed.toString();
        return IgnorePointer(
          ignoring: !canUnlock,
          child: AnimatedOpacity(
            curve: Curves.easeInOut,
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  button: canUnlock,
                  child: MouseRegion(
                    cursor: canUnlock
                        ? SystemMouseCursors.click
                        : MouseCursor.defer,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: canUnlock ? player.unlockLongPressSpeed : null,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 40),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: const BoxDecoration(
                          color: Color(0xAA000000),
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 6,
                          children: [
                            Icon(
                              locked
                                  ? Icons.lock_outline
                                  : Icons.fast_forward_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            Flexible(
                              child: Text(
                                '$speedText倍速${locked ? '已锁定' : '播放中'}'
                                '${canUnlock ? ' · 点击恢复' : ''}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (player.canSwipeLongPressSpeed)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Color(0x88000000),
                        borderRadius: BorderRadius.all(Radius.circular(24)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 6,
                          children: [
                            const Icon(
                              Icons.keyboard_double_arrow_down,
                              color: Colors.white,
                              size: 18,
                            ),
                            Flexible(
                              child: Text(
                                locked ? '下滑解除倍速' : '下滑锁定倍速',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            SizedBox.square(
                              dimension: 26,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  CircularProgressIndicator(
                                    value: progress,
                                    strokeWidth: 2,
                                    color: Colors.white,
                                    backgroundColor: Colors.white24,
                                  ),
                                  Icon(
                                    locked
                                        ? Icons.lock_outline
                                        : Icons.lock_open_outlined,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }),
    ),
  );
}
