import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../services/music_library.dart';
import 'orchid_style.dart';

/// Desktop-only navigation surface. The active tab is owned by ShellScreen.
class DesktopSidebar extends StatelessWidget {
  final int selectedTab;
  final MusicLibrary library;
  final String accountName;
  final VoidCallback onHome;
  final VoidCallback onSearch;
  final VoidCallback onDiscover;
  final VoidCallback onPlaylists;
  final VoidCallback onLibrary;
  final VoidCallback onReplay;
  final VoidCallback onRadio;
  final VoidCallback onAiDj;
  final VoidCallback onSettings;
  final VoidCallback onProfile;

  const DesktopSidebar({
    super.key,
    required this.selectedTab,
    required this.library,
    required this.accountName,
    required this.onHome,
    required this.onSearch,
    required this.onDiscover,
    required this.onPlaylists,
    required this.onLibrary,
    required this.onReplay,
    required this.onRadio,
    required this.onAiDj,
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
    return Container(
      width: 236,
      decoration: BoxDecoration(
        color: const Color(0xED21182F),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(
          color: Color(0x55000000), blurRadius: 26, offset: Offset(0, 9),
        )],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          _nav('Home', LucideIcons.house, onHome, selected: selectedTab == 0),
          _nav('Search', LucideIcons.search, onSearch, selected: selectedTab == 1),
          _nav('Discover', LucideIcons.compass, onDiscover, selected: selectedTab == 3),
          _nav('Library', LucideIcons.library, onLibrary, selected: selectedTab == 2),
          _nav('Playlists', LucideIcons.listMusic, onPlaylists, selected: selectedTab == 4),
          _nav('Replay', LucideIcons.audioLines, onReplay),
          _nav('Radio', LucideIcons.radio, onRadio),
          _nav('AI DJ', LucideIcons.bot, onAiDj),
          const SizedBox(height: 17),
          const Padding(
            padding: EdgeInsets.fromLTRB(21, 0, 12, 9),
            child: Text('YOUR COLLECTION', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700,
              letterSpacing: 1.3, color: Color(0xFF88819D))),
          ),
          _nav('Favorites', LucideIcons.heart, onPlaylists),
          Expanded(
            child: ListenableBuilder(
              listenable: library,
              builder: (context, _) => ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final playlist in library.visiblePlaylists)
                    _nav(playlist.name, LucideIcons.listMusic, onPlaylists),
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
                    child: Text(
                      accountName.isNotEmpty ? accountName[0].toUpperCase() : '?',
                      style: const TextStyle(color: OrchidStyle.lilac,
                        fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
