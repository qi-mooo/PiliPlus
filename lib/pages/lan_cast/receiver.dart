import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/services/lan_cast/client.dart';
import 'package:PiliPlus/services/lan_cast/receiver.dart';
import 'package:PiliPlus/services/lan_cast/session.dart';
import 'package:PiliPlus/services/lan_cast/store.dart';
import 'package:material_ui/material_ui.dart';

class LanCastReceiverPage extends StatefulWidget {
  const LanCastReceiverPage({super.key});
  @override
  State<LanCastReceiverPage> createState() => _LanCastReceiverPageState();
}

class _LanCastReceiverPageState extends State<LanCastReceiverPage> {
  final _receiver = LanCastReceiver.instance;
  final _store = LanCastStore.instance;
  String? _error;

  Future<void> _forgetTarget(String id, Map<String, dynamic> target) async {
    final client = LanCastClient(Uri.parse(target['uri'] as String));
    try {
      if (LanCastSession.instance.device?.id == id) {
        await LanCastSession.instance.disconnect();
      }
      final info = await client.info();
      if (info.id == id) {
        client.token = target['token'] as String;
        await client.unpair();
      }
    } catch (_) {
      _error = '本机已忘记此设备；接收端离线时，可在接收端的已配对设备中移除本机。';
    } finally {
      client.close();
      await _store.remove('targets', id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _receiver,
    builder: (context, _) {
      final server = _receiver.server;
      return SimpleScaffold(
        appBar: AppBar(title: const Text('局域网推送')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SwitchListTile(
              title: const Text('允许接收局域网推送'),
              subtitle: const Text('已配对设备可直接连接；请保持 PiliPlus 打开'),
              value: _receiver.enabled,
              onChanged: _receiver.busy ? null : _receiver.setEnabled,
            ),
            if (_receiver.busy) const LinearProgressIndicator(),
            if (_error ?? _receiver.error case final error?) Text(error),
            if (server != null) ...[
              Text(server.name, style: Theme.of(context).textTheme.titleMedium),
              for (final address in _receiver.addresses)
                SelectableText(address),
              if (server.pairingCode case final code?) ...[
                const SizedBox(height: 16),
                const Text('配对码（2 分钟内有效，成功配对后自动关闭）'),
                SelectableText(
                  code,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                TextButton(
                  onPressed: server.endPairing,
                  child: const Text('关闭配对模式'),
                ),
              ] else
                FilledButton(
                  onPressed: server.beginPairing,
                  child: const Text('开启配对模式'),
                ),
              if (server.sender case final sender?)
                ListTile(
                  title: Text('正在接收来自 $sender 的推送'),
                  trailing: TextButton(
                    onPressed: server.disconnect,
                    child: const Text('断开'),
                  ),
                ),
            ],
            const Divider(height: 32),
            const Text('可控制本机的设备'),
            if (_store.peers.isEmpty) const ListTile(title: Text('暂无已配对设备')),
            for (final peer in _store.peers.entries)
              ListTile(
                title: Text(peer.value['name'] as String),
                trailing: IconButton(
                  tooltip: '取消配对',
                  icon: const Icon(Icons.link_off),
                  onPressed: () async {
                    if (server != null) {
                      await server.revoke(peer.key);
                    } else {
                      await _store.remove('peers', peer.key);
                    }
                    if (mounted) setState(() {});
                  },
                ),
              ),
            const Divider(height: 32),
            const Text('已记住的接收设备'),
            if (_store.targets.isEmpty) const ListTile(title: Text('暂无已配对设备')),
            for (final target in _store.targets.entries)
              ListTile(
                title: Text(target.value['name'] as String),
                trailing: IconButton(
                  tooltip: '取消配对',
                  icon: const Icon(Icons.link_off),
                  onPressed: () => _forgetTarget(target.key, target.value),
                ),
              ),
          ],
        ),
      );
    },
  );
}
