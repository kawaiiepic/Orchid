import 'dart:async';
import 'package:flutter/widgets.dart' as fw;
import 'package:flutter/services.dart' show TextEditingValue;
import '../services/spotify_service.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../widgets/orchid_hover_zoom.dart';
import '../widgets/orchid_adaptive_controls.dart';

import '../models/addon.dart';
import '../services/addon_service.dart';
import '../services/music_library.dart';
import '../services/orchid_account.dart';
import '../services/player_service.dart';
import '../widgets/apple_cover.dart';
import '../widgets/artist_artwork.dart';
import 'music_detail_pages.dart';
import 'song_detail_screen.dart';
import '../widgets/orchid_style.dart';
import '../widgets/song_context_menu.dart';
import '../widgets/track_duration.dart';
import '../widgets/orchid_hover_menu.dart';

class LibraryScreen extends StatefulWidget {
  final Widget header;
  final MusicLibrary library;
  final OrchidAccount account;
  final PlayerService player;
  final AddonService addonService;
  final List<InstalledAddon> addons;
  final VoidCallback openExplore;
  final bool playlistsOnly;
  final String? selectedPlaylistId;
  final ValueChanged<String?>? onPlaylistSelected;
  const LibraryScreen({
    super.key,
    required this.header,
    required this.library,
    required this.account,
    required this.player,
    required this.addonService,
    required this.addons,
    required this.openExplore,
    this.playlistsOnly = false,
    this.selectedPlaylistId,
    this.onPlaylistSelected,
  });
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _queryController = TextEditingController();
  final _librarySearchFocus = fw.FocusNode();
  String _view = 'Songs';
  String? _mobileSection;
  String? _mobilePlaylistId;
  bool _mobileSelecting = false;
  final Set<String> _mobileSelected = {};

  String _songSelectionKey(SavedSong song) =>
      '${song.artist.trim().toLowerCase()}|${song.title.trim().toLowerCase()}|${song.album?.trim().toLowerCase() ?? ''}';

  void _toggleMobileSelection(String key) => setState(() {
    if (!_mobileSelected.add(key)) _mobileSelected.remove(key);
  });

  void _leaveMobileSelection() => setState(() {
    _mobileSelecting = false;
    _mobileSelected.clear();
  });

  void _mobileBack() {
    if (_mobileSelecting) {
      _leaveMobileSelection();
    } else if (_selectedAlbumKey != null) {
      setState(() => _selectedAlbumKey = null);
    } else if (_selectedArtist != null) {
      setState(() => _selectedArtist = null);
    } else if (_mobilePlaylistId != null) {
      _selectMobilePlaylist(null);
    } else if (_playlistFolderId != null) {
      setState(() => _playlistFolderId = null);
    } else {
      setState(() => _mobileSection = null);
    }
  }

  void _applyMobileSelection(Map<String, List<SavedSong>> albums) {
    if (_mobileSelected.isEmpty) return;
    if (_mobileSection == 'Artists') {
      final artists = _mobileSelected.toList();
      for (final artist in artists) {
        if (!widget.library.isArtistSaved(artist)) {
          widget.library.toggleArtistSaved(artist);
        }
      }
    } else {
      final songs = _mobileSection == 'Albums'
          ? <SavedSong>[
              for (final key in _mobileSelected) ...?albums[key],
            ]
          : widget.library.librarySongs
              .where((song) => _mobileSelected.contains(_songSelectionKey(song)))
              .toList();
      for (final song in songs) {
        widget.player.addToQueue(_track(song));
      }
    }
    _leaveMobileSelection();
  }

