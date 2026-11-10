import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../widgets/orchid_adaptive_controls.dart';

import '../models/addon.dart';
import '../services/addon_service.dart';
import '../services/music_library.dart';
import '../services/orchid_account.dart';
import '../services/player_service.dart';
import '../widgets/apple_cover.dart';
import 'song_detail_screen.dart';
import '../widgets/orchid_style.dart';
import '../widgets/song_context_menu.dart';
import '../widgets/track_duration.dart';

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
  String _view = 'Songs';

  @override
  void dispose() {
    _queryController.dispose();
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

  Widget _songRow(SavedSong song, int number, {MusicPlaylist? playlist}) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SongContextMenu(
        track: _track(song), player: widget.player,
        library: widget.library, playlist: playlist,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            widget.player.setAddons(widget.addons);
            widget.player.playTrack(_track(song)).catchError((Object e) {
              debugPrint('[Orchid Library] Playback failed: $e');
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Row(children: [
              SizedBox(width: 30,
                child: Text('$number', textAlign: TextAlign.center).small().muted()),
              const SizedBox(width: 10),
              AppleCover(artist: song.artist, name: song.title,
                album: song.album, fallbackUrl: song.artwork,
                size: 42, radius: 7),
              const SizedBox(width: 12),
              Expanded(flex: 4, child: Column(
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
              if (MediaQuery.sizeOf(context).width >= 720)
                Expanded(flex: 3, child: Text(
                  song.album?.isNotEmpty == true ? song.album! : 'Unknown album',
                  maxLines: 1, overflow: TextOverflow.ellipsis).small().muted()),
              SizedBox(width: 64, child: Text(
                trackDurationLabel(song.duration) ?? '—',
                textAlign: TextAlign.end).small().muted()),
              const SizedBox(width: 38),
            ]),
          ),
        ),
      ),
    );

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
      TextField(
        controller: _queryController,
        placeholder: const Text('Search your library…'),
        onChanged: (_) => setState(() {}),
      ),
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
  );

  Widget _playlistArtwork(List<SavedSong> songs, {bool favorite = false}) {
    final covers = songs.take(4).toList();
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
      VoidCallback action, {bool favorite = false}) =>
    MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: action,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: _playlistArtwork(songs, favorite: favorite)),
          ),
          const SizedBox(height: 8),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis).semiBold(),
          Text('${songs.length} songs', maxLines: 1,
            overflow: TextOverflow.ellipsis).small().muted(),
        ]),
      ),
    );

  Widget _playlistsGrid(List<MusicPlaylist> playlists) =>
    LayoutBuilder(builder: (context, bounds) {
      const gap = 12.0;
      final columns = (bounds.maxWidth / 165).floor().clamp(2, 7).toInt();
      final entries = <Widget>[
        _playlistButton('Favorites', widget.library.favorites,
          () => widget.onPlaylistSelected?.call('favorites'), favorite: true),
        for (final playlist in playlists)
          _playlistButton(playlist.name, playlist.songs,
            () => widget.onPlaylistSelected?.call(playlist.id)),
      ];
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: entries.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: gap,
          mainAxisSpacing: 18,
          childAspectRatio: .75,
        ),
        itemBuilder: (_, i) => entries[i],
      );
    });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) {
      final playlists = widget.library.visiblePlaylists;
      final id = widget.selectedPlaylistId;
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
        padding: EdgeInsets.fromLTRB(24, 24, 30,
          28 + OrchidStyle.iosDockClearance(context) +
          (MediaQuery.sizeOf(context).width >= 850 ? 104 : 0)),
        children: [
          widget.header,
          if (!widget.playlistsOnly) ...[
            const Text('Library').x2Large().semiBold(),
            const SizedBox(height: 8),
            Text('${widget.library.librarySongs.length} saved songs').small().muted(),
            const SizedBox(height: 18),
            _libraryTools(),
            const SizedBox(height: 18),
            _songList(widget.library.librarySongs),
          ] else if (selected) ...[
            if (widget.onPlaylistSelected != null)
              Align(alignment: Alignment.centerLeft,
                child: IconButton.ghost(
                  onPressed: () => widget.onPlaylistSelected!(null),
                  icon: const Icon(LucideIcons.arrowLeft))),
            Text(selectedTitle).x2Large().semiBold(),
            const SizedBox(height: 6),
            Text('${selectedSongs.length} songs').small().muted(),
            const SizedBox(height: 16),
            if (selectedSongs.isNotEmpty)
              Align(alignment: Alignment.centerLeft,
                child: OrchidAdaptiveControls.button(
                  prominent: true,
                  onPressed: () => _playCollection(selectedSongs),
                  child: const Text('Play all'),
                )),
            if (activePlaylist != null) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                OrchidAdaptiveControls.button(
                  onPressed: () => widget.library.setPlaylistPinned(
                    activePlaylist!, !activePlaylist!.pinned),
                  child: Text(activePlaylist.pinned
                    ? 'Unpin from Home' : 'Pin to Home'),
                ),
                OrchidAdaptiveControls.button(
                  onPressed: () async {
                    await widget.library.deletePlaylist(activePlaylist!);
                    widget.onPlaylistSelected?.call(null);
                  },
                  child: const Text('Delete playlist'),
                ),
              ]),
            ],
            const SizedBox(height: 18),
            _songList(selectedSongs, playlist: activePlaylist),
          ] else ...[
            const Text('Playlists').x2Large().semiBold(),
            const SizedBox(height: 20),
            _playlistsGrid(playlists),
          ],
        ],
      );
    },
  );

}
