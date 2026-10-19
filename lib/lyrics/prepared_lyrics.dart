// Render-ready lyrics: words that never wrap apart, per-letter timing for long
// syllables, instrumental-break "interlude" rows and background-vocal rows.
//
// Ported from Sweet Lyrics for iOS (`PreparedLyrics` in LyricsModels.swift),
// which follows Spicy Lyrics' `Applyer/Synced/Syllable.ts` and `Emphasize.ts`.
// Sweet Lyrics is AGPL-3.0; this file is a derivative work.
//
// Unlike the Swift original this builds straight from Orchid's existing
// [LyricsResult], so the service layer stays as it is.

import 'package:characters/characters.dart';

import '../services/lyrics_service.dart';

enum PreparedKind { syllable, line, staticText, interlude }

/// A letter of an emphasised syllable (or one interlude dot), with its own
/// slice of time.
class PreparedLetter {
  final String text;
  final double start;
  final double end;
  const PreparedLetter(this.text, this.start, this.end);
}

class PreparedSyllable {
  final String text;
  final double start;
  final double end;

  /// Non-null when the syllable is long enough to animate letter by letter.
  final List<PreparedLetter>? letters;

  const PreparedSyllable(this.text, this.start, this.end, [this.letters]);
}

/// Syllables glued into one word; a word never breaks across lines.
class PreparedWord {
  final List<PreparedSyllable> syllables;
  const PreparedWord(this.syllables);
}

class PreparedLine {
  final int id;
  final double start;
  final double end;
  final bool oppositeAligned;
  final PreparedKind kind;

  /// Syllable-synced words (kind == syllable).
  final List<PreparedWord> lead;
  final List<PreparedWord> background;

  /// Text for line / static kinds.
  final String text;

  /// The three dots of an interlude.
  final List<PreparedLetter> dots;

  /// A background vocal: its own row under its lead line, smaller and dimmer.
  final bool isBackground;

  /// For background rows, the lead line they belong to (focus never rests on
  /// a background row).
  final int? leadId;

  /// The line in its original language, what a translation replaces.
  final String sourceText;

  const PreparedLine({
    required this.id,
    required this.start,
    required this.end,
    required this.oppositeAligned,
    required this.kind,
    this.lead = const [],
    this.background = const [],
    this.text = '',
    this.dots = const [],
    this.isBackground = false,
    this.leadId,
    this.sourceText = '',
  });

  bool get isInterlude => kind == PreparedKind.interlude;

  /// The line as plain text (copy / share).
  String get plainText {
    switch (kind) {
      case PreparedKind.syllable:
        return [...lead, ...background]
            .map((w) => w.syllables.map((s) => s.text).join())
            .join(' ');
      case PreparedKind.line:
      case PreparedKind.staticText:
        return text;
      case PreparedKind.interlude:
        return '';
    }
  }
}

class PreparedLyrics {
  final PreparedKind kind;
  final List<PreparedLine> lines;
  final LyricsResult source;

  const PreparedLyrics._(this.kind, this.lines, this.source);

  bool get hasDuets => lines.any((l) => l.oppositeAligned);

  /// Gap (seconds) that earns an interlude (`getLyricsBetweenShow()`).
  static const double interludeThreshold = 3;

  /// The dots finish this long before the next line (`preHiddenDotLineMs + 50`).
  static const double interludePadding = 0.55;

  /// Syllables at least this long animate per letter (`IsLetterCapable`).
  static const double letterCapableDuration = 1.0;

  /// Emphasised letters end early so the last one can breathe (`Emphasize`).
  static const double emphasisEndSubtraction = 0.25;