  Widget _mobileTopButton({
    required Widget child,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Container(
      height: 46,
      constraints: const BoxConstraints(minWidth: 46),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0x554A365D),
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: const Color(0x225D4F69)),
      ),
      child: child,
    ),
  );

  Widget _mobilePageHeader(String title, {
    required VoidCallback action,
    required Widget actionChild,
  }) => SizedBox(
    height: 62,
    child: Row(children: [
      SizedBox(
        width: 76,
        child: Align(
          alignment: Alignment.centerLeft,
          child: OrchidBackButton(onPressed: _mobileBack),
        ),
      ),
      Expanded(child: Text(title,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFFF8F1FF),
          fontSize: 19, fontWeight: FontWeight.w700,
        ))),
      SizedBox(
        width: 76,
        child: Align(
          alignment: Alignment.centerRight,
          child: _mobileTopButton(
            onTap: action,
            child: actionChild,
          ),
        ),
      ),
    ]),
  );

  Widget _mobileSelectionBar(Map<String, List<SavedSong>> albums) {
    if (!_mobileSelecting) return const SizedBox.shrink();
    final count = _mobileSelected.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(children: [
        Expanded(child: Text('$count selected',
          style: const TextStyle(color: Color(0xFFB8A9C6),
            fontSize: 13))),
        OrchidAdaptiveControls.button(
          onPressed: count == 0 ? null : () => _applyMobileSelection(albums),
          prominent: true,
          child: Text(_mobileSection == 'Artists'
              ? 'Follow selected' : 'Add to queue'),
        ),
      ]),
    );
  }


  void _openMobileSection(String section) => setState(() {
    _mobileSection = section;
    _mobilePlaylistId = null;
    _mobileSelecting = false;
    _mobileSelected.clear();
    _selectedAlbumKey = null;
    _selectedArtist = null;
    _view = section == 'Playlists' ? 'Songs' : section;
    _queryController.clear();
  });

  void _selectMobilePlaylist(String? id) => setState(() {
    _mobilePlaylistId = id;
  });

  Widget _mobileLibraryLanding(BuildContext context) {
    final songs = widget.library.librarySongs;
    final artists = <String>{
      ...songs.map((song) => song.artist.trim().toLowerCase()),
      ...widget.library.savedArtists.keys.map((name) => name.trim().toLowerCase()),
    }..remove('');
    final albums = _libraryAlbums();
    final playlists = widget.library.visiblePlaylists;
    final entries = <({String title, String count, IconData icon})>[
      (title: 'Artists', count: '${artists.length}', icon: LucideIcons.users),
      (title: 'Songs', count: '${songs.length}', icon: LucideIcons.music2),
      (title: 'Albums', count: '${albums.length}', icon: LucideIcons.library),
      (title: 'Playlists', count: '${playlists.length}', icon: LucideIcons.listMusic),
    ];
    return ListView(
      padding: EdgeInsets.fromLTRB(20,
        24 + MediaQuery.paddingOf(context).top, 20,
        OrchidStyle.iosDockClearance(context) + 24),
      children: [
        const Text('Library', style: TextStyle(
          fontSize: 34, fontWeight: FontWeight.w700,
          color: Color(0xFFF9F4FF),
        )),
        const SizedBox(height: 24),
        for (final entry in entries)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openMobileSection(entry.title),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 6),
              decoration: const BoxDecoration(border: Border(
                bottom: BorderSide(color: Color(0x335F496D)),
              )),
              child: Row(children: [
                Icon(entry.icon, size: 24, color: OrchidStyle.pink),
                const SizedBox(width: 18),
                Expanded(child: Text(entry.title, style: const TextStyle(
                  fontSize: 18, color: Color(0xFFF6EDFF),
                  fontWeight: FontWeight.w500,
                ))),
                Text(entry.count, style: const TextStyle(
                  fontSize: 14, color: Color(0xFFB3A5C1),
                )),
                const SizedBox(width: 12),
                const Icon(LucideIcons.chevronRight, size: 20,
                  color: Color(0xFFB3A5C1)),
              ]),
            ),
          ),
      ],
    );
  }

  String? _selectedAlbumKey;
  String? _selectedArtist;
  bool _followingOnly = false;
  String _playlistSort = 'Recents';
  String _playlistSize = 'M';
  String? _playlistFolderId;
  bool _reorderingPlaylists = false;
  bool _importingPlaylist = false;
  OverlayEntry? _mobilePlaylistAddMenu;

  void _closeMobilePlaylistAddMenu() {
    _mobilePlaylistAddMenu?.remove();
    _mobilePlaylistAddMenu?.dispose();
    _mobilePlaylistAddMenu = null;
  }

  void _showMobilePlaylistAddMenu() {
    _closeMobilePlaylistAddMenu();
    final screen = MediaQuery.sizeOf(context);
    final top = MediaQuery.paddingOf(context).top + 100;
    const menuWidth = 230.0;
    final right = 18.0;
    final actions = <OrchidHoverAction>[
      OrchidHoverAction('New playlist', LucideIcons.listMusic, _newPlaylist),
      OrchidHoverAction('New folder', LucideIcons.folderPlus, _newFolder),
      if (!_importingPlaylist)
        OrchidHoverAction('Import Spotify playlist',
          LucideIcons.download, _spotifyImport),
    ];
    _mobilePlaylistAddMenu = OverlayEntry(builder: (context) => Stack(
      children: [
        Positioned.fill(child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _closeMobilePlaylistAddMenu,
        )),
        Positioned(
          top: top.clamp(8.0, screen.height - 174.0).toDouble(),
          right: right,
          width: menuWidth,
          child: OrchidGlassPanel(
            radius: 16,
            transparentOnDesktop: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final action in actions)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _closeMobilePlaylistAddMenu();
                      action.onSelected();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15, vertical: 13),
                      child: Row(children: [
                        Icon(action.icon, size: 18,
                          color: OrchidStyle.pink),
                        const SizedBox(width: 12),
                        Expanded(child: Text(action.label,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFFF7EDFF),
                          ))),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ],
    ));
    Overlay.of(context).insert(_mobilePlaylistAddMenu!);
  }

  bool _mobilePlaylistListMode = false;

  Future<String?> _askName(String title, {String hint = 'Name'}) {
    final controller = TextEditingController();
    final result = Completer<String?>();
    late OverlayEntry entry;
    void finish(String? name) {
      if (result.isCompleted) return;
      entry.remove();
      entry.dispose();
      controller.dispose();
      result.complete(name);
    }
    entry = OverlayEntry(builder: (context) => Stack(children: [
      Positioned.fill(child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => finish(null),
        child: const ColoredBox(color: Color(0x99000000)),
      )),
      Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: OrchidGlassPanel(
          radius: 18, transparentOnDesktop: false,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title).large().semiBold(),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                placeholder: Text(hint),
                onSubmitted: (value) => finish(value.trim().isEmpty
                    ? null : value.trim()),
              ),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                OrchidAdaptiveControls.button(
                  onPressed: () => finish(null),
                  child: const Text('Cancel')),
                const SizedBox(width: 8),
                OrchidAdaptiveControls.button(
                  prominent: true,
                  onPressed: () => finish(controller.text.trim().isEmpty
                    ? null : controller.text.trim()),
                  child: const Text('Continue')),
              ]),
            ]),
          ),
        ),
      )),
    ]));
    Overlay.of(context).insert(entry);
    return result.future;
  }

  Future<void> _showPlaylistError(Object error) async {
    final result = Completer<void>();
    late OverlayEntry entry;
    void close() {
      if (result.isCompleted) return;
      entry.remove();
      entry.dispose();
      result.complete();
    }
    entry = OverlayEntry(builder: (context) => Stack(children: [
      Positioned.fill(child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: close,
        child: const ColoredBox(color: Color(0x99000000)),
      )),
      Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: OrchidGlassPanel(
          radius: 18, transparentOnDesktop: false,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Spotify import unavailable').large().semiBold(),
              const SizedBox(height: 12),
              Text('$error').small(),
              const SizedBox(height: 18),
              Align(alignment: Alignment.centerRight,
                child: OrchidAdaptiveControls.button(
                  prominent: true,
                  onPressed: close,
                  child: const Text('OK')),
              ),
            ]),
          ),
        ),
      )),
    ]));
    Overlay.of(context).insert(entry);
    await result.future;
  }

  Future<void> _newPlaylist() async {
    final name = await _askName('New playlist');
    if (name == null || !mounted) return;
    final playlist = await widget.library.createPlaylist(name);
    if (_playlistFolderId != null) {
      await widget.library.movePlaylistToFolder(playlist, _playlistFolderId);
    }
  }

  Future<void> _newFolder() async {
    // Playlist folders are flat; newly created folders live at the root.
    final name = await _askName('New folder');
    if (name == null || !mounted) return;
    await widget.library.createPlaylistFolder(name);
    if (mounted) setState(() => _playlistFolderId = null);
  }

  Future<void> _spotifyImport() async {
    final link = await _askName('Import Spotify playlist',
      hint: 'https://open.spotify.com/playlist/...');
    if (link == null || !mounted) return;
    setState(() => _importingPlaylist = true);
    try {
      final imported = await SpotifyService().importPublicPlaylist(link);
      if (!mounted) return;
      await widget.library.importPlaylist(
        imported.name, imported.songs,
        creator: imported.creator, folderId: _playlistFolderId);
    } catch (error) {
      if (!mounted) return;
      await _showPlaylistError(error);
    } finally {
      if (mounted) setState(() => _importingPlaylist = false);
    }
  }

  @override
  void dispose() {
    _closeMobilePlaylistAddMenu();
    _queryController.dispose();
    _librarySearchFocus.dispose();
    super.dispose();
  }

  void _openSong(SavedSong song) {
    showSongDetailDrawer(context,
      player:widget.player, addonService:widget.addonService,
      addons:widget.addons, library:widget.library,
      title:song.title, artist:song.artist,
      album:song.album, artworkUrl:song.artwork,
    );
  }

  Future<void> _playCollection(List<SavedSong> songs) async {
    if (songs.isEmpty) return;
    widget.player.setAddons(widget.addons);
    // Source-independent tracks: PlayerService looks for a matching stream
    // through whichever addons are currently installed.
    final queue = songs.map((song) => TrackResult(
      id: song.key,
      title: song.title,
      artist: song.artist,
      album: song.album,
      artworkUrl: song.artwork,
      duration: song.duration,
      sourceId: 'orchid-library',
      sourceName: 'Library',
    )).toList();
    try {
      await widget.player.playTrack(queue.first, fromQueue: queue);
    } catch (e) {
      debugPrint('[Orchid Library] Playlist playback failed: $e');
    }
  }

  TrackResult _track(SavedSong song) => TrackResult(
    id: song.key, title: song.title, artist: song.artist,
    album: song.album, artworkUrl: song.artwork, duration: song.duration,
    sourceId: 'orchid-library', sourceName: 'Library',
  );

  List<SavedSong> _filtered(List<SavedSong> songs) {
    final query = _queryController.text.trim().toLowerCase();
    final filtered = songs.where((song) =>
      query.isEmpty ||
      song.title.toLowerCase().contains(query) ||
      song.artist.toLowerCase().contains(query) ||
      (song.album ?? '').toLowerCase().contains(query)).toList();
    if (_view == 'Songs') {
      filtered.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    } else if (_view == 'Albums') {
      filtered.sort((a, b) {
        final primary = (a.album ?? '').toLowerCase().compareTo((b.album ?? '').toLowerCase());
        return primary != 0 ? primary : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    } else {
      filtered.sort((a, b) {
        final primary = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
        return primary != 0 ? primary : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    }
    return filtered;
  }

  Widget _songRow(SavedSong song, int number, {MusicPlaylist? playlist}) {
    var hovered = false;
    return StatefulBuilder(builder: (context, updateHover) => MouseRegion(
      onEnter: (_) => updateHover(() => hovered = true),
      onExit: (_) => updateHover(() => hovered = false),
      child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: OrchidHoverSurface(
        child: SongContextMenu(
        track: _track(song), player: widget.player,
        library: widget.library, addonService: widget.addonService, addons: widget.addons, playlist: playlist,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (MediaQuery.sizeOf(context).width < 850 &&
                _mobileSelecting && _mobileSection == 'Songs') {
              _toggleMobileSelection(_songSelectionKey(song));
              return;
            }
            widget.player.setAddons(widget.addons);
            widget.player.playTrack(_track(song)).catchError((Object e) {
              debugPrint('[Orchid Library] Playback failed: $e');
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Row(children: [
              SizedBox(width: 30, child: Center(
                child: MediaQuery.sizeOf(context).width < 850 &&
                    _mobileSelecting && _mobileSection == 'Songs'
                  ? Icon(_mobileSelected.contains(_songSelectionKey(song))
                        ? LucideIcons.check
                        : LucideIcons.circle,
                      size: 20, color: OrchidStyle.pink)
                  : hovered
                    ? const Icon(LucideIcons.play, size: 16)
                    : Text('$number').small().muted(),
              )),
              const SizedBox(width: 10),
              AppleCover(artist: song.artist, name: song.title,
                album: song.album, fallbackUrl: song.artwork,
                size: 42, radius: 7),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.title, maxLines: 1,
                    overflow: TextOverflow.ellipsis).semiBold(),
                  Text(
                    MediaQuery.sizeOf(context).width < 720 &&
                        song.album?.isNotEmpty == true
                      ? '${song.artist} · ${song.album}'
                      : song.artist,
                    maxLines: 1, overflow: TextOverflow.ellipsis).small().muted(),
                ],
              )),
              if (MediaQuery.sizeOf(context).width >= 720) ...[
                const SizedBox(width: 14),
                SizedBox(width: 180, child: Text(
                  song.album?.isNotEmpty == true ? song.album! : 'Unknown album',
                  maxLines: 1, overflow: TextOverflow.ellipsis).small().muted()),
                const SizedBox(width: 14),
              ],
              SizedBox(width: 64, child: Text(
                trackDurationLabel(song.duration) ?? '—',
                textAlign: TextAlign.end).small().muted()),
              const SizedBox(width: 38),
            ]),
          ),
        ),
        ),
      ),
    )));
  }

  Widget _songList(List<SavedSong> songs, {MusicPlaylist? playlist}) {
    if (songs.isEmpty) return const Text('No songs found.').muted();
    final items = _filtered(songs);
    if (items.isEmpty) return const Text('No matching songs.').muted();
    if (_view == 'Songs') {
      return Column(children: [
        for (var i = 0; i < items.length; i++)
          _songRow(items[i], i + 1, playlist: playlist),
      ]);
    }
    final groups = <String, List<SavedSong>>{};
    for (final song in items) {
      final key = _view == 'Albums'
        ? (song.album?.trim().isNotEmpty == true ? song.album!.trim() : 'Unknown album')
        : song.artist;
      groups.putIfAbsent(key, () => []).add(song);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final entry in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 24, 0, 10),
          child: Text(entry.key).large().semiBold(),
        ),
        for (final song in entry.value)
          _songRow(song, items.indexOf(song) + 1, playlist: playlist),
      ],
    ]);
  }

  Widget _libraryTools() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      OrchidGlassPanel(
        radius: 14,
        transparentOnDesktop: false,
        child: SizedBox(
          height: 46,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              const Icon(LucideIcons.search,
                size: 18, color: Color(0xFFCDBAE2)),
              const SizedBox(width: 12),
              Expanded(
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _queryController,
                  builder: (context, value, _) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      if (value.text.isEmpty)
                        const IgnorePointer(
                          child: Text('Search your library…',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFFB8A9C6),
                            ),
                          ),
                        ),
                      fw.EditableText(
                        controller: _queryController,
                        focusNode: _librarySearchFocus,
                        style: const TextStyle(
                          color: Color(0xFFF7F0FF),
                          fontSize: 14,
                          height: 1.25,
                        ),
                        cursorColor: OrchidStyle.lilac,
                        backgroundCursorColor: OrchidStyle.lilac,
                        selectionColor: const Color(0x665F4391),
                        maxLines: 1,
                        keyboardType: fw.TextInputType.text,
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _queryController,
                builder: (context, value, _) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : GestureDetector(
                      onTap: () {
                        _queryController.clear();
                        setState(() {});
                        _librarySearchFocus.requestFocus();
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(LucideIcons.x,
                          size: 16, color: Color(0xFFBEACC9)),
                      ),
                    ),
              ),
            ]),
          ),
        ),
      ),
      if (MediaQuery.sizeOf(context).width >= 850) ...[
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final view in const ['Songs', 'Albums', 'Artists'])
            OrchidAdaptiveControls.button(
              prominent: _view == view,
              onPressed: () => setState(() => _view = view),
              child: Text(view),
            ),
        ]),
      ],
    ],
  );

  Widget _playlistArtwork(List<SavedSong> songs, {bool favorite = false}) {
    final covers = songs.reversed.take(4).toList();
    if (covers.isEmpty) {
      return ColoredBox(
        color: const Color(0x4D4D3664),
        child: Center(child: Icon(
          favorite ? LucideIcons.heart : LucideIcons.listMusic,
          size: 42, color: OrchidStyle.lilac)),
      );
    }
    Widget image(SavedSong song, double size) => AppleCover(
      artist: song.artist, name: song.title, album: song.album,
      fallbackUrl: song.artwork, size: size, radius: 0);
    return LayoutBuilder(builder: (context, bounds) {
      final size = bounds.maxWidth;
      if (covers.length == 1) return image(covers.first, size);
      if (covers.length == 2) {
        return Row(children: [
          for (final song in covers)
            Expanded(child: SizedBox.expand(child: image(song, size / 2))),
        ]);
      }
      return Column(children: [
        for (var row = 0; row < 2; row++)
          Expanded(child: Row(children: [
            for (var col = 0; col < 2; col++)
              Expanded(child: row * 2 + col < covers.length
                ? image(covers[row * 2 + col], size / 2)
                : const ColoredBox(color: Color(0x55432F57))),
          ])),
      ]);
    });
  }

  Widget _playlistButton(String name, List<SavedSong> songs,
      VoidCallback action, {bool favorite = false, MusicPlaylist? playlist}) =>
    OrchidHoverMenu(
      actions: [
        OrchidHoverAction('Open playlist', LucideIcons.listMusic, action),
        if (playlist != null)
          OrchidHoverAction(widget.library.isPlaylistSaved(playlist)
            ? 'Remove from Library' : 'Add to Library',
            LucideIcons.library, () => widget.library.togglePlaylistSaved(playlist)),
        if (playlist != null)
          OrchidHoverAction(playlist.pinned ? 'Unpin from Home' : 'Pin to Home',
            LucideIcons.pin, () => widget.library.setPlaylistPinned(
              playlist, !playlist.pinned)),
        if (playlist != null && playlist.folderId != null)
          OrchidHoverAction('Remove from folder', LucideIcons.folderMinus,
            () => widget.library.movePlaylistToFolder(playlist, null)),
        if (playlist != null)
          for (final folder in widget.library.playlistFolders)
            OrchidHoverAction('Move to ${folder.name}', LucideIcons.folder,
              () => widget.library.movePlaylistToFolder(playlist, folder.id)),
      ],
      child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: action,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: OrchidHoverZoom(
                child: _playlistArtwork(songs, favorite: favorite))),
          ),
          const SizedBox(height: 8),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis).semiBold(),
          Text('${songs.length} songs', maxLines: 1,
            overflow: TextOverflow.ellipsis).small().muted(),
        ]),
      ),
    ),
  );


  /// Album identity includes the artist so same-titled albums stay separate.
  String _albumKey(SavedSong song) =>
      '${song.artist.trim().toLowerCase()}|'
      '${(song.album ?? '').trim().toLowerCase()}';

  Map<String, List<SavedSong>> _libraryAlbums() {
    final groups = <String, List<SavedSong>>{};
    for (final song in widget.library.librarySongs) {
      if (song.album?.trim().isNotEmpty != true) continue;
      groups.putIfAbsent(_albumKey(song), () => []).add(song);
    }
    return groups;
  }

  Widget _albumsGrid(Map<String, List<SavedSong>> albums) {
    final query = _selectedArtist == null
        ? _queryController.text.trim().toLowerCase() : '';
    final entries = albums.entries.where((entry) {
      final song = entry.value.first;
      return query.isEmpty ||
          song.album!.toLowerCase().contains(query) ||
          song.artist.toLowerCase().contains(query) ||
          entry.value.any((track) => track.title.toLowerCase().contains(query));
    }).toList()
      ..sort((a, b) {
        final first = a.value.first;
        final second = b.value.first;
        final compare = first.album!.toLowerCase().compareTo(
          second.album!.toLowerCase());
        return compare != 0 ? compare :
          first.artist.toLowerCase().compareTo(second.artist.toLowerCase());
      });

    if (entries.isEmpty) return const Text('No saved albums found.').muted();
    return LayoutBuilder(builder: (context, constraints) {
      const gap = 12.0;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: entries.length,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 210,
          crossAxisSpacing: gap,
          mainAxisSpacing: 18,
          childAspectRatio: .78,
        ),
        itemBuilder: (context, index) {
          final entry = entries[index];
          final song = entry.value.first;
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (MediaQuery.sizeOf(context).width < 850 &&
                    _mobileSelecting && _mobileSection == 'Albums') {
                  _toggleMobileSelection(entry.key);
                } else {
                  setState(() => _selectedAlbumKey = entry.key);
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Stack(children: [
                    Positioned.fill(child: LayoutBuilder(builder: (context, size) =>
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AppleCover(
                          artist: song.artist,
                          name: song.album!,
                          isAlbum: true,
                          fallbackUrl: song.artwork,
                          size: size.maxWidth,
                          radius: 0, zoomOnHover: true),
                      ),
                    )),
                    if (_mobileSelecting && _mobileSection == 'Albums')
                      Positioned(top: 8, right: 8,
                        child: Icon(_mobileSelected.contains(entry.key)
                            ? LucideIcons.check : LucideIcons.circle,
                          color: OrchidStyle.pink, size: 23)),
                  ])),
                  const SizedBox(height: 8),
                  Text(song.album!, maxLines: 1,
                    overflow: TextOverflow.ellipsis).semiBold(),
                  const SizedBox(height: 3),
                  Text(song.artist, maxLines: 1,
                    overflow: TextOverflow.ellipsis).small().muted(),
                ],
              ),
            ),
          );
        },
      );
    });
  }

  Widget _savedAlbumDetail(List<SavedSong> songs) {
    final album = songs.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (MediaQuery.sizeOf(context).width >= 850)
          Align(alignment: Alignment.centerLeft,
            child: IconButton.ghost(
              onPressed: () => setState(() => _selectedAlbumKey = null),
              icon: const Icon(LucideIcons.arrowLeft))),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, bounds) {
          final artwork = SizedBox(
            width: 168, height: 168,
            child: ClipRRect(borderRadius: BorderRadius.circular(13),
              child: AppleCover(
                artist: album.artist, name: album.album!,
                isAlbum: true, fallbackUrl: album.artwork,
                size: 168, radius: 0)),
          );
          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Album').small().muted(),
              const SizedBox(height: 6),
              Text(album.album!).x2Large().semiBold(),
              const SizedBox(height: 7),
              Text(album.artist).muted(),
              const SizedBox(height: 4),
              Text('${songs.length} saved ${songs.length == 1 ? 'song' : 'songs'}')
                .small().muted(),
              const SizedBox(height: 16),
              OrchidAdaptiveControls.button(
                prominent: true,
                onPressed: () => _playCollection(songs),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(LucideIcons.play, size: 17),
                  SizedBox(width: 8),
                  Text('Play all'),
                ]),
              ),
            ],
          );
          if (bounds.maxWidth < 530) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [artwork, const SizedBox(height: 18), info]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [artwork, const SizedBox(width: 22), Expanded(child: info)]);
        }),
        const SizedBox(height: 28),
        for (var i = 0; i < songs.length; i++) _songRow(songs[i], i + 1),
      ],
    );
  }


  Widget _savedArtistDetail(String artist, List<SavedSong> songs,
      Map<String, List<SavedSong>> albums) {
    final art = widget.library.savedArtists[artist];
    final artistAlbums = <String, List<SavedSong>>{
      for (final entry in albums.entries)
        if (entry.value.first.artist.trim().toLowerCase() ==
            artist.trim().toLowerCase()) entry.key: entry.value,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (MediaQuery.sizeOf(context).width >= 850)
          Align(alignment: Alignment.centerLeft,
            child: IconButton.ghost(
              onPressed: () => setState(() {
                _selectedArtist = null;
                _selectedAlbumKey = null;
              }),
              icon: const Icon(LucideIcons.arrowLeft))),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, bounds) {
          final artwork = ArtistArtwork(
            artist: artist, fallbackUrl: art, size: 168, radius: 84);
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Artist').small().muted(),
              const SizedBox(height: 6),
              Text(artist).x2Large().semiBold(),
              const SizedBox(height: 7),
              Text('${artistAlbums.length} saved albums · '
                '${songs.length} saved ${songs.length == 1 ? 'song' : 'songs'}')
                  .small().muted(),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OrchidAdaptiveControls.button(
                  prominent: true,
                  onPressed: songs.isEmpty ? null : () => _playCollection(songs),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(LucideIcons.play, size: 17),
                    SizedBox(width: 8), Text('Play all'),
                  ]),
                ),
                OrchidAdaptiveControls.button(
                  onPressed: () => openArtistPage(context,
                    artist: artist, artwork: art, account: widget.account,
                    player: widget.player, addonService: widget.addonService,
                    addons: widget.addons, library: widget.library),
                  child: const Text('View full discography'),
                ),
              ]),
            ],
          );
          if (bounds.maxWidth < 530) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [artwork, const SizedBox(height: 18), details]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            artwork, const SizedBox(width: 22), Expanded(child: details),
          ]);
        }),
        const SizedBox(height: 30),
        const OrchidSectionHeader(title: 'Saved Albums'),
        const SizedBox(height: 14),
        _albumsGrid(artistAlbums),
        const SizedBox(height: 28),
        const OrchidSectionHeader(title: 'Saved Songs'),
        const SizedBox(height: 12),
        if (songs.isEmpty)
          const Text('No songs from this artist in your library yet.').muted()
        else
          for (var i = 0; i < songs.length; i++)
            _songRow(songs[i], i + 1),
      ],
    );
  }

  Widget _savedArtistsGrid() {
    final query = _queryController.text.trim().toLowerCase();
    final allArtists = <String, String>{};
    if (!_followingOnly) {
      for (final song in widget.library.librarySongs) {
        final artist = song.artist.trim();
        if (artist.isNotEmpty) {
          allArtists.putIfAbsent(artist.toLowerCase(), () => artist);
        }
      }
    }
    for (final artist in widget.library.savedArtists.keys) {
      final name = artist.trim();
      if (name.isNotEmpty) {
        allArtists.putIfAbsent(name.toLowerCase(), () => name);
      }
    }
    final artists = allArtists.values
        .where((name) => name.toLowerCase().contains(query)).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      OrchidAdaptiveControls.button(
        prominent: _followingOnly,
        onPressed: () => setState(() => _followingOnly = !_followingOnly),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_followingOnly ? LucideIcons.check : LucideIcons.users, size: 16),
          const SizedBox(width: 8),
          const Text('Following only'),
        ]),
      ),
      const SizedBox(height: 16),
      if (artists.isEmpty)
        Text(_followingOnly ? 'No followed artists found.' :
          'No artists in your library yet.').muted()
      else
        LayoutBuilder(builder: (context, bounds) {
      final compact = MediaQuery.sizeOf(context).width < 850;
      final columns = (bounds.maxWidth / (compact ? 150 : 165))
          .floor().clamp(2, 7).toInt();
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: artists.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: compact ? 16 : 12,
          mainAxisSpacing: compact ? 24 : 18,
          childAspectRatio: compact ? .9 : .82),
        itemBuilder: (context, index) {
          final artist = artists[index];
          final savedSongCount = widget.library.librarySongs.where((song) =>
            song.artist.trim().toLowerCase() == artist.toLowerCase()).length;
          return OrchidHoverMenu(
            showHoverButton: false,
            actions: [OrchidHoverAction(
              widget.library.isArtistSaved(artist)
                  ? 'Unfollow artist' : 'Follow artist',
              LucideIcons.library,
              () => widget.library.toggleArtistSaved(artist))],
            child: GestureDetector(
              onTap: () {
                if (compact && _mobileSelecting && _mobileSection == 'Artists') {
                  _toggleMobileSelection(artist);
                } else {
                  setState(() {
                    _selectedArtist = artist;
                    _selectedAlbumKey = null;
                  });
                }
              },
              child: Column(children: [
                Expanded(child: LayoutBuilder(builder: (context, bounds) {
                  final available = bounds.maxWidth < bounds.maxHeight
                      ? bounds.maxWidth : bounds.maxHeight;
                  final diameter = compact ? available * 0.76 : available;
                  return Center(child: ClipOval(
                    child: ArtistArtwork(artist: artist, size: diameter,
                      radius: diameter / 2, zoomOnHover: true),
                  ));
                })),
                const SizedBox(height: 8),
                if (compact && _mobileSelecting && _mobileSection == 'Artists')
                  Icon(_mobileSelected.contains(artist)
                      ? LucideIcons.check : LucideIcons.circle,
                    size: 18, color: OrchidStyle.pink),
                Text(artist, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 12 : 14,
                    fontWeight: FontWeight.w600,
                  )),
                const SizedBox(height: 3),
                Text('${savedSongCount} ${savedSongCount == 1 ? 'song' : 'songs'}',
                  maxLines: 1, overflow: TextOverflow.ellipsis).small().muted(),
              ]),
            ),
          );
        },
      );
    }),
    ]);
  }

  List<MusicPlaylist> _sortedPlaylists(List<MusicPlaylist> playlists) {
    final result = playlists.where((p) =>
      _playlistFolderId == null || p.folderId == _playlistFolderId).toList();
    switch (_playlistSort) {
      case 'Recently Added':
        result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case 'Recents':
        result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case 'Alphabetical':
        result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case 'Creator':
        result.sort((a, b) {
          final byCreator = a.creator.toLowerCase().compareTo(b.creator.toLowerCase());
          return byCreator != 0 ? byCreator :
              a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      case 'Custom Order':
        break;
    }
    return result;
  }

  Widget _playlistFolderCard(PlaylistFolder folder, int count) =>
    OrchidHoverMenu(
      showHoverButton: false,
      actions: [
        OrchidHoverAction('Open folder', LucideIcons.folderOpen,
          () => setState(() => _playlistFolderId = folder.id)),
        OrchidHoverAction('Rename folder', LucideIcons.pencil, () async {
          final name = await _askName('Rename ${folder.name}');
          if (name != null) await widget.library.renamePlaylistFolder(folder, name);
        }),
        OrchidHoverAction('Delete folder', LucideIcons.trash2,
          () => widget.library.deletePlaylistFolder(folder)),
      ],
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _playlistFolderId = folder.id),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: OrchidHoverZoom(
                    child: ColoredBox(
                      color: const Color(0xFF362843),
                    child: Center(child: LayoutBuilder(
                      builder: (context, bounds) => Icon(
                        LucideIcons.folder,
                        size: (bounds.maxWidth * .44).clamp(26.0, 88.0),
                        color: OrchidStyle.lilac,
                      ),
                    )),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(folder.name, maxLines: 1,
                overflow: TextOverflow.ellipsis).semiBold(),
              Text('$count ${count == 1 ? 'playlist' : 'playlists'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis).small().muted(),
            ],
          ),
        ),
      ),
    );

  Widget _playlistsGrid(List<MusicPlaylist> playlists) {
    final filtered = _sortedPlaylists(playlists);
    final folders = _playlistFolderId == null
        ? widget.library.playlistFolders : <PlaylistFolder>[];
    // Fixed maximum tile widths make S and M visibly different even on
    // narrower desktop windows, unlike floor-based column counts.
    final tileWidth = switch (_playlistSize) {
      'S' => 112.0,
      'L' => 226.0,
      'XL' => 282.0,
      _ => 172.0,
    };
    return LayoutBuilder(builder: (context, bounds) {
      const gap = 12.0;
      if (_reorderingPlaylists && _playlistSort == 'Custom Order') {
        return fw.ReorderableList(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filtered.length,
          onReorder: (oldIndex, newIndex) {
            if (newIndex > oldIndex) newIndex--;
            if (oldIndex == newIndex) return;
            final moving = filtered[oldIndex];
            final reordered = [...filtered]..removeAt(oldIndex);
            reordered.insert(newIndex, moving);
            widget.library.applyPlaylistOrder(reordered);
          },
          itemBuilder: (context, index) {
            final p = filtered[index];
            return fw.ReorderableDragStartListener(
              key: fw.ValueKey(p.id),
              index: index,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  SizedBox(width: 48, height: 48,
                    child: _playlistArtwork(p.songs)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name).semiBold(),
                      Text('${p.songs.length} songs').small().muted(),
                    ])),
                  const Icon(LucideIcons.gripVertical),
                ]),
              ),
            );
          },
        );
      }
      // Wrap respects the requested size directly without stretching cards
      // to fill every column. Folders are first-class grid items.
      return Wrap(
        spacing: gap,
        runSpacing: 18,
        children: [
          for (final folder in folders)
            SizedBox(
              width: tileWidth,
              height: tileWidth + 50,
              child: _playlistFolderCard(folder, playlists
                .where((p) => p.folderId == folder.id).length),
            ),
          for (final playlist in filtered)
            SizedBox(
              width: tileWidth,
              height: tileWidth + 50,
              child: _playlistButton(playlist.name, playlist.songs,
                () => widget.playlistsOnly
                    ? widget.onPlaylistSelected?.call(playlist.id)
                    : _selectMobilePlaylist(playlist.id),
                playlist: playlist),
            ),
        ],
      );
    });
  }

  Widget _mobilePlaylistsContent(List<MusicPlaylist> playlists) {
    final sorted = _sortedPlaylists(playlists);
    final folders = _playlistFolderId == null
        ? widget.library.playlistFolders : <PlaylistFolder>[];
    final entries = <({PlaylistFolder? folder, MusicPlaylist? playlist})>[
      for (final folder in folders) (folder: folder, playlist: null),
      for (final playlist in sorted) (folder: null, playlist: playlist),
    ];

    Widget item(({PlaylistFolder? folder, MusicPlaylist? playlist}) entry) {
      final folder = entry.folder;
      if (folder != null) {
        return _playlistFolderCard(folder,
          playlists.where((playlist) => playlist.folderId == folder.id).length);
      }
      final playlist = entry.playlist!;
      return _playlistButton(playlist.name, playlist.songs,
        () => _selectMobilePlaylist(playlist.id), playlist: playlist);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_playlistFolderId == null) ...[
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _selectMobilePlaylist('favorites'),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0x553F3050),
              borderRadius: BorderRadius.circular(21),
              border: Border.all(color: const Color(0x225E4A6C)),
            ),
            child: Row(children: [
              SizedBox(width: 86, height: 86,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: _playlistArtwork(widget.library.favorites,
                    favorite: true),
                )),
              const SizedBox(width: 16),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Favorites', style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700,
                  )),
                  const SizedBox(height: 8),
                  Text('${widget.library.favorites.length} songs',
                    style: const TextStyle(fontSize: 13,
                      color: Color(0xFFBAACCA))),
                ],
              )),
              const Icon(LucideIcons.chevronRight, size: 21,
                color: Color(0xFFC1B2D0)),
            ]),
          ),
        ),
        const SizedBox(height: 30),
      ],
      Row(children: [
        const Text('Playlists', style: TextStyle(
          fontSize: 22, fontWeight: FontWeight.w700,
        )),
        const SizedBox(width: 9),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            color: const Color(0x554A385F),
          ),
          child: Text('${sorted.length}', style: const TextStyle(
            fontSize: 12, color: Color(0xFFBCAEC9),
          )),
        ),
        const Spacer(),
        OrchidHoverMenu(
          showHoverButton: false,
          openOnTap: true,
          actions: [
            for (final sort in const [
              'Recents', 'Recently Added', 'Alphabetical',
              'Creator', 'Custom Order',
            ])
              OrchidHoverAction(sort, LucideIcons.arrowDownUp,
                () => setState(() => _playlistSort = sort)),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(LucideIcons.arrowDownUp, size: 16,
                color: Color(0xFFC5B8D0)),
              const SizedBox(width: 6),
              Text(_playlistSort, style: const TextStyle(
                fontSize: 12, color: Color(0xFFC5B8D0))),
            ]),
          ),
        ),
        const SizedBox(width: 14),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() =>
            _mobilePlaylistListMode = !_mobilePlaylistListMode),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(_mobilePlaylistListMode
                ? LucideIcons.layoutGrid : LucideIcons.list,
              color: OrchidStyle.lilac, size: 20),
          ),
        ),
      ]),
      const SizedBox(height: 20),
      if (_mobilePlaylistListMode)
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (entry.folder != null) {
                  setState(() => _playlistFolderId = entry.folder!.id);
                } else if (entry.playlist != null) {
                  _selectMobilePlaylist(entry.playlist!.id);
                }
              },
              child: Row(children: [
                SizedBox(width: 66, height: 66,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: entry.playlist != null
                        ? _playlistArtwork(entry.playlist!.songs)
                        : const ColoredBox(
                            color: Color(0xFF40334C),
                            child: Icon(LucideIcons.folder,
                              color: OrchidStyle.lilac),
                          ),
                  )),
                const SizedBox(width: 13),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.playlist?.name ?? entry.folder!.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(entry.playlist != null
                      ? '${entry.playlist!.songs.length} songs'
                      : 'Folder',
                      style: const TextStyle(
                        fontSize: 12, color: Color(0xFFBCAEC9))),
                  ],
                )),
                const Icon(LucideIcons.chevronRight, size: 18,
                  color: Color(0xFFC1B2D0)),
              ]),
            ),
          )
      else
        LayoutBuilder(builder: (context, bounds) {
          const spacing = 16.0;
          final tileWidth = (bounds.maxWidth - spacing) / 2;
          return Wrap(
            spacing: spacing,
            runSpacing: 22,
            children: [
              for (final entry in entries)
                SizedBox(
                  width: tileWidth,
                  height: tileWidth + 48,
                  child: item(entry),
                ),
            ],
          );
        }),
    ]);
  }

  Widget _playlistsToolbar() {
    final folders = widget.library.playlistFolders;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OrchidHoverMenu(
            showHoverButton: false, openOnTap: true,
            actions: [
              for (final sort in const [
                'Recents', 'Recently Added', 'Alphabetical',
                'Creator', 'Custom Order',
              ])
                OrchidHoverAction(sort, LucideIcons.arrowDownUp,
                  () => setState(() {
                    _playlistSort = sort;
                    _reorderingPlaylists = false;
                  })),
            ],
            child: _playlistToolbarChip(LucideIcons.arrowDownUp, _playlistSort),
          ),
          if (_playlistSort == 'Custom Order')
            OrchidAdaptiveControls.button(
              prominent: _reorderingPlaylists,
              onPressed: () => setState(() =>
                _reorderingPlaylists = !_reorderingPlaylists),
              child: Text(_reorderingPlaylists ? 'Done' : 'Reorder'),
            ),
          OrchidHoverMenu(
            showHoverButton: false, openOnTap: true,
            actions: [
              for (final size in const ['S', 'M', 'L', 'XL'])
                OrchidHoverAction(size, LucideIcons.layoutGrid,
                  () => setState(() => _playlistSize = size)),
            ],
            child: _playlistToolbarChip(LucideIcons.layoutGrid,
              'Size: $_playlistSize'),
          ),
          OrchidAdaptiveControls.button(
            onPressed: _importingPlaylist ? null : _spotifyImport,
            child: Text(_importingPlaylist ? 'Importing…' : 'Import'),
          ),
          if (_playlistFolderId == null)
            OrchidAdaptiveControls.button(
              onPressed: _newFolder, child: const Text('New Folder')),
          OrchidAdaptiveControls.button(
            prominent: true, onPressed: _newPlaylist,
            child: const Text('New')),
        ],
      ),
      if (_playlistFolderId != null) ...[
        const SizedBox(height: 14),
        OrchidAdaptiveControls.button(
          onPressed: () => setState(() => _playlistFolderId = null),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(LucideIcons.arrowLeft, size: 16),
            const SizedBox(width: 8),
            Text(folders.where((f) => f.id == _playlistFolderId)
                .map((f) => f.name).firstOrNull ?? 'All playlists'),
          ]),
        ),
      ],
    ]);
  }

  Widget _playlistToolbarChip(IconData icon, String label) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: const Color(0x443F3150),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16), const SizedBox(width: 7),
        Text(label), const SizedBox(width: 5),
        const Icon(LucideIcons.chevronDown, size: 14),
      ]),
    );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) {
      final playlists = widget.library.visiblePlaylists;
      final albums = _libraryAlbums();
      final activeAlbumSongs = albums[_selectedAlbumKey];
      final selectedArtist = _selectedArtist;
      final activeArtist = selectedArtist != null &&
          (widget.library.isArtistSaved(selectedArtist) ||
            widget.library.librarySongs.any((song) =>
              song.artist.trim().toLowerCase() ==
                  selectedArtist.trim().toLowerCase()))
          ? selectedArtist : null;
      final artistSongs = activeArtist == null ? <SavedSong>[] :
          widget.library.librarySongs.where((song) =>
            song.artist.trim().toLowerCase() ==
                activeArtist.trim().toLowerCase()).toList();
      final mobile = MediaQuery.sizeOf(context).width < 850;
      if (mobile && !widget.playlistsOnly && _mobileSection == null) {
        return _mobileLibraryLanding(context);
      }
      final showingPlaylists = widget.playlistsOnly ||
          (mobile && _mobileSection == 'Playlists');
      final id = widget.playlistsOnly
          ? widget.selectedPlaylistId : _mobilePlaylistId;
      MusicPlaylist? activePlaylist;
      if (id != null && id != 'favorites') {
        for (final playlist in playlists) {
          if (playlist.id == id) {
            activePlaylist = playlist;
            break;
          }
        }
      }
      final selected = id == 'favorites' || activePlaylist != null;
      final selectedSongs = id == 'favorites'
        ? widget.library.favorites
        : activePlaylist?.songs ?? <SavedSong>[];
      final selectedTitle = id == 'favorites'
        ? 'Favorites' : activePlaylist?.name ?? 'Playlists';
      return ListView(
        padding: EdgeInsets.fromLTRB(24,
          24 + MediaQuery.paddingOf(context).top, 30,
          28 + OrchidStyle.iosDockClearance(context) +
          (MediaQuery.sizeOf(context).width >= 850 ? 104 : 0)),
        children: [
          widget.header,
          if (mobile && !widget.playlistsOnly) ...[
            _mobilePageHeader(
              _mobilePlaylistId != null
                  ? selectedTitle
                  : _selectedAlbumKey != null
                      ? (activeAlbumSongs?.first.album ?? 'Album')
                      : activeArtist ?? (_playlistFolderId != null
                          ? widget.library.playlistFolders
                              .where((folder) => folder.id == _playlistFolderId)
                              .map((folder) => folder.name)
                              .firstOrNull ?? 'Folder'
                          : _mobileSection ?? 'Library'),
              action: () {
                if (_mobilePlaylistId != null) {
                  if (selectedSongs.isNotEmpty) _playCollection(selectedSongs);
                } else if (_selectedAlbumKey != null) {
                  if (activeAlbumSongs != null) _playCollection(activeAlbumSongs);
                } else if (activeArtist != null) {
                  widget.library.toggleArtistSaved(activeArtist);
                } else if (showingPlaylists) {
                  _showMobilePlaylistAddMenu();
                } else {
                  setState(() {
                    _mobileSelecting = !_mobileSelecting;
                    _mobileSelected.clear();
                  });
                }
              },
              actionChild: _mobilePlaylistId != null ||
                           _selectedAlbumKey != null
                  ? const Icon(LucideIcons.play, size: 21,
                      color: OrchidStyle.pink)
                  : activeArtist != null
                      ? Icon(widget.library.isArtistSaved(activeArtist)
                          ? LucideIcons.check : LucideIcons.plus,
                          size: 21, color: OrchidStyle.pink)
                      : showingPlaylists
                          ? const Icon(LucideIcons.plus, size: 24,
                              color: OrchidStyle.pink)
                          : Text(_mobileSelecting ? 'Done' : 'Select',
                              style: const TextStyle(
                                fontSize: 13,
                                color: OrchidStyle.pink,
                                fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 20),
            _mobileSelectionBar(albums),
          ],
          if (!showingPlaylists) ...[
            if (activeAlbumSongs != null &&
                (_view == 'Albums' || _view == 'Artists' &&
                    activeArtist != null)) ...[
              _savedAlbumDetail(activeAlbumSongs),
            ] else if (_view == 'Artists' && activeArtist != null) ...[
              _savedArtistDetail(activeArtist, artistSongs, albums),
            ] else ...[
              if (!mobile) const OrchidSectionHeader(title: 'Library'),
              const SizedBox(height: 8),
              Text(mobile
                ? switch (_view) {
                    'Artists' => '${widget.library.savedArtists.length} followed artists',
                    'Albums' => '${albums.length} saved albums',
                    _ => '${widget.library.librarySongs.length} saved songs',
                  }
                : '${widget.library.librarySongs.length} saved songs').small().muted(),
              const SizedBox(height: 18),
              _libraryTools(),
              const SizedBox(height: 18),
              if (_view == 'Artists')
                _savedArtistsGrid()
              else if (_view == 'Albums')
                _albumsGrid(albums)
              else
                _songList(widget.library.librarySongs),
            ],
          ] else if (selected) ...[
            if (widget.playlistsOnly && widget.onPlaylistSelected != null)
              Align(alignment: Alignment.centerLeft,
                child: IconButton.ghost(
                  onPressed: () => widget.onPlaylistSelected!(null),
                  icon: const Icon(LucideIcons.arrowLeft))),
            LayoutBuilder(builder: (context, bounds) {
              final narrow = bounds.maxWidth < 540;
              final cover = SizedBox(width: 148, height: 148,
                child: ClipRRect(borderRadius: BorderRadius.circular(12),
                  child: _playlistArtwork(selectedSongs,
                    favorite: id == 'favorites')));
              final details = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Playlist').small().muted(),
                  const SizedBox(height: 5),
                  Text(selectedTitle).x2Large().semiBold(),
                  const SizedBox(height: 6),
                  Text('${selectedSongs.length} songs').small().muted(),
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    OrchidAdaptiveControls.button(
                      prominent: true,
                      onPressed: selectedSongs.isEmpty ? null :
                        () => _playCollection(selectedSongs),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(LucideIcons.play, size: 17),
                        SizedBox(width: 7), Text('Play all')]),
                    ),
                    if (selected)
                      OrchidHoverMenu(
                        showHoverButton: false,
                        openOnTap: true,
                        actions: [
                          if (id == 'favorites')
                            OrchidHoverAction('Play all favorites', LucideIcons.play,
                              () => _playCollection(widget.library.favorites)),
                          if (id == 'favorites')
                            OrchidHoverAction('Add favorites to queue', LucideIcons.listMusic,
                              () {
                                for (final song in widget.library.favorites) {
                                  widget.player.addToQueue(_track(song));
                                }
                              }),
                          if (activePlaylist != null) ...[
                          OrchidHoverAction(
                            widget.library.isPlaylistSaved(activePlaylist)
                              ? 'Remove from Library' : 'Add to Library',
                            LucideIcons.library,
                            () => widget.library.togglePlaylistSaved(activePlaylist!)),
                          OrchidHoverAction(
                            activePlaylist.pinned ? 'Unpin from Home' : 'Pin to Home',
                            LucideIcons.pin,
                            () => widget.library.setPlaylistPinned(
                              activePlaylist!, !activePlaylist!.pinned)),
                          OrchidHoverAction('Delete playlist', LucideIcons.trash2,
                            () async {
                              await widget.library.deletePlaylist(activePlaylist!);
                              if (widget.playlistsOnly) {
                                widget.onPlaylistSelected?.call(null);
                              } else {
                                _selectMobilePlaylist(null);
                              }
                            }),
                          ],
                        ],
                        child: const SizedBox(width: 42, height: 42,
                          child: Center(child: Icon(LucideIcons.ellipsis))),
                      ),
                  ]),
                ],
              );
              return narrow
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    cover, const SizedBox(height: 16), details])
                : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    cover, const SizedBox(width: 20),
                    Expanded(child: details)]);
            }),
            const SizedBox(height: 18),
            _songList(selectedSongs, playlist: activePlaylist),
          ] else ...[
            if (!mobile) const OrchidSectionHeader(title: 'Playlists'),
            const SizedBox(height: 16),
            if (mobile && !widget.playlistsOnly)
              _mobilePlaylistsContent(playlists)
            else ...[
              _playlistsToolbar(),
              const SizedBox(height: 20),
              _playlistsGrid(playlists),
            ],
          ],
        ],
      );
    },
  );

}
