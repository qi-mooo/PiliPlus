import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:flutter/gestures.dart';

class LongPressSpeedGestureRecognizer extends LongPressGestureRecognizer {
  LongPressSpeedGestureRecognizer(this.player)
    : super(
        duration: player.enableTapDm ? const Duration(milliseconds: 300) : null,
      ) {
    onLongPressStart = (_) {
      _pressed = true;
      _sourceGeneration = player.sourceGeneration;
      player.setLongPressStatus(true);
    };
    onLongPressMoveUpdate = (details) {
      if (_sourceGeneration == player.sourceGeneration) {
        player.updateLongPressOffset(details.localOffsetFromOrigin);
      }
    };
    onLongPressEnd = (_) => _endPress();
    onLongPressCancel = _endPress;
  }

  final PlPlayerController player;
  bool _pressed = false;
  int? _sourceGeneration;

  void _endPress() {
    if (!_pressed) return;
    _pressed = false;
    if (_sourceGeneration == player.sourceGeneration) {
      player.setLongPressStatus(false);
    }
  }

  @override
  void handlePrimaryPointer(PointerEvent event) {
    // Flutter's onLongPressCancel only runs before the gesture is accepted.
    if (event is PointerCancelEvent) _endPress();
    super.handlePrimaryPointer(event);
  }

  @override
  void dispose() {
    _endPress();
    super.dispose();
  }
}