  /// [romanized] shows the API's transliteration where present.
  /// [replacements] maps a line's original text to text shown instead (a
  /// translation); the new words are re-timed over the original syllables.
  factory PreparedLyrics.fromResult(
    LyricsResult result, {
    bool simple = false,
    bool romanized = false,
    Map<String, String> replacements = const {},
  }) {
    final out = <PreparedLine>[];

    void add(
      double start,
      double end,
      bool opposite,
      PreparedKind kind, {
      List<PreparedWord> lead = const [],
      String text = '',
      List<PreparedLetter> dots = const [],
      String sourceText = '',
    }) {
      out.add(PreparedLine(
        id: out.length,
        start: start,
        end: end,
        oppositeAligned: opposite,
        kind: kind,
        lead: lead,
        text: text,
        dots: dots,
        sourceText: sourceText,
      ));
    }

    String roman(LyricSyllable s) =>
        romanized ? (s.transliteratedText ?? s.text) : s.text;

    final src = result.lines;
    final isSyllable = result.bodyType == 'Syllable' && result.hasSyllables;
    final isTimedLine = !isSyllable && src.isNotEmpty;

    if (!isSyllable && !isTimedLine) {
      // Static lyrics: no timings at all.
      for (final raw in result.displayText.split('\n')) {
        final t = raw.trim();
        if (t.isEmpty) continue;
        add(0, 0, false, PreparedKind.staticText,
            text: replacements[t] ?? t, sourceText: t);
      }
      return PreparedLyrics._(PreparedKind.staticText, out, result);
    }

    if (src.first.start >= interludeThreshold) {
      add(0, src.first.start, src.first.oppositeAligned, PreparedKind.interlude,
          dots: _dots(0, src.first.start));
    }

    // A long line (a trailing backing vocal, say) can outlast the lines after
    // it, so a gap only counts once every earlier line has finished.
    var latestEnd = 0.0;
    for (var index = 0; index < src.length; index++) {
      final line = src[index];
      if (line.end > latestEnd) latestEnd = line.end;

      if (isSyllable) {
        int? leadId;
        final leadText = _plain(line.lead);
        final leadWords = replacements.containsKey(leadText)
            ? _retimed(replacements[leadText]!, line.lead, simple)
            : _words(line.lead, simple, roman);
        if (leadWords.isNotEmpty) {
          leadId = out.length;
          final starts = line.lead.map((s) => s.start);
          final ends = line.lead.map((s) => s.end);
          add(
            starts.isEmpty ? line.start : starts.reduce(_min),
            ends.isEmpty ? line.end : ends.reduce(_max),
            line.oppositeAligned,
            PreparedKind.syllable,
            lead: leadWords,
            sourceText: leadText,
          );
        }
        if (line.background.isNotEmpty) {
          final bgText = _plain(line.background);
          final words = replacements.containsKey(bgText)
              ? _retimed(replacements[bgText]!, line.background, simple)
              : _words(line.background, simple, roman);
          if (words.isNotEmpty) {
            out.add(PreparedLine(
              id: out.length,
              start: line.background.map((s) => s.start).reduce(_min),
              end: line.background.map((s) => s.end).reduce(_max),
              oppositeAligned: line.oppositeAligned,
              kind: PreparedKind.syllable,
              lead: words,
              isBackground: true,
              leadId: leadId,
              sourceText: bgText,
            ));
          }
        }
      } else {
        final text = (line.plainText ?? line.text);
        add(line.start, line.end, line.oppositeAligned, PreparedKind.line,
            text: replacements[text] ?? text, sourceText: text);
      }

      if (index + 1 < src.length) {
        final next = src[index + 1];
        if (next.start - latestEnd >= interludeThreshold) {
          add(latestEnd, next.start, next.oppositeAligned,
              PreparedKind.interlude,
              dots: _dots(latestEnd, next.start));
        }
      }
    }

    return PreparedLyrics._(
        isSyllable ? PreparedKind.syllable : PreparedKind.line, out, result);
  }

  static double _min(double a, double b) => a < b ? a : b;
  static double _max(double a, double b) => a > b ? a : b;

  /// The three dots' timing exactly as `Applyer/Synced/Syllable.ts` lays them
  /// out: thirds of the gap, each pulled earlier by a third of the padding,
  /// the last one ending `padding` early.
  static List<PreparedLetter> _dots(double start, double end) {
    final total = end - start;
    final third = total / 3;
    final padding = interludePadding / 3;
    final dot1 = _max(start, start + third - padding);
    final dot2 = _max(dot1, start + third * 2 - padding * 2);
    final dot3 = _max(dot2, start + total - interludePadding);
    return [
      PreparedLetter('•', start, dot1),
      PreparedLetter('•', dot1, dot2),
      PreparedLetter('•', dot2, dot3),
    ];
  }

  /// Syllables as one string, spaced where words end. In Orchid's model
  /// `isPartOfWord` means "joins the next syllable".
  static String _plain(List<LyricSyllable> syllables) => syllables
      .map((s) => s.text + (s.isPartOfWord ? '' : ' '))
      .join()
      .trim();

  static List<PreparedWord> _words(
    List<LyricSyllable> syllables,
    bool simple,
    String Function(LyricSyllable) display,
  ) {
    final words = <PreparedWord>[];
    var current = <PreparedSyllable>[];
    // Syllables are drawn left to right, so they must also light up left to
    // right. Some sources time a word slightly before the one in front of it;
    // start it with that one instead of lighting the line out of order.
    var earliestStart = double.negativeInfinity;
    for (final syllable in syllables) {
      final text = display(syllable).replaceAll('\u200B', '').trim();
      if (text.isNotEmpty) {
        final start =
            syllable.start > earliestStart ? syllable.start : earliestStart;
        earliestStart = start;
        current.add(_prepare(
            text, start, syllable.end > start ? syllable.end : start, simple));
      }
      if (!syllable.isPartOfWord && current.isNotEmpty) {
        words.add(PreparedWord(current));
        current = <PreparedSyllable>[];
      }
    }
    if (current.isNotEmpty) words.add(PreparedWord(current));
    return words;
  }

