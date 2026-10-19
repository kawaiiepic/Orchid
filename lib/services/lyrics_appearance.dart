import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-tunable lyrics look — mirrors Sweet Lyrics AppearanceSettings.
class LyricsAppearance extends ChangeNotifier {
  static final LyricsAppearance instance = LyricsAppearance._();
  LyricsAppearance._();

  bool _loaded = false;

  bool simpleMode = false;
  bool centered = false;
  bool showTranslations = true;
  bool showTransliteration = true;
  bool blurEnabled = true;
  bool skipUnsynced = false;
  bool bigArtworkMode = false;

  double fontSize = 22;
  double blurScale = 1;
  double glowScale = 1;
  double inactiveBrightness = 1;
  double lineSpacingScale = 1;
  double translationScale = 1;

  /// 0 = normal, 1 = medium, 2 = bold
  int weightIndex = 2;

  FontWeight get weight {
    switch (weightIndex) {
      case 0:
        return FontWeight.w500;
      case 1:
        return FontWeight.w600;
      default:
        return FontWeight.w700;
    }
  }

  Future<void> load() async {
    if (_loaded) return;
    final p = await SharedPreferences.getInstance();
    simpleMode = p.getBool('lyrics.simpleMode') ?? false;
    centered = p.getBool('lyrics.centered') ?? false;
    showTranslations = p.getBool('lyrics.showTranslations') ?? true;
    showTransliteration = p.getBool('lyrics.showTransliteration') ?? true;
    blurEnabled = p.getBool('lyrics.blurEnabled') ?? true;
    skipUnsynced = p.getBool('lyrics.skipUnsynced') ?? false;
    bigArtworkMode = p.getBool('lyrics.bigArtworkMode') ?? false;
    fontSize = p.getDouble('lyrics.fontSize') ?? 22;
    blurScale = p.getDouble('lyrics.blurScale') ?? 1;
    glowScale = p.getDouble('lyrics.glowScale') ?? 1;
    inactiveBrightness = p.getDouble('lyrics.inactiveBrightness') ?? 1;
    lineSpacingScale = p.getDouble('lyrics.lineSpacingScale') ?? 1;
    translationScale = p.getDouble('lyrics.translationScale') ?? 1;
    weightIndex = p.getInt('lyrics.weightIndex') ?? 2;
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('lyrics.simpleMode', simpleMode);
    await p.setBool('lyrics.centered', centered);
    await p.setBool('lyrics.showTranslations', showTranslations);
    await p.setBool('lyrics.showTransliteration', showTransliteration);
    await p.setBool('lyrics.blurEnabled', blurEnabled);
    await p.setBool('lyrics.skipUnsynced', skipUnsynced);
    await p.setBool('lyrics.bigArtworkMode', bigArtworkMode);
    await p.setDouble('lyrics.fontSize', fontSize);
    await p.setDouble('lyrics.blurScale', blurScale);
    await p.setDouble('lyrics.glowScale', glowScale);
    await p.setDouble('lyrics.inactiveBrightness', inactiveBrightness);
    await p.setDouble('lyrics.lineSpacingScale', lineSpacingScale);
    await p.setDouble('lyrics.translationScale', translationScale);
    await p.setInt('lyrics.weightIndex', weightIndex);
  }

  Future<void> update(void Function(LyricsAppearance a) fn) async {
    fn(this);
    await _save();
    notifyListeners();
  }
}
