import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'orchid_style.dart';

/// Shared, responsive header for album, artist, and song detail pages.
class OrchidDetailHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget artwork;
  final Widget actions;
  final Widget? trailing;

  const OrchidDetailHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.artwork,
    required this.actions,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 620;
      final artworkSize = wide ? 194.0 : 184.0;
      final info = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(children: [
            Text(eyebrow.toUpperCase(), style: const TextStyle(
              fontSize: 11,
              letterSpacing: 1.7,
              fontWeight: FontWeight.w700,
              color: OrchidStyle.lilac,
            )),
            if (trailing != null) ...[
              const Spacer(),
              trailing!,
            ],
          ]),
          const SizedBox(height: 9),
          Text(title, maxLines: 3, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: const Color(0xFFF9F5FF),
              fontSize: wide ? 32 : 27,
              height: 1.12,
              fontWeight: FontWeight.w700,
            )),
          const SizedBox(height: 8),
          Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFB7ABCA), fontSize: 13,
            )),
          const SizedBox(height: 18),
          actions,
        ],
      );
      return ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF30253F),
                Color(0xFF211D2F),
                Color(0xFF181622),
              ],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(wide ? 24 : 20),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(width: artworkSize, height: artworkSize,
                        child: artwork),
                      const SizedBox(width: 28),
                      Expanded(child: info),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(child: SizedBox(
                        width: artworkSize, height: artworkSize,
                        child: artwork,
                      )),
                      const SizedBox(height: 22),
                      info,
                    ],
                  ),
          ),
        ),
      );
    },
  );
}
