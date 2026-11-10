import 'package:shadcn_flutter/shadcn_flutter.dart';
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
  String _view = 'Songs';
  String? _selectedAlbumKey;
  String? _selectedArtist;
  bool _followingOnly = false;

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

  Widget _songRow(SavedSong song, int number, {MusicPlaylist? playlist}) {
    var hovered = false;
    return StatefulBuilder(builder: (context, updateHover) => MouseRegion(
      onEnter: (_) => updateHover(() => hovered = true),
      onExit: (_) => updateHover(() => hovered = false),
      child: Padding(
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
              SizedBox(width: 30, child: Center(child: hovered
                ? const Icon(LucideIcons.play, size: 16)
                : Text('$number').small().muted())),
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
              child: _playlistArtwork(songs, favorite: favorite)),
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
              onTap: () => setState(() => _selectedAlbumKey = entry.key),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: LayoutBuilder(builder: (context, size) =>
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AppleCover(
                        artist: song.artist,
                        name: song.album!,
                        isAlbum: true,
                        fallbackUrl: song.artwork,
                        size: size.maxWidth,
                        radius: 0),
                    ),
                  )),
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
        Text('Saved Albums').large().semiBold(),
        const SizedBox(height: 14),
        _albumsGrid(artistAlbums),
        const SizedBox(height: 28),
        Text('Saved Songs').large().semiBold(),
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
      final columns = (bounds.maxWidth / 165).floor().clamp(2, 7).toInt();
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: artists.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns, crossAxisSpacing: 12,
          mainAxisSpacing: 18, childAspectRatio: .82),
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
              onTap: () => setState(() {
                _selectedArtist = artist;
                _selectedAlbumKey = null;
              }),
              child: Column(children: [
                Expanded(child: LayoutBuilder(builder: (context, bounds) {
                  final diameter = bounds.maxWidth < bounds.maxHeight
                      ? bounds.maxWidth : bounds.maxHeight;
                  return Center(child: ClipOval(
                    child: ArtistArtwork(artist: artist, size: diameter,
                      radius: diameter / 2),
                  ));
                })),
                const SizedBox(height: 8),
                Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis).semiBold(),
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

  Widget _playlistsGrid(List<MusicPlaylist> playlists) =>
    LayoutBuilder(builder: (context, bounds) {
      const gap = 12.0;
      final columns = (bounds.maxWidth / 165).floor().clamp(2, 7).toInt();
      final entries = <Widget>[
        for (final playlist in playlists)
          _playlistButton(playlist.name, playlist.songs,
            () => widget.onPlaylistSelected?.call(playlist.id),
            playlist: playlist),
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
            if (activeAlbumSongs != null &&
                (_view == 'Albums' || _view == 'Artists' &&
                    activeArtist != null)) ...[
              _savedAlbumDetail(activeAlbumSongs),
            ] else if (_view == 'Artists' && activeArtist != null) ...[
              _savedArtistDetail(activeArtist, artistSongs, albums),
            ] else ...[
              const Text('Library').x2Large().semiBold(),
              const SizedBox(height: 8),
              Text('${widget.library.librarySongs.length} saved songs').small().muted(),
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
            if (widget.onPlaylistSelected != null)
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
                              widget.onPlaylistSelected?.call(null);
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
            const Text('Playlists').x2Large().semiBold(),
            const SizedBox(height: 20),
            _playlistsGrid(playlists),
          ],
        ],
      );
    },
  );

}
