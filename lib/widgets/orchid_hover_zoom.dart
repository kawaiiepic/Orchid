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

/// A soft dark hover background for tappable song and result rows.
class OrchidHoverSurface extends StatefulWidget {
  final Widget child;
  final double radius;
  const OrchidHoverSurface({super.key, required this.child, this.radius = 9});

  @override
  State<OrchidHoverSurface> createState() => _OrchidHoverSurfaceState();
}

class _OrchidHoverSurfaceState extends State<OrchidHoverSurface> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: _hovered ? const Color(0x66332940) : const Color(0x00000000),
        borderRadius: BorderRadius.circular(widget.radius),
      ),
      child: widget.child,
    ),
  );
}

  
/// Subtle brightness tint for clickable cards that should not scale.
class OrchidHoverBrighten extends StatefulWidget {
  final Widget child;
  const OrchidHoverBrighten({super.key, required this.child});

  @override
  State<OrchidHoverBrighten> createState() => _OrchidHoverBrightenState();
}

class _OrchidHoverBrightenState extends State<OrchidHoverBrighten> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: Stack(children: [
      widget.child,
      Positioned.fill(
        child: IgnorePointer(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: _hovered
                  ? const Color(0x18FFFFFF)
                  : const Color(0x00FFFFFF),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    ]),
  );
}
