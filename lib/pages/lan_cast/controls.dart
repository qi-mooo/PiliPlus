import 'package:PiliPlus/services/lan_cast/protocol.dart';
import 'package:material_ui/material_ui.dart';

class LanCastControls extends StatefulWidget {
  const LanCastControls({
    super.key,
    required this.status,
    required this.onCommand,
    this.enabled = true,
  });
  final LanCastStatus status;
  final Future<void> Function(String, [double?]) onCommand;
  final bool enabled;

  @override
  State<LanCastControls> createState() => _LanCastControlsState();
}

class _LanCastControlsState extends State<LanCastControls> {
  double? _seek;
  double? _volume;

  String _time(num milliseconds) {
    final seconds = milliseconds ~/ 1000;
    final minutes = seconds ~/ 60;
    return '${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final enabled = widget.enabled && status.title.isNotEmpty;
    final canSeek = enabled && !status.isLive && status.duration > 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status.error case final error?)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              error,
              style: TextStyle(color: ColorScheme.of(context).error),
            ),
          ),
        if (status.buffering) const LinearProgressIndicator(),
        if (!status.isLive) ...[
          Slider(
            semanticFormatterCallback: _time,
            value: (_seek ?? status.position.toDouble()).clamp(
              0,
              status.duration.toDouble(),
            ),
            max: status.duration > 0 ? status.duration.toDouble() : 1,
            onChanged: canSeek
                ? (value) => setState(() => _seek = value)
                : null,
            onChangeEnd: canSeek
                ? (value) async {
                    await widget.onCommand('seek', value);
                    if (mounted) setState(() => _seek = null);
                  }
                : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_time(_seek ?? status.position)),
                Text(_time(status.duration)),
              ],
            ),
          ),
        ] else
          const Center(child: Text('直播中')),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: '后退 10 秒',
              iconSize: 34,
              onPressed: canSeek
                  ? () => widget.onCommand(
                      'seek',
                      (status.position - 10000)
                          .clamp(0, status.duration)
                          .toDouble(),
                    )
                  : null,
              icon: const Icon(Icons.replay_10),
            ),
            const SizedBox(width: 24),
            IconButton.filled(
              tooltip: status.playing ? '暂停' : '播放',
              iconSize: 48,
              onPressed: enabled
                  ? () => widget.onCommand(status.playing ? 'pause' : 'play')
                  : null,
              icon: Icon(status.playing ? Icons.pause : Icons.play_arrow),
            ),
            const SizedBox(width: 24),
            IconButton(
              tooltip: '快进 10 秒',
              iconSize: 34,
              onPressed: canSeek
                  ? () => widget.onCommand(
                      'seek',
                      (status.position + 10000)
                          .clamp(0, status.duration)
                          .toDouble(),
                    )
                  : null,
              icon: const Icon(Icons.forward_10),
            ),
          ],
        ),
        Row(
          children: [
            IconButton(
              tooltip: status.volume == 0 ? '取消静音' : '静音',
              onPressed: enabled
                  ? () =>
                        widget.onCommand('volume', status.volume == 0 ? 50 : 0)
                  : null,
              icon: Icon(
                status.volume == 0
                    ? Icons.volume_off_outlined
                    : Icons.volume_up_outlined,
              ),
            ),
            Expanded(
              child: Slider(
                label: '${(_volume ?? status.volume).round()}%',
                value: (_volume ?? status.volume).clamp(0, 100),
                max: 100,
                onChanged: enabled
                    ? (value) => setState(() => _volume = value)
                    : null,
                onChangeEnd: enabled
                    ? (value) async {
                        await widget.onCommand('volume', value);
                        if (mounted) setState(() => _volume = null);
                      }
                    : null,
              ),
            ),
            SizedBox(
              width: 42,
              child: Text('${(_volume ?? status.volume).round()}%'),
            ),
          ],
        ),
        if (!status.isLive)
          Center(
            child: PopupMenuButton<double>(
              enabled: enabled,
              tooltip: '播放速度',
              initialValue: status.speed,
              onSelected: (value) => widget.onCommand('speed', value),
              itemBuilder: (_) => [
                for (final speed in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0])
                  PopupMenuItem(value: speed, child: Text('${speed}x')),
              ],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('倍速 ${status.speed}x ▾'),
              ),
            ),
          ),
      ],
    );
  }
}
