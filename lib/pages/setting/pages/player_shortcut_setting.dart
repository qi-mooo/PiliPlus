import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/models/common/player_shortcut.dart';
import 'package:flutter/services.dart' show KeyDownEvent, KeyEvent;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class PlayerShortcutSettingPage extends StatefulWidget {
  const PlayerShortcutSettingPage({super.key});

  @override
  State<PlayerShortcutSettingPage> createState() =>
      _PlayerShortcutSettingPageState();
}

class _PlayerShortcutSettingPageState extends State<PlayerShortcutSettingPage> {
  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewPaddingOf(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('快捷键绑定'),
        actions: [
          IconButton(
            tooltip: '恢复默认',
            onPressed: () async {
              await PlayerShortcutConfig.resetAll();
              if (mounted) {
                setState(() {});
              }
              SmartDialog.showToast('已恢复默认快捷键');
            },
            icon: const Icon(Icons.restore_outlined),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: ListView.builder(
        padding: EdgeInsets.only(
          left: padding.left,
          right: padding.right,
          bottom: padding.bottom + 100,
        ),
        itemCount: PlayerShortcutAction.values.length,
        itemBuilder: (context, index) {
          final action = PlayerShortcutAction.values[index];
          final bindings = PlayerShortcutConfig.bindingsOf(action);
          return ListTile(
            leading: Icon(action.icon),
            title: Text(action.title),
            subtitle: Text(
              bindings.isEmpty
                  ? '未设置'
                  : bindings.map((item) => item.label).join(' / '),
            ),
            trailing: const Icon(Icons.keyboard_arrow_right),
            onTap: () => _showEditDialog(action),
          );
        },
      ),
    );
  }

  Future<void> _showEditDialog(PlayerShortcutAction action) {
    return showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            final bindings = PlayerShortcutConfig.bindingsOf(action);
            return AlertDialog(
              title: Text(action.title),
              content: ConstrainedBox(
                constraints: Style.dialogFixedConstraints,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (bindings.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            '未设置快捷键',
                            style: TextStyle(
                              color: ColorScheme.of(context).outline,
                            ),
                          ),
                        )
                      else
                        ...bindings.map(
                          (binding) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(binding.label),
                            trailing: IconButton(
                              tooltip: '删除',
                              onPressed: () async {
                                await PlayerShortcutConfig.removeBinding(
                                  action,
                                  binding,
                                );
                                _refresh(dialogSetState);
                              },
                              icon: const Icon(Icons.close),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    await PlayerShortcutConfig.clear(action);
                    _refresh(dialogSetState);
                  },
                  child: const Text('清空'),
                ),
                TextButton(
                  onPressed: () async {
                    await PlayerShortcutConfig.reset(action);
                    _refresh(dialogSetState);
                  },
                  child: const Text('默认'),
                ),
                TextButton(
                  onPressed: () => _addBinding(action, dialogSetState),
                  child: const Text('添加'),
                ),
                TextButton(
                  onPressed: Get.back,
                  child: Text(
                    '完成',
                    style: TextStyle(color: ColorScheme.of(context).outline),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addBinding(
    PlayerShortcutAction action,
    StateSetter dialogSetState,
  ) async {
    final binding = await showDialog<PlayerShortcutBinding>(
      context: context,
      builder: (context) => const _ShortcutCaptureDialog(),
    );
    if (binding == null) {
      return;
    }
    final oldAction = PlayerShortcutConfig.actionOf(binding, except: action);
    await PlayerShortcutConfig.addBinding(action, binding);
    _refresh(dialogSetState);
    if (oldAction != null) {
      SmartDialog.showToast('已保存，与「${oldAction.title}」共用快捷键');
    }
  }

  void _refresh(StateSetter dialogSetState) {
    dialogSetState(() {});
    if (mounted) {
      setState(() {});
    }
  }
}

class _ShortcutCaptureDialog extends StatefulWidget {
  const _ShortcutCaptureDialog();

  @override
  State<_ShortcutCaptureDialog> createState() => _ShortcutCaptureDialogState();
}

class _ShortcutCaptureDialogState extends State<_ShortcutCaptureDialog> {
  final FocusNode _focusNode = FocusNode();
  PlayerShortcutBinding? _binding;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('添加快捷键'),
      content: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: ConstrainedBox(
          constraints: Style.dialogFixedConstraints,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SizedBox(
              height: 96,
              child: Center(
                child: Text(
                  _binding?.label ?? '请按下要添加的快捷键',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: Get.back,
          child: Text(
            '取消',
            style: TextStyle(color: ColorScheme.of(context).outline),
          ),
        ),
        TextButton(
          onPressed: _binding == null ? null : () => Get.back(result: _binding),
          child: const Text('保存'),
        ),
      ],
    );
  }

  void _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return;
    }
    final binding = PlayerShortcutBinding.fromEvent(event);
    if (binding.isModifierKey) {
      return;
    }
    setState(() => _binding = binding);
  }
}
