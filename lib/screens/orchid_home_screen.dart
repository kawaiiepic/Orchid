import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../services/orchid_account.dart';
import '../services/player_service.dart';

class OrchidHomeScreen extends StatefulWidget {
  final PlayerService player;
  final OrchidAccount account;
  final VoidCallback openExplore;
  final VoidCallback openProfile;

  const OrchidHomeScreen({
    super.key,
    required this.player,
    required this.account,
    required this.openExplore,
    required this.openProfile,
  });

  @override
  State<OrchidHomeScreen> createState() => _OrchidHomeScreenState();
}

class _OrchidHomeScreenState extends State<OrchidHomeScreen> {
  Map<String, dynamic>? _history;
  bool _loading = false;
  String? _error;
  String? _lastfmUser;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    widget.account.addListener(_accountChanged);
    _accountChanged();
  }

  @override
  void didUpdateWidget(covariant OrchidHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account != widget.account) {
      oldWidget.account.removeListener(_accountChanged);
      widget.account.addListener(_accountChanged);
      _accountChanged();
    }
  }

  void _accountChanged() {
    final user = widget.account.lastfmUsername;
    if (_lastfmUser == user) return;
    _lastfmUser = user;
    _requestId++;
    _history = null;
    _error = null;
    if (user != null) {
      _refresh();
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    if (!widget.account.lastfmConnected) return;
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.account.lastfmHome();
      if (!mounted || requestId != _requestId) return;
      setState(() => _history = result);
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    widget.account.removeListener(_accountChanged);
    super.dispose();
  }

  List<Map<String, dynamic>> _items(String key) {
    final raw = _history?[key];
    if (raw is! List) return [];
    return raw.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList();
  }

  String _count(dynamic value) {
    final number = value is num ? value : num.tryParse('$value') ?? 0;
    if (number >= 1000000) return '${(number / 1000000).toStringAsFixed(1)}m';
    if (number >= 1000) return '${(number / 1000).toStringAsFixed(1)}k';
    return number.toStringAsFixed(0);
  }

  Widget _art(String? url, {double size = 48}) {
    if (url == null || !url.startsWith('https://')) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.muted,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(LucideIcons.music2, size: 20),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _art(null, size: size),
      ),
    );
  }

  Widget _stat(String title, dynamic count) {
    return SizedBox(
      width: 138,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_count(count)).x2Large().semiBold(),
              const SizedBox(height: 4),
              Text(title).small().muted(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recentRow(Map<String, dynamic> track) {
    final artist = track['artist']?.toString() ?? '';
    final album = track['album']?.toString() ?? '';
    final nowPlaying = track['nowPlaying'] == true;
    final timestamp = track['timestamp'] is num
        ? (track['timestamp'] as num).toInt()
        : null;
    final time = timestamp == null
        ? ''
        : _relativeTime(DateTime.fromMillisecondsSinceEpoch(timestamp * 1000));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          _art(track['image'] as String?),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(track['title']?.toString() ?? 'Unknown track').semiBold(),
                Text(album.isEmpty ? artist : '$artist · $album').small().muted(),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(nowPlaying ? 'Now playing' : time).xSmall().muted(),
        ],
      ),
    );
  }

  String _relativeTime(DateTime when) {
    final difference = DateTime.now().difference(when);
    if (difference.isNegative || difference.inMinutes < 1) return 'Just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    return '${when.month}/${when.day}/${when.year}';
  }

  Widget _topCard(Map<String, dynamic> item, {required bool isAlbum}) {
    final title = item['name']?.toString() ?? 'Unknown';
    final artist = item['artist']?.toString() ?? '';
    return SizedBox(
      width: 156,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _art(item['image'] as String?, size: 132),
              const SizedBox(height: 10),
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis).semiBold(),
              if (isAlbum)
                Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis).small().muted(),
              Text('${_count(item['plays'])} plays').xSmall().muted(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _horizontalItems(List<Map<String, dynamic>> items, {required bool albums}) {
    if (items.isEmpty) {
      return const Text('Nothing here yet.').muted();
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items) ...[
            _topCard(item, isAlbum: albums),
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.player,
      builder: (context, _) {
        final current = widget.player.current;
        final linked = widget.account.lastfmConnected;
        final stats = _history?['stats'] is Map
            ? Map<String, dynamic>.from(_history!['stats'] as Map)
            : <String, dynamic>{};
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Welcome back, ${widget.account.username ?? 'listener'}').x2Large().semiBold(),
            const SizedBox(height: 5),
            const Text('Your music, your space.').muted(),
            const SizedBox(height: 24),
            const Text('Jump back in').large().semiBold(),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(current?.title ?? 'Nothing playing yet').semiBold(),
                    const SizedBox(height: 4),
                    Text(current?.artist ?? 'Find something you love and press play.').muted(),
                    const SizedBox(height: 12),
                    PrimaryButton(
                      onPressed: current == null
                          ? widget.openExplore
                          : () => widget.player.togglePlayPause(),
                      child: Text(current == null
                          ? 'Explore music'
                          : widget.player.player.playing ? 'Pause' : 'Resume'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: const Text('Your Last.fm').large().semiBold()),
                if (linked)
                  GhostButton(
                    onPressed: _loading ? null : _refresh,
                    child: Text(_loading ? 'Loading…' : 'Refresh'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (!linked)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Connect Last.fm to unlock your listening history.').semiBold(),
                      const SizedBox(height: 8),
                      const Text('See music played on all your Last.fm-connected apps, plus your favorite artists, albums, and listening stats.').small().muted(),
                      const SizedBox(height: 12),
                      PrimaryButton(
                        onPressed: widget.openProfile,
                        child: const Text('Connect Last.fm'),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              if (_error != null) ...[
                Text(_error!).small(),
                const SizedBox(height: 8),
                OutlineButton(onPressed: _refresh, child: const Text('Try again')),
              ],
              if (_loading && _history == null)
                const Text('Loading your listening history…').muted(),
              if (_history != null) ...[
                const Text('Listening statistics').large().semiBold(),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _stat('Scrobbles', stats['scrobbles']),
                    _stat('Artists', stats['artists']),
                    _stat('Albums', stats['albums']),
                    _stat('Tracks', stats['tracks']),
                  ],
                ),
                const SizedBox(height: 24),
                const Text('Recently played').large().semiBold(),
                const SizedBox(height: 10),
                if (_items('recent').isEmpty)
                  const Text('No Last.fm listening history yet.').muted()
                else
                  ..._items('recent').map(_recentRow),
                const SizedBox(height: 24),
                const Text('Top artists').large().semiBold(),
                const SizedBox(height: 5),
                const Text('All time').xSmall().muted(),
                const SizedBox(height: 10),
                _horizontalItems(_items('artists'), albums: false),
                const SizedBox(height: 24),
                const Text('Top albums').large().semiBold(),
                const SizedBox(height: 5),
                const Text('All time').xSmall().muted(),
                const SizedBox(height: 10),
                _horizontalItems(_items('albums'), albums: true),
              ],
            ],
            const SizedBox(height: 24),
            const Text('Your connections').large().semiBold(),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Petal account connected').semiBold(),
                          Text(linked
                                  ? 'Last.fm: ${widget.account.lastfmUsername}'
                                  : 'Link Last.fm for listening stats and scrobbles.')
                              .small()
                              .muted(),
                        ],
                      ),
                    ),
                    OutlineButton(
                      onPressed: widget.openProfile,
                      child: const Text('Manage'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
