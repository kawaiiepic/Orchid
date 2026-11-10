import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../services/player_service.dart';
import 'content_drawer.dart';

/// Device output and local sound options. Remote-session handoff is only
/// possible once Orchid provides a real shared playback/session backend.
void showAudioConnectSheet(BuildContext context, PlayerService player) {
  showOrchidActionDrawer(
    context,
    maxHeightFraction: .84,
    builder: (sheetContext, close) => _AudioConnectSheet(
      player: player,
      close: close,
    ),
  );
}

class _AudioConnectSheet extends StatefulWidget {
  final PlayerService player;
  final VoidCallback close;
  const _AudioConnectSheet({required this.player, required this.close});

  @override
  State<_AudioConnectSheet> createState() => _AudioConnectSheetState();
}

class _AudioConnectSheetState extends State<_AudioConnectSheet> {
  static const _platform = MethodChannel('orchid/audio_routes');
  String? _message;
  bool _pipeline = false;

  Future<void> _openSystemAudioSettings() async {
    try {
      await _platform.invokeMethod<void>('openAudioSettings');
    } catch (_) {
      if (mounted) setState(() =>
          _message = 'Audio output settings are unavailable on this device.');
    }
  }

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 9),
    child: Text(label, style: const TextStyle(
      fontSize: 13, fontWeight: FontWeight.w600,
      color: Color(0xFF9C9CA4))),
  );

  Widget _tile(IconData icon, String name, String description, {
    VoidCallback? onTap, Widget? trailing, Color? subtitleColor,
  }) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(children: [
        SizedBox(width: 54, child: Icon(icon, size: 26,
          color: const Color(0xFFF1F2F0))),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(
              color: Color(0xFFF7F7F4), fontSize: 17,
              fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(description, style: TextStyle(
              color: subtitleColor ?? const Color(0xFF96979B),
              fontSize: 13)),
          ],
        )),
        if (trailing != null) trailing,
      ]),
    ),
  );

  Widget _pipelineControls() => ListenableBuilder(
    listenable: widget.player,
    builder: (_, __) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(LucideIcons.volume2, size: 17),
            const SizedBox(width: 12),
            Expanded(child: Slider(
              min: 0, max: 1,
              value: SliderValue.single(widget.player.volume),
              onChanged: (v) => widget.player.setVolume(v.value),
            )),
            const SizedBox(width: 12),
            Text('${(widget.player.volume * 100).round()}%',
              style: const TextStyle(fontSize: 12)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.player.toggleShuffle,
              child: Row(children: [
                Icon(LucideIcons.shuffle, size: 18,
                  color: widget.player.shuffleEnabled
                      ? const Color(0xFFD95A9C) : null),
                const SizedBox(width: 8),
                Text(widget.player.shuffleEnabled
                    ? 'Shuffle on' : 'Shuffle off'),
              ]),
            )),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.player.cycleRepeatMode,
              child: Row(children: [
                Icon(widget.player.repeatMode == OrchidRepeatMode.one
                    ? LucideIcons.repeat1 : LucideIcons.repeat,
                  size: 18,
                  color: widget.player.repeatMode != OrchidRepeatMode.off
                      ? const Color(0xFFD95A9C) : null),
                const SizedBox(width: 8),
                Text(widget.player.repeatMode == OrchidRepeatMode.one
                    ? 'Repeat one' : widget.player.repeatMode ==
                        OrchidRepeatMode.all ? 'Repeat all' : 'Repeat off'),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Text('Source: ${widget.player.sourceLabel}',
            style: const TextStyle(fontSize: 12,
              color: Color(0xFFAAA5B0))),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.player,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.only(bottom: 22),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 14, 12),
          child: Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Connect to a device', style: TextStyle(
                  fontSize: 23, fontWeight: FontWeight.w700,
                  color: Color(0xFFFFFFFF))),
                const SizedBox(height: 5),
                const Text('Choose where Orchid plays audio',
                  style: TextStyle(fontSize: 14,
                    color: Color(0xFF9E9EA4))),
              ],
            )),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.close,
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Text('Done', style: TextStyle(
                  color: Color(0xFFE35C9B), fontSize: 17,
                  fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
        const Divider(),
        _tile(LucideIcons.smartphone, 'This device',
          'Currently playing locally',
          subtitleColor: const Color(0xFFE35C9B),
          trailing: const Icon(LucideIcons.volume2,
            color: Color(0xFFE35C9B), size: 20)),
        _section('AirPlay & Bluetooth'),
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(children: [
              Expanded(child: _tile(
                LucideIcons.speaker, 'Speaker & TV',
                'AirPlay, Bluetooth & other devices')),
              const SizedBox(
                width: 54, height: 52,
                child: UiKitView(
                  viewType: 'orchid/airplay-route-picker'),
              ),
            ]),
          )
        else
          _tile(LucideIcons.speaker, 'Speaker & TV',
            'Open system audio & Bluetooth settings',
            onTap: _openSystemAudioSettings,
            trailing: const Icon(LucideIcons.chevronRight,
              color: Color(0xFF99999F))),
        _section('Your Devices'),
        _tile(LucideIcons.monitor, 'Other Orchid devices',
          'Remote transfer is not available yet'),
        _section('Listen Together'),
        _tile(LucideIcons.radio, 'Start a Jam',
          'Shared playback sessions are not available yet'),
        const Divider(),
        _tile(LucideIcons.audioLines, 'Audio Pipeline',
          'Volume, shuffle, repeat & playback source',
          onTap: () => setState(() => _pipeline = !_pipeline),
          trailing: Icon(_pipeline ? LucideIcons.chevronDown
              : LucideIcons.chevronRight,
              color: const Color(0xFF99999F))),
        if (_pipeline) _pipelineControls(),
        if (_message != null) Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_message!, style: const TextStyle(
            color: Color(0xFFF6B1B1), fontSize: 12)),
        ),
      ],
    ),
  );
}
