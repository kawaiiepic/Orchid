import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'content_drawer.dart';

import '../models/addon.dart';
import '../services/addon_service.dart';
import '../screens/song_detail_screen.dart';
import '../screens/music_detail_pages.dart';
import '../services/music_catalog_service.dart';
import 'apple_cover.dart';
import '../services/music_library.dart';
import '../services/player_service.dart';
import 'orchid_style.dart';
import '../services/orchid_share.dart';

/// Reusable desktop right-click / mobile long-press song actions.
/// OverlayEntry keeps the menu independent from the current page's layout.
class SongContextMenu extends StatefulWidget {
  final Widget child;
  final TrackResult track;
  final PlayerService player;
  final MusicLibrary library;
  final AddonService? addonService;
  final List<InstalledAddon> addons;
  final MusicPlaylist? playlist;
  final bool openOnTap;
  final bool showMenuButton;
  final bool showViewSong;

  const SongContextMenu({
    super.key,
    required this.child,
    required this.track,
    required this.player,
    required this.library,
    this.addonService,
    this.addons = const [],
    this.playlist,
    this.openOnTap = false,
    this.showMenuButton = true,
    this.showViewSong = true,
  });

  @override
  State<SongContextMenu> createState() => _SongContextMenuState();
}

class _SongContextMenuState extends State<SongContextMenu> {
  OverlayEntry? _entry;
  bool _hovered = false;
  bool _menuHovered = false;

