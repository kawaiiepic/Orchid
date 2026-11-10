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
      // Match the Playlists page header: artwork on the left and metadata
      // alongside it, with a stacked fallback only on narrow viewports.
      final narrow = constraints.maxWidth < 540;
      const artworkSize = 148.0;
      final details = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(child: Text(eyebrow,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFB7ABCA),
              ))),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 5),
          Text(title, maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFF9F5FF),
              fontSize: 27,
              height: 1.12,
              fontWeight: FontWeight.w700,
            )),
          const SizedBox(height: 6),
          Text(subtitle, maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFB7ABCA),
              fontSize: 13,
            )),
          const SizedBox(height: 14),
          actions,
        ],
      );
      final cover = SizedBox(
        width: artworkSize,
        height: artworkSize,
        child: artwork,
      );
      if (narrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            cover,
            const SizedBox(height: 16),
            details,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          cover,
          const SizedBox(width: 20),
          Expanded(child: details),
        ],
      );
    },
  );
}