  /// Words of [text] timed over the original syllables. Each word takes the
  /// share of the line its length is of the whole, measured along the original
  /// syllables by their length too: the words follow the singer's pace and the
  /// pauses between the original syllables.
  static List<PreparedWord> _retimed(
    String text,
    List<LyricSyllable> syllables,
    bool simple,
  ) {
    final alnum = RegExp(r'[\p{L}\p{N}]', unicode: true);
    double weight(String s) {
      final n = alnum.allMatches(s).length;
      return (n < 1 ? 1 : n).toDouble();
    }

    final segments = <List<double>>[]; // [start, end, weight]
    for (final s in syllables) {
      if (s.text.trim().isEmpty) continue;
      segments.add([s.start, _max(s.end, s.start), weight(s.text)]);
    }
    final tokens =
        text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (segments.isEmpty || tokens.isEmpty) return const [];
    final segmentTotal = segments.fold<double>(0, (a, s) => a + s[2]);

    /// The time at [fraction] of the original line. At a boundary between two
    /// syllables a word start takes the later one, so it does not light up
    /// during the pause.
    double timeAt(double fraction, bool starting) {
      var target = fraction.clamp(0.0, 1.0) * segmentTotal;
      for (var i = 0; i < segments.length; i++) {
        final seg = segments[i];
        final isLast = i == segments.length - 1;
        if (target < seg[2] || (target == seg[2] && (!starting || isLast))) {
          return seg[0] + (seg[1] - seg[0]) * (target / seg[2]);
        }
        target -= seg[2];
      }
      return segments.last[1];
    }

    final weights = tokens.map(weight).toList();
    final tokenTotal = weights.fold<double>(0, (a, b) => a + b);

    // Pauses in the original (between syllables) a new word should not be sung
    // across.
    final pauses = <List<double>>[];
    for (var i = 0; i + 1 < segments.length; i++) {
      final s = segments[i][1], e = segments[i + 1][0];
      if (e - s >= 0.3) pauses.add([s, e]);
    }

    final words = <PreparedWord>[];
    var covered = 0.0;
    var earliest = double.negativeInfinity;
    for (var i = 0; i < tokens.length; i++) {
      var start = _max(timeAt(covered / tokenTotal, true), earliest);
      covered += weights[i];
      var end = timeAt(covered / tokenTotal, false);
      // A word straddling a pause keeps to the side where most of it falls.
      for (final pause in pauses) {
        if (pause[0] > start && pause[1] < end) {
          if (pause[0] - start >= end - pause[1]) {
            end = pause[0];
          } else {
            start = pause[1];
          }
        }
      }
      end = _max(end, start + 0.05);
      earliest = start;
      words.add(PreparedWord([_prepare(tokens[i], start, end, simple)]));
    }
    return words;
  }

  /// `IsLetterCapable` and `Emphasize`: long syllables animate per letter.
  /// Simple Lyrics Mode only does so for up to 12 letters lasting 1.05 s, and
  /// shifts the letters a little later.
  static PreparedSyllable _prepare(
      String text, double start, double end, bool simple) {
    final chars = text.characters.toList(growable: false);
    final duration = end - start;
    final capable = chars.length > 1 &&
        !_isRtl(text) &&
        (simple
            ? chars.length <= 12 && duration >= 1.05
            : duration >= letterCapableDuration);
    if (!capable) return PreparedSyllable(text, start, end);

    final letterStart = simple ? start + 0.021 : start;
    final letterEnd =
        simple ? end + 0.04 : _max(start + 0.05, end - emphasisEndSubtraction);
    final each = (letterEnd - letterStart) / chars.length;
    final letters = <PreparedLetter>[
      for (var i = 0; i < chars.length; i++)
        PreparedLetter(
            chars[i], letterStart + i * each, letterStart + (i + 1) * each),
    ];
    return PreparedSyllable(text, start, end, letters);
  }

  static bool _isRtl(String text) {
    for (final r in text.runes) {
      if ((r >= 0x0590 && r <= 0x08FF) ||
          (r >= 0xFB1D && r <= 0xFDFF) ||
          (r >= 0xFE70 && r <= 0xFEFF)) {
        return true;
      }
    }
    return false;
  }
}
