import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../services/music_library.dart';
import 'orchid_style.dart';

/// Desktop-only navigation surface. The active tab is owned by ShellScreen.
class DesktopSidebar extends StatelessWidget {
  final int selectedTab;
  final MusicLibrary library;
  final String accountName;
  final String? avatarUrl;
  final VoidCallback onHome;
  final VoidCallback onSearch;
  final VoidCallback onDiscover;
  final VoidCallback onPlaylists;
  final VoidCallback onLibrary;
  final VoidCallback onReplay;
  final VoidCallback onRadio;
  final VoidCallback onAiDj;
  final String? selectedPlaylistId;
  final ValueChanged<String?> onPlaylistSelected;
  final VoidCallback onSettings;
  final VoidCallback onProfile;

  const DesktopSidebar({
    super.key,
    required this.selectedTab,
    required this.library,
    required this.accountName,
    this.avatarUrl,
    required this.onHome,
    required this.onSearch,
    required this.onDiscover,
    required this.onPlaylists,
    required this.onLibrary,
    required this.onReplay,
    required this.onRadio,
    required this.onAiDj,
    required this.selectedPlaylistId,
    required this.onPlaylistSelected,
    required this.onSettings,
    required this.onProfile,
  });

  Widget _nav(String label, IconData icon, VoidCallback action,
      {bool selected = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: action,
        child: Container(
          height: 38,
          decoration: BoxDecoration(
            color: selected ? OrchidStyle.violet.withValues(alpha: 0.17) : null,
            borderRadius: BorderRadius.circular(9),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Icon(icon, size: 17,
              color: selected ? OrchidStyle.pink : const Color(0xFFA8A0B9)),
            const SizedBox(width: 12),
            Expanded(child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? OrchidStyle.pink : const Color(0xFFC7BFD2),
              ),
            )),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OrchidGlassPanel(
      radius: 18,
      transparentOnDesktop: false,
      child: SizedBox(
        width: 236,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          _nav('Home', LucideIcons.house, onHome, selected: selectedTab == 0),
          _nav('Search', LucideIcons.search, onSearch, selected: selectedTab == 1),
          _nav('Discover', LucideIcons.compass, onDiscover, selected: selectedTab == 3),
          _nav('Library', LucideIcons.library, onLibrary, selected: selectedTab == 2),
          _nav('Playlists', LucideIcons.listMusic, onPlaylists, selected: selectedTab == 4),
          _nav('Replay', LucideIcons.audioLines, onReplay, selected: selectedTab == 5),
          _nav('Radio', LucideIcons.radio, onRadio, selected: selectedTab == 6),
          const SizedBox(height: 17),
          const Padding(
            padding: EdgeInsets.fromLTRB(21, 0, 12, 9),
            child: Text('YOUR COLLECTION', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700,
              letterSpacing: 1.3, color: Color(0xFF88819D))),
          ),
          _nav('Favorites', LucideIcons.heart,
            () => onPlaylistSelected('favorites'),
            selected: selectedTab == 4 && selectedPlaylistId == 'favorites'),
          Expanded(
            child: ListenableBuilder(
              listenable: library,
              builder: (context, _) => ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final playlist in library.visiblePlaylists)
                    _nav(playlist.name, LucideIcons.listMusic,
                      () => onPlaylistSelected(playlist.id),
                      selected: selectedTab == 4 && selectedPlaylistId == playlist.id),
                  if (library.visiblePlaylists.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Text('Your playlists will appear here',
                        style: TextStyle(fontSize: 11, color: Color(0xFF89819B))),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onSettings,
                  child: Container(
                    width: 38, height: 38,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: OrchidStyle.panelLight,
                      shape: BoxShape.circle,
                    ),
                    child: avatarUrl == null
                      ? Text(
                          accountName.isNotEmpty ? accountName[0].toUpperCase() : '?',
                          style: const TextStyle(color: OrchidStyle.lilac,
                            fontSize: 15, fontWeight: FontWeight.w700))
                      : ClipOval(child: Image.network(avatarUrl!,
                          fit: BoxFit.cover, width: 38, height: 38,
                          errorBuilder: (_, __, ___) =>
                            const Icon(LucideIcons.user,
                              color: OrchidStyle.lilac))),
                  ),
                ),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
