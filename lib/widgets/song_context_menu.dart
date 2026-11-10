import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../models/addon.dart';
import '../services/music_library.dart';
import '../services/player_service.dart';
import 'orchid_style.dart';

/// Reusable desktop right-click / mobile long-press song actions.
/// OverlayEntry keeps the menu independent from the current page's layout.
class SongContextMenu extends StatefulWidget {
  final Widget child;
  final TrackResult track;
  final PlayerService player;
  final MusicLibrary library;
  final bool openOnTap;
  final bool showMenuButton;

  const SongContextMenu({
    super.key,
    required this.child,
    required this.track,
    required this.player,
    required this.library,
    this.openOnTap = false,
    this.showMenuButton = false,
  });

  @override
  State<SongContextMenu> createState() => _SongContextMenuState();
}

class _SongContextMenuState extends State<SongContextMenu> {
  OverlayEntry? _entry;

  void _close() {
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  void _open(Offset position) {
    _close();
    final screen = MediaQuery.sizeOf(context);
    const width = 268.0;
    const height = 402.0;
    final left = position.dx.clamp(8.0, (screen.width - width - 8).clamp(8.0, double.infinity)).toDouble();
    final top = position.dy.clamp(8.0, (screen.height - height - 8).clamp(8.0, double.infinity)).toDouble();
    final overlay = Overlay.of(context);
    _entry = OverlayEntry(builder: (_) => Stack(children: [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _close,
        ),
      ),
      Positioned(
        left: left, top: top,
        width: width,
        child: _SongActionPanel(
          track: widget.track,
          player: widget.player,
          library: widget.library,
          dismiss: _close,
        ),
      ),
    ]));
    overlay.insert(_entry!);
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  void _openBelowButton() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final position = box.localToGlobal(
      Offset(box.size.width - 12, box.size.height),
    );
    _open(position);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onSecondaryTapDown: (details) => _open(details.globalPosition),
    onLongPressStart: (details) => _open(details.globalPosition),
    onTap: widget.openOnTap ? _openBelowButton : null,
    child: widget.showMenuButton
      ? Stack(children: [
          widget.child,
          Positioned(
            right: 0, top: 0, bottom: 0,
            child: Center(
              child: IconButton.ghost(
                onPressed: _openBelowButton,
                icon: const Icon(LucideIcons.ellipsis, size: 19),
              ),
            ),
          ),
        ])
      : widget.child,
  );
}

class _SongActionPanel extends StatefulWidget {
  final TrackResult track;
  final PlayerService player;
  final MusicLibrary library;
  final VoidCallback dismiss;

  const _SongActionPanel({
    required this.track,
    required this.player,
    required this.library,
    required this.dismiss,
  });

  @override
  State<_SongActionPanel> createState() => _SongActionPanelState();
}

class _SongActionPanelState extends State<_SongActionPanel> {
  final _name = TextEditingController();
  bool _creating = false;

  SavedSong get _saved => SavedSong(widget.track.title, widget.track.artist,
    album: widget.track.album, artwork: widget.track.artworkUrl);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final playlist = await widget.library.createPlaylist(name);
    await widget.library.addToPlaylist(playlist, _saved);
    if (mounted) widget.dismiss();
  }

  Widget _action(String label, IconData icon, VoidCallback callback) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: callback,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        child: Row(children: [
          Icon(icon, size: 17, color: OrchidStyle.lilac),
          const SizedBox(width: 12),
          Expanded(child: Text(label).small()),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: OrchidStyle.panelDecoration(radius: 17),
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: ListenableBuilder(
      listenable: widget.library,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 7),
            child: Text(widget.track.title, maxLines: 1,
              overflow: TextOverflow.ellipsis).semiBold(),
          ),
          _action('Play Now', LucideIcons.play, () {
            widget.dismiss();
            widget.player.playTrack(widget.track).catchError((Object e) {
              debugPrint('[Orchid] Play Now failed: $e');
            });
          }),
          _action('Add to Queue', LucideIcons.listMusic, () {
            widget.player.addToQueue(widget.track);
            widget.dismiss();
          }),
          _action(widget.library.isInLibrary(_saved)
              ? 'Remove from Library' : 'Add to Library',
              widget.library.isInLibrary(_saved)
                  ? LucideIcons.check : LucideIcons.library,
              () {
                if (widget.library.isInLibrary(_saved)) {
                  widget.library.removeFromLibrary(_saved);
                } else {
                  widget.library.addToLibrary(_saved);
                }
                widget.dismiss();
              }),
          _action(widget.library.isFavorite(_saved)
              ? 'Remove from Favorites' : 'Add to Favorites',
              LucideIcons.heart, () {
                widget.library.toggleFavorite(_saved);
                widget.dismiss();
              }),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 5, 14, 5),
            child: const Text('Add to playlist').small().muted(),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 145),
            child: SingleChildScrollView(
              child: Column(children: [
                for (final playlist in widget.library.visiblePlaylists)
                  _action(
                    playlist.name,
                    widget.library.contains(playlist, _saved)
                        ? LucideIcons.check : LucideIcons.plus,
                    () {
                      widget.library.addToPlaylist(playlist, _saved);
                      widget.dismiss();
                    },
                  ),
              ]),
            ),
          ),
          if (_creating)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(children: [
                Expanded(child: TextField(
                  controller: _name,
                  placeholder: const Text('Playlist name'),
                  onSubmitted: (_) => _create(),
                )),
                const SizedBox(width: 5),
                IconButton.ghost(
                  onPressed: _create,
                  icon: const Icon(LucideIcons.check, size: 18),
                ),
              ]),
            )
          else
            _action('Create new playlist', LucideIcons.plus,
              () => setState(() => _creating = true)),
        ],
      ),
    ),
  );
}
