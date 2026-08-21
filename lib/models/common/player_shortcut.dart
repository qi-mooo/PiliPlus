import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum PlayerShortcutAction {
  like('like', '点赞/刷新直播', Icons.thumb_up_alt_outlined),
  triple('triple', '一键三连/刷新直播', Icons.recommend_outlined),
  volumeUp('volumeUp', '音量增加', Icons.volume_up_outlined),
  volumeDown('volumeDown', '音量降低', Icons.volume_down_outlined),
  seekForward('seekForward', '快进', Icons.forward_10_outlined),
  seekBackward('seekBackward', '快退', Icons.replay_10_outlined),
  normalSpeed('normalSpeed', '设置 1.0x 倍速', Icons.speed_outlined),
  doubleSpeed('doubleSpeed', '设置 2.0x 倍速', Icons.speed_outlined),
  playPause('playPause', '播放/暂停', Icons.play_arrow_outlined),
  fullscreen('fullscreen', '全屏/退出全屏', Icons.fullscreen_outlined),
  danmaku('danmaku', '显示/隐藏弹幕', Icons.subtitles_outlined),
  desktopPip('desktopPip', '桌面小窗', Icons.picture_in_picture_alt_outlined),
  mute('mute', '静音/取消静音', Icons.volume_off_outlined),
  screenshot('screenshot', '截图', Icons.photo_camera_outlined),
  lockControl('lockControl', '锁定/解锁控制栏', Icons.lock_outline),
  sendDanmaku('sendDanmaku', '发送弹幕/跳过片段', Icons.send_outlined),
  coin('coin', '投币', Icons.paid_outlined),
  favorite('favorite', '快速收藏', Icons.star_border_outlined),
  viewLater('viewLater', '稍后再看', Icons.watch_later_outlined),
  follow('follow', '关注/取消关注', Icons.person_add_alt_outlined),
  previousEpisode('previousEpisode', '上一集', Icons.skip_previous_outlined),
  nextEpisode('nextEpisode', '下一集', Icons.skip_next_outlined),
  speedDown('speedDown', '倍速降低', Icons.remove_circle_outline),
  speedUp('speedUp', '倍速提高', Icons.add_circle_outline),
  toggleControls('toggleControls', '显示/隐藏控制栏', Icons.touch_app_outlined),
  back('back', '返回', Icons.arrow_back_outlined),
  search('search', '搜索', Icons.search_outlined),
  home('home', '打开首页', Icons.home_outlined),
  dynamics('dynamics', '打开动态', Icons.motion_photos_on_outlined),
  mine('mine', '打开我的', Icons.person_outline),
  homeRefresh('homeRefresh', '刷新首页', Icons.refresh_outlined),
  currentTopOrRefresh(
    'currentTopOrRefresh',
    '当前页置顶/刷新',
    Icons.vertical_align_top_outlined,
  );

  const PlayerShortcutAction(this.id, this.title, this.icon);

  final String id;
  final String title;
  final IconData icon;

  List<PlayerShortcutBinding> get defaultBindings {
    return switch (this) {
      like => [PlayerShortcutBinding(LogicalKeyboardKey.keyQ.keyId)],
      triple => [PlayerShortcutBinding(LogicalKeyboardKey.keyR.keyId)],
      volumeUp => [PlayerShortcutBinding(LogicalKeyboardKey.arrowUp.keyId)],
      volumeDown => [PlayerShortcutBinding(LogicalKeyboardKey.arrowDown.keyId)],
      seekForward => [
        PlayerShortcutBinding(LogicalKeyboardKey.arrowRight.keyId),
      ],
      seekBackward => [
        PlayerShortcutBinding(LogicalKeyboardKey.arrowLeft.keyId),
      ],
      normalSpeed => [
        PlayerShortcutBinding(LogicalKeyboardKey.digit1.keyId, shift: true),
      ],
      doubleSpeed => [
        PlayerShortcutBinding(LogicalKeyboardKey.digit2.keyId, shift: true),
      ],
      playPause => [PlayerShortcutBinding(LogicalKeyboardKey.space.keyId)],
      fullscreen => [PlayerShortcutBinding(LogicalKeyboardKey.keyF.keyId)],
      danmaku => [PlayerShortcutBinding(LogicalKeyboardKey.keyD.keyId)],
      desktopPip => [PlayerShortcutBinding(LogicalKeyboardKey.keyP.keyId)],
      mute => [PlayerShortcutBinding(LogicalKeyboardKey.keyM.keyId)],
      screenshot => [PlayerShortcutBinding(LogicalKeyboardKey.keyS.keyId)],
      lockControl => [PlayerShortcutBinding(LogicalKeyboardKey.keyL.keyId)],
      sendDanmaku => [PlayerShortcutBinding(LogicalKeyboardKey.enter.keyId)],
      coin => [PlayerShortcutBinding(LogicalKeyboardKey.keyW.keyId)],
      favorite => [PlayerShortcutBinding(LogicalKeyboardKey.keyE.keyId)],
      viewLater => [
        PlayerShortcutBinding(LogicalKeyboardKey.keyT.keyId),
        PlayerShortcutBinding(LogicalKeyboardKey.keyV.keyId),
      ],
      follow => [PlayerShortcutBinding(LogicalKeyboardKey.keyG.keyId)],
      previousEpisode => [
        PlayerShortcutBinding(LogicalKeyboardKey.bracketLeft.keyId),
      ],
      nextEpisode => [
        PlayerShortcutBinding(LogicalKeyboardKey.bracketRight.keyId),
      ],
      speedDown => [PlayerShortcutBinding(LogicalKeyboardKey.minus.keyId)],
      speedUp => [PlayerShortcutBinding(LogicalKeyboardKey.equal.keyId)],
      toggleControls => [PlayerShortcutBinding(LogicalKeyboardKey.keyC.keyId)],
      back => [PlayerShortcutBinding(LogicalKeyboardKey.escape.keyId)],
      search => [
        PlayerShortcutBinding(LogicalKeyboardKey.keyK.keyId, control: true),
      ],
      home => [
        PlayerShortcutBinding(LogicalKeyboardKey.digit1.keyId, alt: true),
      ],
      dynamics => [
        PlayerShortcutBinding(LogicalKeyboardKey.digit2.keyId, alt: true),
      ],
      mine => [
        PlayerShortcutBinding(LogicalKeyboardKey.digit3.keyId, alt: true),
      ],
      homeRefresh => [PlayerShortcutBinding(LogicalKeyboardKey.f5.keyId)],
      currentTopOrRefresh => [
        PlayerShortcutBinding(LogicalKeyboardKey.f6.keyId),
      ],
    };
  }

  bool get isGlobal => switch (this) {
    back ||
    search ||
    home ||
    dynamics ||
    mine ||
    homeRefresh ||
    currentTopOrRefresh => true,
    _ => false,
  };
}

