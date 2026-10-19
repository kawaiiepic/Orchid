import 'package:flutter/scheduler.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/lyrics_service.dart';
import '../services/player_service.dart';

/// In-app floating lyrics (Sweet Lyrics–style PiP strip).
///
/// Stays on top while Orchid is open. True OS Picture-in-Picture (over other
/// apps) needs platform channels / plugins and is not enabled here yet.
class FloatingLyricsController extends ChangeNotifier {
  static final FloatingLyricsController instance = FloatingLyricsController._();
  FloatingLyricsController._();

  bool enabled = false;
  Offset offset = const Offset(16, 120);
  OverlayEntry? _entry;
  PlayerService? _player;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    enabled = p.getBool('lyrics.floatingEnabled') ?? false;
    final dx = p.getDouble('lyrics.floatingDx');
    final dy = p.getDouble('lyrics.floatingDy');
    if (dx != null && dy != null) offset = Offset(dx, dy);
    notifyListeners();
  }

  Future<void> setEnabled(bool v) async {
    enabled = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool('lyrics.floatingEnabled', v);
    notifyListeners();
    _syncOverlay();
  }

  Future<void> _saveOffset() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble('lyrics.floatingDx', offset.dx);
    await p.setDouble('lyrics.floatingDy', offset.dy);
  }

  void attach(PlayerService player, BuildContext context) {
    _player = player;
    player.addListener(_onPlayer);
    _syncOverlay(context: context);
  }

  void detach() {
    _player?.removeListener(_onPlayer);
    _removeEntry();
    _player = null;
  }

  void _onPlayer() => _syncOverlay();

  void _syncOverlay({BuildContext? context}) {
    final player = _player;
    if (player == null) return;

    if (!enabled || player.current == null) {
      _removeEntry();
      return;
    }

    if (_entry != null) {
      _entry!.markNeedsBuild();
      return;
    }

    final overlay = context != null
        ? Overlay.maybeOf(context, rootOverlay: true)
        : null;
    if (overlay == null) return;

    _entry = OverlayEntry(
      builder: (ctx) => _FloatingLyricsBubble(
        player: player,
        offset: offset,
        onOffset: (o) {
          offset = o;
          _saveOffset();
          _entry?.markNeedsBuild();
        },
        onClose: () => setEnabled(false),
      ),
    );
    overlay.insert(_entry!);
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
  }

  void showFrom(BuildContext context) {
    enabled = true;
    SharedPreferences.getInstance().then((p) {
      p.setBool('lyrics.floatingEnabled', true);
    });
    notifyListeners();
    _removeEntry();
    _syncOverlay(context: context);
  }
}

class _FloatingLyricsBubble extends StatefulWidget {
  final PlayerService player;
  final Offset offset;
  final ValueChanged<Offset> onOffset;
  final VoidCallback onClose;

  const _FloatingLyricsBubble({
    required this.player,
    required this.offset,
    required this.onOffset,
    required this.onClose,
  });

  @override
  State<_FloatingLyricsBubble> createState() => _FloatingLyricsBubbleState();
}

class _FloatingLyricsBubbleState extends State<_FloatingLyricsBubble>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late Offset _pos;

  @override
  void initState() {
    super.initState();
    _pos = widget.offset;
    _ticker = createTicker((_) {
      if (mounted) setState(() {});
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  String _currentLine(LyricsResult? lyrics, double t) {
    if (lyrics == null || lyrics.lines.isEmpty) {
      final plain = lyrics?.displayText ?? '';
      if (plain.isEmpty) return 'No lyrics';
      return plain.split('\n').first;
    }
    final i = lyrics.lineIndexAt(t);
    if (i < 0) return lyrics.lines.first.text;
    final line = lyrics.lines[i];
    if (line.isInterlude) return '• • •';
    return line.text.isEmpty ? '…' : line.text;
  }

  String _nextLine(LyricsResult? lyrics, double t) {
    if (lyrics == null || lyrics.lines.isEmpty) return '';
    final i = lyrics.lineIndexAt(t);
    if (i < 0 || i + 1 >= lyrics.lines.length) return '';
    final n = lyrics.lines[i + 1];
    if (n.isInterlude) return '• • •';
    return n.text;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final player = widget.player;
    final t = player.player.position.inMilliseconds / 1000.0;
    final line = _currentLine(player.lyrics, t);
    final next = _nextLine(player.lyrics, t);
    final track = player.current;

    final size = MediaQuery.sizeOf(context);
    final maxX = size.width - 280;
    final maxY = size.height - 120;

    return Positioned(
      left: _pos.dx.clamp(8.0, maxX > 8 ? maxX : 8),
      top: _pos.dy.clamp(8.0, maxY > 8 ? maxY : 8),
      child: GestureDetector(
        onPanUpdate: (d) {
          setState(() {
            _pos += d.delta;
          });
        },
        onPanEnd: (_) => widget.onOffset(_pos),
        child: Container(
          width: 268,
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            color: scheme.card.withOpacity(0.94),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.border),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF000000).withOpacity(0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      track?.title ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ).xSmall().muted(),
                  ),
                  IconButton(
                    variance: ButtonVariance.ghost,
                    onPressed: widget.onClose,
                    icon: const Icon(LucideIcons.x, size: 16),
                  ),
                ],
              ),
              Text(
                line,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: scheme.foreground,
                  height: 1.25,
                ),
              ),
              if (next.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  next,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.mutedForeground,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    variance: ButtonVariance.ghost,
                    onPressed: () => player.playPrevious(),
                    icon: const Icon(LucideIcons.skipBack, size: 16),
                  ),
                  IconButton(
                    variance: ButtonVariance.ghost,
                    onPressed: () => player.togglePlayPause(),
                    icon: Icon(
                      player.player.playing
                          ? LucideIcons.pause
                          : LucideIcons.play,
                      size: 18,
                    ),
                  ),
                  IconButton(
                    variance: ButtonVariance.ghost,
                    onPressed: player.hasNext ? () => player.playNext() : null,
                    icon: const Icon(LucideIcons.skipForward, size: 16),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
