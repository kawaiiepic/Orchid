import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../models/addon.dart';
import '../services/addon_service.dart';
import '../services/lyrics_appearance.dart';
import '../services/player_service.dart';
import '../widgets/floating_lyrics.dart';
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
  final _floating = FloatingLyricsController.instance;

  Key? selected = const ValueKey(0);

  NavigationBarAlignment alignment = NavigationBarAlignment.spaceAround;
  NavigationLabelType labelType = NavigationLabelType.none;
  bool customButtonStyle = true;
  bool expanded = true;

  List<InstalledAddon> _addons = [];

  @override
  void initState() {
    super.initState();
    LyricsAppearance.instance.load();
    _floating.load();
    _loadAddons();
    _player = PlayerService(addonService: _addonService);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _floating.attach(_player, context);
    });
  }

  @override
  void dispose() {
    _floating.detach();
    super.dispose();
  }

  Future<void> _loadAddons() async {
    try {
      final addons = await _addonService.load();
      setState(() => _addons = addons);
      _player.setAddons(addons);
    } catch (e) {
      debugPrint('Error loading addons: $e');
    }
  }

  NavigationItem buildButton(String label, IconData icon, Key key) {
    return NavigationItem(
      key: key,
      style: customButtonStyle
          ? const ButtonStyle.muted(density: ButtonDensity.icon)
          : null,
      selectedStyle: customButtonStyle
          ? const ButtonStyle.fixed(density: ButtonDensity.icon)
          : null,
      label: Text(label),
      child: Icon(icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pageIndex = (selected as ValueKey<int>?)?.value ?? 0;
    final pages = [
      SearchScreen(
        addonService: _addonService,
        player: _player,
        addons: _addons,
      ),
      SearchScreen(
        addonService: _addonService,
        player: _player,
        addons: _addons,
      ),
      SearchScreen(
        addonService: _addonService,
        player: _player,
        addons: _addons,
      ),
      SearchScreen(
        addonService: _addonService,
        player: _player,
        addons: _addons,
      ),
      SettingsScreen(
        addonService: _addonService,
        addons: _addons,
        onAddonsChanged: (installed) {
          setState(() => _addons = installed);
          _player.setAddons(installed);
        },
      ),
    ];

    return Scaffold(
      footers: [
        MiniPlayerBar(player: _player),
        const Divider(),
        NavigationBar(
          alignment: alignment,
          labelType: labelType,
          expanded: expanded,
          onSelected: (key) => setState(() => selected = key),
          selectedKey: selected,
          children: [
            buildButton('Home', BootstrapIcons.house, const ValueKey(0)),
            buildButton('Explore', BootstrapIcons.compass, const ValueKey(1)),
            buildButton(
              'Library',
              BootstrapIcons.musicNoteList,
              const ValueKey(2),
            ),
            buildButton('Profile', BootstrapIcons.person, const ValueKey(3)),
            buildButton('App', BootstrapIcons.gear, const ValueKey(4)),
          ],
        ),
      ],
      child: pages[pageIndex.clamp(0, pages.length - 1)],
    );
  }
}