@immutable
class PlayerShortcutBinding {
  const PlayerShortcutBinding(
    this.keyId, {
    this.shift = false,
    this.control = false,
    this.alt = false,
    this.meta = false,
  });

  factory PlayerShortcutBinding.fromEvent(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    return PlayerShortcutBinding(
      event.logicalKey.keyId,
      shift: keyboard.isShiftPressed,
      control: keyboard.isControlPressed,
      alt: keyboard.isAltPressed,
      meta: keyboard.isMetaPressed,
    );
  }

  factory PlayerShortcutBinding.fromStorage(Object? value) {
    if (value is int) {
      return PlayerShortcutBinding(value);
    }
    if (value is String) {
      final parts = value.split(':');
      return PlayerShortcutBinding(
        int.parse(parts.first),
        shift: parts.elementAtOrNull(1) == '1',
        control: parts.elementAtOrNull(2) == '1',
        alt: parts.elementAtOrNull(3) == '1',
        meta: parts.elementAtOrNull(4) == '1',
      );
    }
    throw FormatException('Invalid shortcut binding: $value');
  }

  final int keyId;
  final bool shift;
  final bool control;
  final bool alt;
  final bool meta;

  String get storageValue =>
      '$keyId:${shift ? 1 : 0}:${control ? 1 : 0}:${alt ? 1 : 0}:${meta ? 1 : 0}';

  String get label {
    final parts = [
      if (meta) 'Meta',
      if (control) 'Ctrl',
      if (alt) 'Alt',
      if (shift) 'Shift',
      _keyLabel(keyId),
    ];
    return parts.join(' + ');
  }

  bool get isModifierKey => _modifierKeyIds.contains(keyId);

  bool matches(KeyEvent event, {bool allowExtraShift = false}) {
    if (event.logicalKey.keyId != keyId) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed != control ||
        keyboard.isAltPressed != alt ||
        keyboard.isMetaPressed != meta) {
      return false;
    }
    return keyboard.isShiftPressed == shift || (allowExtraShift && !shift);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerShortcutBinding &&
          runtimeType == other.runtimeType &&
          keyId == other.keyId &&
          shift == other.shift &&
          control == other.control &&
          alt == other.alt &&
          meta == other.meta;

  @override
  int get hashCode => Object.hash(keyId, shift, control, alt, meta);