  void _close() {
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  void _open(Offset position) {
    if (MediaQuery.sizeOf(context).width < 850) {
      _openMobileSheet();
      return;
    }
    _close();
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox;
    // Pointer coordinates are global, but Positioned expects coordinates
    // relative to this overlay (which can live inside the content navigator).
    final pointer = overlayBox.globalToLocal(position);
    final bounds = overlayBox.size;
    const width = 268.0;
    const height = 402.0;
    const margin = 8.0;
    final left = pointer.dx.clamp(
      margin, (bounds.width - width - margin).clamp(margin, double.infinity),
    ).toDouble();
    final top = pointer.dy.clamp(
      margin, (bounds.height - height - margin).clamp(margin, double.infinity),
    ).toDouble();
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
          addonService: widget.addonService,
          addons: widget.addons,
          showViewSong: widget.showViewSong,
          playlist: widget.playlist,
          dismiss: _close,
        ),
      ),
    ]));
    overlay.insert(_entry!);
  }

  void _openMobileSheet() {
    showOrchidActionDrawer(
      context,
      maxHeightFraction: .82,
      builder: (drawerContext, close) => SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: _SongActionPanel(
          track: widget.track,
          player: widget.player,
          library: widget.library,
          addonService: widget.addonService,
          addons: widget.addons,
          showViewSong: widget.showViewSong,
          playlist: widget.playlist,
          mobileSheet: true,
          dismiss: close,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) { if (mounted) setState(() => _hovered = true); },
    onExit: (_) { if (mounted) setState(() { _hovered = false; _menuHovered = false; }); },
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => _open(details.globalPosition),
      onLongPressStart: (details) => _open(details.globalPosition),
      onTapDown: widget.openOnTap
          ? (details) => _open(details.globalPosition)
          : null,
      child: widget.showMenuButton
        ? Stack(children: [
            widget.child,
            Positioned(
              right: 0, top: 0, bottom: 0,
              child: IgnorePointer(
                ignoring: !(_hovered || MediaQuery.sizeOf(context).width < 850),
                child: AnimatedOpacity(
                  opacity: (_hovered || MediaQuery.sizeOf(context).width < 850)
                      ? 1 : 0,
                  duration: const Duration(milliseconds: 140),
                  child: Center(
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      onEnter: (_) => setState(() => _menuHovered = true),
                      onExit: (_) => setState(() => _menuHovered = false),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) => _open(details.globalPosition),
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: Center(
                            child: Icon(
                              LucideIcons.ellipsis,
                              size: 19,
                              color: _menuHovered
                                  ? const Color(0xFFF8F6FC)
                                  : const Color(0xFF9E96AB),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ])
        : widget.child,
    ),
  );
}

class _SongActionPanel extends StatefulWidget {
  final TrackResult track;
  final PlayerService player;
  final MusicLibrary library;
  final AddonService? addonService;
  final List<InstalledAddon> addons;
  final MusicPlaylist? playlist;
  final bool showViewSong;
  final VoidCallback dismiss;
  final bool mobileSheet;

  const _SongActionPanel({
    required this.track,
    required this.player,
    required this.library,
    this.addonService,
    this.addons = const [],
    this.showViewSong = true,
    this.playlist,
    required this.dismiss,
    this.mobileSheet = false,
  });

  @override
  State<_SongActionPanel> createState() => _SongActionPanelState();
}

class _SongActionPanelState extends State<_SongActionPanel> {
  final _name = TextEditingController();
  bool _creating = false;
  bool _saving = false;
  bool _showMobilePlaylists = false;
  String? _error;
  OverlayEntry? _playlistSubmenu;

  SavedSong get _saved => SavedSong(widget.track.title, widget.track.artist,
    album: widget.track.album, artwork: widget.track.artworkUrl,
    duration: widget.track.duration);

  @override
  void dispose() {
    _closePlaylistSubmenu();
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty || _saving) return;
    setState(() { _saving = true; _error = null; });
    try {
      await widget.library.createPlaylistWithSong(name, _saved);
      if (mounted) widget.dismiss();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      debugPrint('[Orchid] Create playlist failed: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addTo(MusicPlaylist playlist) async {
    if (_saving) return;
    setState(() { _saving = true; _error = null; });
    try {
      await widget.library.addToPlaylist(playlist, _saved);
      _closePlaylistSubmenu();
      if (mounted) widget.dismiss();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      debugPrint('[Orchid] Add to playlist failed: $error');
      _closePlaylistSubmenu();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _closePlaylistSubmenu() {
    _playlistSubmenu?.remove();
    _playlistSubmenu?.dispose();
    _playlistSubmenu = null;
  }

  void _openPlaylistSubmenu() {
    if (widget.mobileSheet) {
      setState(() => _showMobilePlaylists = true);
      return;
    }
    _closePlaylistSubmenu();
    final box = context.findRenderObject();
    if (box is! RenderBox) return;
    final origin = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.sizeOf(context);
    const width = 248.0;
    final left = origin.dx + box.size.width + width + 8 < screen.width
        ? origin.dx + box.size.width + 4
        : (origin.dx - width - 4).clamp(8.0, screen.width - width - 8.0);
    final top = origin.dy.clamp(
      8.0, (screen.height - 290).clamp(8.0, double.infinity));
    _playlistSubmenu = OverlayEntry(builder: (_) => Stack(children: [
      Positioned.fill(child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _closePlaylistSubmenu,
      )),
      Positioned(
      left: left.toDouble(), top: top.toDouble(), width: width,
      child: OrchidGlassPanel(
        radius: 14, transparentOnDesktop: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 290),
          child: ListenableBuilder(
            listenable: widget.library,
            builder: (_, __) => SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final playlist in widget.library.visiblePlaylists)
                  _action(
                    playlist.name,
                    widget.library.contains(playlist, _saved)
                      ? LucideIcons.check : LucideIcons.plus,
                    () => _addTo(playlist),
                  ),
                _action('New playlist', LucideIcons.plus, () {
                  _closePlaylistSubmenu();
                  setState(() => _creating = true);
                }),
              ]),
            ),
          ),
        ),
      ),
      ),
    ]));
    Overlay.of(context).insert(_playlistSubmenu!);
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
  Widget build(BuildContext context) => widget.mobileSheet
      ? _mobilePanelBody()
      : OrchidGlassPanel(
          radius: 17,
          transparentOnDesktop: false,
          child: _panelBody(),
        );

  void _playNow() {
    widget.player.setAddons(widget.addons);
    widget.dismiss();
    widget.player.playTrack(widget.track).catchError(
      (Object error) => debugPrint('[Orchid Drawer] Playback failed: $error'),
    );
  }

  void _openSongDetails() {
    showSongDetailDrawer(context,
      player: widget.player,
      addonService: widget.addonService ?? AddonService(),
      addons: widget.addons,
      library: widget.library,
      title: widget.track.title,
      artist: widget.track.artist,
      album: widget.track.album,
      artworkUrl: widget.track.artworkUrl,
      track: widget.track,
    );
    widget.dismiss();
  }

  Future<void> _startSongRadio() async {
    widget.dismiss();
    try {
      final catalog = MusicCatalogService.instance;
      final results = await catalog.searchTracks(widget.track.artist);
      final unique = <String, TrackResult>{};
      unique['${widget.track.artist.toLowerCase()}|${widget.track.title.toLowerCase()}'] =
          widget.track;
      for (final track in results) {
        unique.putIfAbsent(
          '${track.artist.trim().toLowerCase()}|${track.title.trim().toLowerCase()}',
          () => track);
      }
      final tracks = unique.values.toList();
      if (tracks.length > 1) {
        final rest = tracks.sublist(1)..shuffle();
        tracks.replaceRange(1, tracks.length, rest);
      }
      widget.player.setAddons(widget.addons);
      await widget.player.playTrack(
        tracks.first, fromQueue: tracks,
      );
    } catch (error) {
      debugPrint('[Orchid Drawer] Could not start radio: $error');
    }
  }

  Widget _mobileSection(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 21, 22, 10),
    child: Text(title, style: const TextStyle(
      fontSize: 12, fontWeight: FontWeight.w600,
      color: Color(0xFFAE9EBA),
    )),
  );

  Widget _mobileDivider() => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    child: SizedBox(height: 1,
      child: ColoredBox(color: Color(0x335F5364))),
  );

  Widget _mobileRow(String label, IconData icon, VoidCallback action, {
    bool trailing = false,
  }) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: action,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
      child: Row(children: [
        SizedBox(width: 28, child: Icon(icon,
          size: 21, color: const Color(0xFFE5DDEB))),
        const SizedBox(width: 16),
        Expanded(child: Text(label,
          style: const TextStyle(fontSize: 16,
            color: Color(0xFFF5EDF9)))),
        if (trailing) const Icon(LucideIcons.chevronRight,
          size: 18, color: Color(0xFF9F91AB)),
      ]),
    ),
  );

  Widget _mobileQuickAction(String title, IconData icon,
      VoidCallback action) => Expanded(child: GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: action,
    child: Container(
      height: 92,
      decoration: BoxDecoration(
        color: const Color(0x554D3B55),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 25, color: const Color(0xFFF5EDF9)),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600,
            color: Color(0xFFF5EDF9))),
        ]),
    ),
  ));

  Widget _mobilePanelBody() => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) => Padding(
      padding: EdgeInsets.fromLTRB(
        20, 15, 20, MediaQuery.paddingOf(context).bottom + 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AppleCover(
              artist: widget.track.artist,
              name: widget.track.title,
              album: widget.track.album,
              fallbackUrl: widget.track.artworkUrl,
              size: 68,
              radius: 11,
            ),
            const SizedBox(width: 15),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.track.title, maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF9F3FC))),
                const SizedBox(height: 5),
                Text(widget.track.artist, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15,
                    color: Color(0xFFCABFCE))),
                if (widget.track.album?.isNotEmpty == true) ...[
                  const SizedBox(height: 3),
                  Text(widget.track.album!, maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13,
                      color: Color(0xFFAA9DAF))),
                ],
                const SizedBox(height: 7),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0x554F4258),
                    borderRadius: BorderRadius.circular(12)),
                  child: Text(widget.track.sourceName,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11,
                      color: Color(0xFFCFC4D3))),
                ),
              ],
            )),
          ]),
          const SizedBox(height: 26),
          Row(children: [
            _mobileQuickAction('Share', LucideIcons.share,
              () {
                final track = widget.track;
                widget.dismiss();
                OrchidShare.song(track, context: context).catchError((Object error) {
                  debugPrint('[Orchid Share] Song share failed: $error');
                });
              }),
            const SizedBox(width: 10),
            _mobileQuickAction('Queue', LucideIcons.listPlus,
              () {
                widget.player.addToQueue(widget.track);
                widget.dismiss();
              }),
            const SizedBox(width: 10),
            _mobileQuickAction('Playlist', LucideIcons.listMusic,
              _openPlaylistSubmenu),
          ]),
          const SizedBox(height: 22),
          if (_showMobilePlaylists) ...[
            _mobileRow('Back to actions', LucideIcons.arrowLeft,
              () => setState(() => _showMobilePlaylists = false)),
            for (final playlist in widget.library.visiblePlaylists)
              _mobileRow(playlist.name,
                widget.library.contains(playlist, _saved)
                    ? LucideIcons.check : LucideIcons.plus,
                () => _addTo(playlist)),
            _mobileRow('New playlist', LucideIcons.plus,
              () => setState(() {
                _showMobilePlaylists = false;
                _creating = true;
              })),
          ] else ...[
            _mobileRow('Play', LucideIcons.play, _playNow),
            _mobileRow('Play Next', LucideIcons.listPlus, () {
              widget.player.addNextToQueue(widget.track);
              widget.dismiss();
            }),
            _mobileRow(widget.library.isFavorite(_saved)
                ? 'Remove from Favorites' : 'Add to Favorites',
              LucideIcons.heart, () {
                widget.library.toggleFavorite(_saved);
                widget.dismiss();
              }),
            _mobileRow(widget.library.isInLibrary(_saved)
                ? 'Remove from Library' : 'Add to Library',
              LucideIcons.library, () {
                if (widget.library.isInLibrary(_saved)) {
                  widget.library.removeFromLibrary(_saved);
                } else {
                  widget.library.addToLibrary(_saved);
                }
                widget.dismiss();
              }),
            if (widget.playlist != null)
              _mobileRow('Remove from Playlist', LucideIcons.x, () {
                widget.library.removeFromPlaylist(widget.playlist!, _saved);
                widget.dismiss();
              }),
            _mobileDivider(),
            _mobileSection('Playback'),
            _mobileRow('View Song & Lyrics', LucideIcons.music2,
              _openSongDetails, trailing: true),
            _mobileRow('Find Playback Sources', LucideIcons.search,
              _openSongDetails, trailing: true),
            _mobileDivider(),
            _mobileSection('Explore'),
            _mobileRow('Go to Artist', LucideIcons.user, () {
              openArtistPage(context,
                artist: widget.track.artist,
                player: widget.player,
                addonService: widget.addonService ?? AddonService(),
                addons: widget.addons,
                library: widget.library);
              widget.dismiss();
            }, trailing: true),
            if (widget.track.album?.isNotEmpty == true)
              _mobileRow('Go to Album', LucideIcons.disc, () {
                openAlbumPage(context,
                  artist: widget.track.artist,
                  album: widget.track.album!,
                  player: widget.player,
                  addonService: widget.addonService ?? AddonService(),
                  addons: widget.addons,
                  library: widget.library);
                widget.dismiss();
              }, trailing: true),
            _mobileRow('Start Radio', LucideIcons.radio,
              _startSongRadio),
          ],
          if (_error != null) Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 18, vertical: 8),
            child: Text(_error!, style: const TextStyle(
              color: Color(0xFFFFA5A5), fontSize: 12)),
          ),
          if (_creating) Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 8),
            child: Row(children: [
              Expanded(child: TextField(
                controller: _name,
                placeholder: const Text('Playlist name'),
                onSubmitted: (_) => _create(),
              )),
              const SizedBox(width: 8),
              IconButton.ghost(
                onPressed: _create,
                icon: const Icon(LucideIcons.check),
              ),
            ]),
          ),
        ],
      ),
    ),
  );

  Widget _panelBody() => Padding(
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
          if (widget.showViewSong)
          _action('View Song', LucideIcons.info, () {
            showSongDetailDrawer(context,
              player: widget.player,
              addonService: widget.addonService ?? AddonService(),
              addons: widget.addons,
              library: widget.library,
              title: widget.track.title,
              artist: widget.track.artist,
              album: widget.track.album,
              artworkUrl: widget.track.artworkUrl,
              track: widget.track,
            );
            widget.dismiss();
          }),
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
          _action('Share Song', LucideIcons.share, () {
            final track = widget.track;
            widget.dismiss();
            OrchidShare.song(track, context: context).catchError((Object error) {
              debugPrint('[Orchid Share] Song share failed: $error');
            });
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
          if (widget.playlist != null)
            _action('Remove from this playlist', LucideIcons.x, () {
              widget.library.removeFromPlaylist(widget.playlist!, _saved);
              widget.dismiss();
            }),
          const Divider(),
          if (_showMobilePlaylists) ...[
            _action('Back to actions', LucideIcons.arrowLeft,
              () => setState(() => _showMobilePlaylists = false)),
            for (final playlist in widget.library.visiblePlaylists)
              _action(playlist.name,
                widget.library.contains(playlist, _saved)
                  ? LucideIcons.check : LucideIcons.plus,
                () => _addTo(playlist)),
            _action('New playlist', LucideIcons.plus, () =>
              setState(() {
                _showMobilePlaylists = false;
                _creating = true;
              })),
          ] else
            _action('Add to playlist', LucideIcons.listPlus,
              _openPlaylistSubmenu),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(_error!, maxLines: 3,
                overflow: TextOverflow.ellipsis).small(),
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
          
        ],
        ),
      ),
  );
}
