import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../models/addon.dart';
import '../services/addon_service.dart';
import '../services/player_service.dart';
import '../widgets/mini_player_bar.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  final _addonService = AddonService();
  late final PlayerService _player;

  List<InstalledAddon> _addons = [];
  bool _loadingAddons = true;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _player = PlayerService(addonService: _addonService);
    _loadAddons();
  }

  Future<void> _loadAddons() async {
    final list = await _addonService.load();
    if (!mounted) return;
    setState(() {
      _addons = list;
      _loadingAddons = false;
    });
    _player.setAddons(list);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      headers: [
        AppBar(
          title: Text(_tab == 0 ? 'Search' : 'Settings'),
          subtitle: Text(
            _tab == 0
                ? 'iTunes · addons · Spicy Lyrics'
                : 'Sources & Eclipse addons',
          ),
        ),
      ],
      child: Column(
        children: [
          Expanded(
            child: _loadingAddons
                ? const Center(child: Text('Loading…').muted())
                : IndexedStack(
                    index: _tab,
                    children: [
                      SearchScreen(
                        addonService: _addonService,
                        player: _player,
                        addons: _addons,
                      ),
                      SettingsScreen(
                        addonService: _addonService,
                        addons: _addons,
                        onAddonsChanged: (next) {
                          setState(() => _addons = next);
                          _player.setAddons(next);
                        },
                      ),
                    ],
                  ),
          ),
          MiniPlayerBar(player: _player),
          NavigationBar(
            index: _tab,
            onSelected: (i) => setState(() => _tab = i),
            children: const [
              NavigationItem(
                label: Text('Search'),
                child: Icon(LucideIcons.search),
              ),
              NavigationItem(
                label: Text('Settings'),
                child: Icon(LucideIcons.settings),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