  static String _keyLabel(int keyId) {
    final key = LogicalKeyboardKey.findKeyByKeyId(keyId);
    if (key == LogicalKeyboardKey.space) {
      return 'Space';
    }
    if (key == LogicalKeyboardKey.enter) {
      return 'Enter';
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      return '↑';
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      return '↓';
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      return '←';
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      return '→';
    }
    if (key == LogicalKeyboardKey.bracketLeft) {
      return '[';
    }
    if (key == LogicalKeyboardKey.bracketRight) {
      return ']';
    }
    if (key == LogicalKeyboardKey.escape) {
      return 'Esc';
    }
    if (key == LogicalKeyboardKey.tab) {
      return 'Tab';
    }
    final label = key?.keyLabel;
    if (label != null && label.isNotEmpty) {
      return label;
    }
    return '0x${keyId.toRadixString(16)}';
  }

  static final Set<int> _modifierKeyIds = {
    LogicalKeyboardKey.shift.keyId,
    LogicalKeyboardKey.shiftLeft.keyId,
    LogicalKeyboardKey.shiftRight.keyId,
    LogicalKeyboardKey.control.keyId,
    LogicalKeyboardKey.controlLeft.keyId,
    LogicalKeyboardKey.controlRight.keyId,
    LogicalKeyboardKey.alt.keyId,
    LogicalKeyboardKey.altLeft.keyId,
    LogicalKeyboardKey.altRight.keyId,
    LogicalKeyboardKey.meta.keyId,
    LogicalKeyboardKey.metaLeft.keyId,
    LogicalKeyboardKey.metaRight.keyId,
  };
}

abstract final class PlayerShortcutConfig {
  static bool isCapturingBinding = false;

  static List<PlayerShortcutBinding> bindingsOf(PlayerShortcutAction action) {
    final raw = _storedMap[action.id];
    if (raw is List) {
      return raw
          .map((item) {
            try {
              return PlayerShortcutBinding.fromStorage(item);
            } catch (_) {
              return null;
            }
          })
          .nonNulls
          .toList();
    }
    return action.defaultBindings;
  }

  static PlayerShortcutAction? actionFor(
    KeyEvent event, {
    bool includeGlobal = true,
    bool onlyGlobal = false,
  }) {
    for (final action in PlayerShortcutAction.values) {
      if (onlyGlobal && !action.isGlobal) {
        continue;
      }
      if (!includeGlobal && action.isGlobal) {
        continue;
      }
      final allowExtraShift = action == PlayerShortcutAction.fullscreen;
      for (final binding in bindingsOf(action)) {
        if (binding.matches(event, allowExtraShift: allowExtraShift)) {
          return action;
        }
      }
    }
    return null;
  }

  static bool shouldHandle(
    LogicalKeyboardKey logicalKey, {
    bool includeGlobal = true,
  }) {
    if (logicalKey == LogicalKeyboardKey.tab) {
      return true;
    }
    final keyId = logicalKey.keyId;
    return PlayerShortcutAction.values.any(
      (action) =>
          (includeGlobal || !action.isGlobal) &&
          bindingsOf(action).any((binding) => binding.keyId == keyId),
    );
  }

  static PlayerShortcutAction? actionOf(
    PlayerShortcutBinding binding, {
    PlayerShortcutAction? except,
  }) {
    for (final action in PlayerShortcutAction.values) {
      if (action == except) {
        continue;
      }
      if (bindingsOf(action).contains(binding)) {
        return action;
      }
    }
    return null;
  }

  static Future<void> addBinding(
    PlayerShortcutAction action,
    PlayerShortcutBinding binding,
  ) async {
    final map = _storedMap;
    map[action.id] = [
      ...bindingsOf(action).where((element) => element != binding),
      binding,
    ].map((element) => element.storageValue).toList();
    await GStorage.setting.put(SettingBoxKey.playerShortcuts, map);
  }

  static Future<void> removeBinding(
    PlayerShortcutAction action,
    PlayerShortcutBinding binding,
  ) {
    return setBindings(
      action,
      bindingsOf(action).where((element) => element != binding).toList(),
    );
  }

  static Future<void> reset(PlayerShortcutAction action) =>
      setBindings(action, action.defaultBindings);

  static Future<void> resetAll() =>
      GStorage.setting.delete(SettingBoxKey.playerShortcuts);

  static Future<void> clear(PlayerShortcutAction action) =>
      setBindings(action, const []);

  static Future<void> setBindings(
    PlayerShortcutAction action,
    List<PlayerShortcutBinding> bindings,
  ) {
    final map = _storedMap;
    map[action.id] = bindings.map((item) => item.storageValue).toList();
    return GStorage.setting.put(SettingBoxKey.playerShortcuts, map);
  }

  static Map<String, dynamic> get _storedMap {
    final raw = GStorage.setting.get(SettingBoxKey.playerShortcuts);
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return <String, dynamic>{};
  }
}
