import 'dart:async';
import 'dart:io' show exit, Platform;
import 'dart:math' as math;

import 'package:PiliPlus/models/common/player_shortcut.dart';
import 'package:PiliPlus/pages/common/common_intro_controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:flutter/services.dart'
    show
        HardwareKeyboard,
        KeyDownEvent,
        KeyEvent,
        KeyUpEvent,
        LogicalKeyboardKey;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

class PlayerFocus extends StatelessWidget {
  const PlayerFocus({
    super.key,
    required this.child,
    required this.plPlayerController,
    this.introController,
    required this.onSendDanmaku,
    this.canPlay,
    this.onSkipSegment,
    this.onRefresh,
  });

  final Widget child;
  final PlPlayerController plPlayerController;
  final CommonIntroController? introController;
  final VoidCallback onSendDanmaku;
  final ValueGetter<bool>? canPlay;
  final ValueGetter<bool>? onSkipSegment;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        final handled = _handleKey(context, event);
        if (handled ||
            PlayerShortcutConfig.shouldHandle(
              event.logicalKey,
              includeGlobal: false,
            )) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }

  bool get isFullScreen => plPlayerController.isFullScreen.value;
  bool get hasPlayer => plPlayerController.videoPlayerController != null;

  void _setVolume({required bool isIncrease}) {
    final volume = isIncrease
        ? math.min(
            plPlayerController.maxVolume,
            plPlayerController.volume.value + 0.1,
          )
        : math.max(0.0, plPlayerController.volume.value - 0.1);
    plPlayerController.setVolume(volume);
  }

  void _updateVolume(KeyEvent event, {required bool isIncrease}) {
    if (event is KeyDownEvent) {
      if (hasPlayer) {
        _setVolume(isIncrease: isIncrease);
        plPlayerController
          ..longPressTimer?.cancel()
          ..longPressTimer = Timer.periodic(
            const Duration(milliseconds: 150),
            (_) => _setVolume(isIncrease: isIncrease),
          );
      }
    } else if (event is KeyUpEvent) {
      plPlayerController.cancelLongPressTimer();
    }
  }

  void _setAdjacentSpeed({required bool isIncrease}) {
    final speeds = plPlayerController.speedList.toSet().toList()..sort();
    final current = plPlayerController.playbackSpeed;
    final speed = isIncrease
        ? speeds.firstWhere((item) => item > current, orElse: () => speeds.last)
        : speeds.lastWhere(
            (item) => item < current,
            orElse: () => speeds.first,
          );
    if (speed != current) {
      plPlayerController.setPlaybackSpeed(speed);
      SmartDialog.showToast('${speed}x播放');
    }
  }

  bool _handleKey(BuildContext context, KeyEvent event) {
    final key = event.logicalKey;

    if (HardwareKeyboard.instance.isMetaPressed) {
      if (key == LogicalKeyboardKey.keyQ ||
          key == LogicalKeyboardKey.keyR ||
          key == LogicalKeyboardKey.keyW) {
        if (key == LogicalKeyboardKey.keyQ && Platform.isMacOS) {
          exit(0);
        }
        return true;
      }
    }

    final action = PlayerShortcutConfig.actionFor(event, includeGlobal: false);
    if (action == null) {
      return false;
    }
    if (event is KeyDownEvent &&
        action != PlayerShortcutAction.like &&
        action != PlayerShortcutAction.triple &&
        (introController?.isTripling ?? false)) {
      introController!.onCancelTriple();
    }

    switch (action) {
      case PlayerShortcutAction.like:
      case PlayerShortcutAction.triple:
        if (event is KeyDownEvent) {
          if (plPlayerController.isLive) {
            onRefresh?.call();
          } else {
            introController?.onStartTriple();
          }
        } else if (event is KeyUpEvent && !plPlayerController.isLive) {
          introController?.onCancelTriple(action == PlayerShortcutAction.like);
        }
        return true;

      case PlayerShortcutAction.volumeUp:
      case PlayerShortcutAction.volumeDown:
        _updateVolume(
          event,
          isIncrease: action == PlayerShortcutAction.volumeUp,
        );
        return true;

      case PlayerShortcutAction.seekForward:
        if (plPlayerController.isLive) {
          return true;
        }
        if (event is KeyDownEvent) {
          if (hasPlayer && !plPlayerController.longPressStatus.value) {
            plPlayerController
              ..longPressTimer?.cancel()
              ..longPressTimer = Timer(
                const Duration(milliseconds: 200),
                () => plPlayerController
                  ..cancelLongPressTimer()
                  ..setLongPressStatus(true),
              );
          }
        } else if (event is KeyUpEvent) {
          plPlayerController.cancelLongPressTimer();
          if (hasPlayer) {
            if (plPlayerController.longPressStatus.value) {
              plPlayerController.setLongPressStatus(false);
            } else {
              plPlayerController.onForward(
                plPlayerController.fastForBackwardDuration,
              );
            }
          }
        }
        return true;

      case PlayerShortcutAction.seekBackward:
        if (!plPlayerController.isLive && event is KeyDownEvent && hasPlayer) {
          plPlayerController.onBackward(
            plPlayerController.fastForBackwardDuration,
          );
        }
        return true;

      case PlayerShortcutAction.normalSpeed:
      case PlayerShortcutAction.doubleSpeed:
        if (!plPlayerController.isLive && event is KeyDownEvent && hasPlayer) {
          final speed = action == PlayerShortcutAction.normalSpeed ? 1.0 : 2.0;
          if (speed != plPlayerController.playbackSpeed) {
            plPlayerController.setPlaybackSpeed(speed);
          }
          SmartDialog.showToast('${speed}x播放');
        }
        return true;

      case PlayerShortcutAction.speedDown:
      case PlayerShortcutAction.speedUp:
        if (!plPlayerController.isLive && event is KeyDownEvent && hasPlayer) {
          _setAdjacentSpeed(isIncrease: action == PlayerShortcutAction.speedUp);
        }
        return true;

      case PlayerShortcutAction.toggleControls:
        if (event is KeyDownEvent) {
          plPlayerController.controls = !plPlayerController.showControls.value;
        }
        return true;
      case PlayerShortcutAction.playPause:
        if (event is KeyDownEvent &&
            (plPlayerController.isLive || canPlay?.call() == true) &&
            hasPlayer) {
          plPlayerController.onDoubleTapCenter();
        }
        return true;

      case PlayerShortcutAction.fullscreen:
        if (event is KeyDownEvent) {
          final isFullScreen = this.isFullScreen;
          if (isFullScreen && plPlayerController.controlsLock.value) {
            plPlayerController
              ..controlsLock.value = false
              ..showControls.value = false;
          }
          plPlayerController.triggerFullScreen(
            status: !isFullScreen,
            inAppFullScreen: HardwareKeyboard.instance.isShiftPressed,
          );
        }
        return true;

      case PlayerShortcutAction.danmaku:
        if (event is KeyDownEvent) {
          plPlayerController.setDanmakuEnabled(
            !plPlayerController.danmakuEnabled,
          );
        }
        return true;

      case PlayerShortcutAction.desktopPip:
        if (event is KeyDownEvent &&
            PlatformUtils.isDesktop &&
            hasPlayer &&
            !isFullScreen) {
          plPlayerController
            ..toggleDesktopPip()
            ..controlsLock.value = false
            ..showControls.value = false;
        }
        return true;

      case PlayerShortcutAction.mute:
        if (event is KeyDownEvent && hasPlayer) {
          plPlayerController.toggleMute();
        }
        return true;

      case PlayerShortcutAction.screenshot:
        if (event is KeyDownEvent && hasPlayer && isFullScreen) {
          plPlayerController.takeScreenshot();
        }
        return true;

      case PlayerShortcutAction.lockControl:
        if (event is KeyDownEvent &&
            (isFullScreen || plPlayerController.isDesktopPip)) {
          plPlayerController.onLockControl(
            !plPlayerController.controlsLock.value,
          );
        }
        return true;

      case PlayerShortcutAction.sendDanmaku:
        if (event is KeyDownEvent) {
          if (onSkipSegment?.call() ?? false) {
            return true;
          }
          onSendDanmaku();
        }
        return true;

      case PlayerShortcutAction.coin:
        if (!plPlayerController.isLive && event is KeyDownEvent) {
          introController?.actionCoinVideo();
        }
        return true;

      case PlayerShortcutAction.favorite:
        if (!plPlayerController.isLive && event is KeyDownEvent) {
          introController?.actionFavVideo(isQuick: true);
        }
        return true;

      case PlayerShortcutAction.viewLater:
        if (!plPlayerController.isLive && event is KeyDownEvent) {
          introController?.viewLater();
        }
        return true;

      case PlayerShortcutAction.follow:
        if (!plPlayerController.isLive && event is KeyDownEvent) {
          if (introController case final UgcIntroController ugcCtr) {
            ugcCtr.actionRelationMod(context);
          }
        }
        return true;

      case PlayerShortcutAction.previousEpisode:
        if (!plPlayerController.isLive && event is KeyDownEvent) {
          if (introController case final introController?) {
            if (!introController.prevPlay()) {
              SmartDialog.showToast('已经是第一集了');
            }
          }
        }
        return true;

      case PlayerShortcutAction.nextEpisode:
        if (!plPlayerController.isLive && event is KeyDownEvent) {
          if (introController case final introController?) {
            if (!introController.nextPlay()) {
              SmartDialog.showToast('已经是最后一集了');
            }
          }
        }
        return true;

      case PlayerShortcutAction.back:
      case PlayerShortcutAction.search:
      case PlayerShortcutAction.home:
      case PlayerShortcutAction.dynamics:
      case PlayerShortcutAction.mine:
      case PlayerShortcutAction.homeRefresh:
      case PlayerShortcutAction.currentTopOrRefresh:
        return false;
    }
  }
}
