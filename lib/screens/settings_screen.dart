import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../models/addon.dart';
import '../services/addon_service.dart';
import '../services/lyrics_appearance.dart';
import '../widgets/floating_lyrics.dart';

class SettingsScreen extends StatefulWidget {
  final AddonService addonService;
  final List<InstalledAddon> addons;
  final ValueChanged<List<InstalledAddon>> onAddonsChanged;

  const SettingsScreen({
    super.key,
    required this.addonService,
    required this.addons,
    required this.onAddonsChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlController = TextEditingController();
  bool _adding = false;
  String? _status;
  final _appearance = LyricsAppearance.instance;
  final _floating = FloatingLyricsController.instance;

  @override
  void initState() {
    super.initState();
    _appearance.load().then((_) {
      if (mounted) setState(() {});
    });
    _floating.load().then((_) {
      if (mounted) setState(() {});
    });
    _appearance.addListener(_onAppearance);
    _floating.addListener(_onAppearance);
  }

  void _onAppearance() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _appearance.removeListener(_onAppearance);
    _floating.removeListener(_onAppearance);
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _addAddon() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _adding = true;
      _status = null;
    });
    try {
      final installed = await widget.addonService.fetchAndBuild(url);
      final next = List<InstalledAddon>.from(widget.addons);
      final idx = next.indexWhere(
        (a) =>
            a.baseUrl == installed.baseUrl ||
            a.manifest.id == installed.manifest.id,
      );
      if (idx >= 0) {
        next[idx] = installed;
      } else {
        next.add(installed);
      }
      await widget.addonService.save(next);
      widget.onAddonsChanged(next);
      if (!mounted) return;
      setState(() {
        _urlController.clear();
        _status = 'Added ${installed.manifest.name}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Add failed: $e');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _removeAddon(InstalledAddon addon) async {
    final next =
        widget.addons.where((a) => a.baseUrl != addon.baseUrl).toList();
    await widget.addonService.save(next);
    widget.onAddonsChanged(next);
  }

  Widget _switchTile(String title, String subtitle, bool value,
      ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),
                Text(subtitle).xSmall().muted(),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _sliderTile(
    String title,
    double value,
    double min,
    double max, {
    int divisions = 20,
    String Function(double)? label,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title)),
              Text(label?.call(value) ?? value.toStringAsFixed(2))
                  .xSmall()
                  .muted(),
            ],
          ),
          Slider(
            value: SliderValue.single(value),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: (v) => onChanged(v.value),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = _appearance;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Lyrics appearance').large().semiBold(),
        const SizedBox(height: 8),
        const Text(
          'Matches Sweet Lyrics style options: simple mode, size, glow, blur, alignment.',
        ).small().muted(),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _switchTile(
                  'Floating lyrics',
                  'Draggable mini lyrics bubble while Orchid is open',
                  _floating.enabled,
                  (v) {
                    if (v) {
                      _floating.showFrom(context);
                    } else {
                      _floating.setEnabled(false);
                    }
                  },
                ),
                _switchTile(
                  'Simple Lyrics Mode',
                  'Softer fill, no glow, milder motion',
                  a.simpleMode,
                  (v) => a.update((x) => x.simpleMode = v),
                ),
                _switchTile(
                  'Centered lyrics',
                  'Center-align every line',
                  a.centered,
                  (v) => a.update((x) => x.centered = v),
                ),
                _switchTile(
                  'Distance blur',
                  'Blur lines away from the active one',
                  a.blurEnabled,
                  (v) => a.update((x) => x.blurEnabled = v),
                ),
                _switchTile(
                  'Show translations',
                  'Under each line when available',
                  a.showTranslations,
                  (v) => a.update((x) => x.showTranslations = v),
                ),
                _switchTile(
                  'Show transliteration',
                  'Romanized syllables when available',
                  a.showTransliteration,
                  (v) => a.update((x) => x.showTransliteration = v),
                ),
                _switchTile(
                  'Skip unsynced tracks',
                  'Auto-skip when lyrics have no timing',
                  a.skipUnsynced,
                  (v) => a.update((x) => x.skipUnsynced = v),
                ),
                _switchTile(
                  'Big artwork mode',
                  'Prefer large cover + current line in full player',
                  a.bigArtworkMode,
                  (v) => a.update((x) => x.bigArtworkMode = v),
                ),
                const Divider(),
                _sliderTile(
                  'Font size',
                  a.fontSize,
                  14,
                  36,
                  divisions: 22,
                  label: (v) => v.round().toString(),
                  onChanged: (v) => a.update((x) => x.fontSize = v),
                ),
                _sliderTile(
                  'Glow strength',
                  a.glowScale,
                  0,
                  2,
                  onChanged: (v) => a.update((x) => x.glowScale = v),
                ),
                _sliderTile(
                  'Blur strength',
                  a.blurScale,
                  0,
                  2,
                  onChanged: (v) => a.update((x) => x.blurScale = v),
                ),
                _sliderTile(
                  'Inactive brightness',
                  a.inactiveBrightness,
                  0.5,
                  1.5,
                  onChanged: (v) => a.update((x) => x.inactiveBrightness = v),
                ),
                _sliderTile(
                  'Line spacing',
                  a.lineSpacingScale,
                  0.5,
                  2,
                  onChanged: (v) => a.update((x) => x.lineSpacingScale = v),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const Expanded(child: Text('Weight')),
                      ...[0, 1, 2].map((i) {
                        final labels = ['Medium', 'Semibold', 'Bold'];
                        final selected = a.weightIndex == i;
                        return Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: selected
                              ? PrimaryButton(
                                  onPressed: () {},
                                  child: Text(labels[i]).xSmall(),
                                )
                              : OutlineButton(
                                  onPressed: () =>
                                      a.update((x) => x.weightIndex = i),
                                  child: Text(labels[i]).xSmall(),
                                ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text('Sources').large().semiBold(),
        const SizedBox(height: 8),
        const Text(
          'Built-in search uses iTunes. Add Eclipse-compatible addons for full streams.',
        ).small().muted(),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Built-in').semiBold(),
                const SizedBox(height: 8),
                _builtInRow(
                  'iTunes',
                  'Search + 30s previews when no stream matches',
                ),
                const SizedBox(height: 6),
                _builtInRow(
                  'Spicy Lyrics',
                  'Syllable / line sync · attribution required',
                ),
                const SizedBox(height: 6),
                _builtInRow(
                  'LRCLIB',
                  'Synced LRC fallback when Spicy has nothing',
                ),
                const SizedBox(height: 6),
                _builtInRow(
                  'Spotify API',
                  'Fallback search for track IDs (lyrics)',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text('Eclipse addons').semiBold(),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _urlController,
                placeholder: const Text('https://addon…/ or …/manifest.json'),
                onSubmitted: (_) => _addAddon(),
              ),
            ),
            const SizedBox(width: 8),
            PrimaryButton(
              onPressed: _adding ? null : _addAddon,
              child: Text(_adding ? '…' : 'Add'),
            ),
          ],
        ),
        if (_status != null) ...[
          const SizedBox(height: 8),
          Text(_status!).small().muted(),
        ],
        const SizedBox(height: 12),
        if (widget.addons.isEmpty)
          const Text('No external addons yet.').muted()
        else
          ...widget.addons.map((a) {
            final caps = <String>[
              if (a.manifest.canSearch) 'search',
              if (a.manifest.canStream) 'stream',
            ].join(', ');
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.manifest.name).semiBold(),
                            Text(
                              '${a.baseUrl}\n$caps · v${a.manifest.version}',
                            ).small().muted(),
                          ],
                        ),
                      ),
                      GhostButton(
                        onPressed: () => _removeAddon(a),
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _builtInRow(String title, String subtitle) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title),
              Text(subtitle).xSmall().muted(),
            ],
          ),
        ),
        const Text('on').xSmall().muted(),
      ],
    );
  }
}
