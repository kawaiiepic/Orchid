import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Subtle, clipped artwork zoom on desktop hover. Touch stays at normal scale.
class OrchidHoverZoom extends StatefulWidget {
  final Widget child;
  final double scale;
  const OrchidHoverZoom({super.key, required this.child, this.scale = 1.045});

  @override
  State<OrchidHoverZoom> createState() => _OrchidHoverZoomState();
}

class _OrchidHoverZoomState extends State<OrchidHoverZoom> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: ClipRect(
      child: AnimatedScale(
        scale: _hovered ? widget.scale : 1,
        duration: const Duration(milliseconds: 190),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    ),
  );
}
