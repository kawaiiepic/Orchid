import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Moves the fullscreen player with the user's finger without taking over
/// taps, lyrics scrolling, or drags on the transport and volume controls.
class PlayerDismissGestures extends StatefulWidget {
  const PlayerDismissGestures({
    super.key,
    required this.onDismiss,
    required this.child,
    this.downStartFraction = .65,
  });

  final VoidCallback onDismiss;
  final Widget child;
  final double downStartFraction;

  @override
  State<PlayerDismissGestures> createState() => _PlayerDismissGesturesState();
}

enum _Pull { down, left, right }

class _PlayerDismissGesturesState extends State<PlayerDismissGestures>
    with SingleTickerProviderStateMixin {
  late final AnimationController _settle = AnimationController(vsync: this)
    ..addListener(() => setState(() => _offset = _motion!.evaluate(_settle)));
  Tween<Offset>? _motion;
  Offset _offset = Offset.zero;
  int? _pointer;
  Offset? _start;
  _Pull? _direction;
  bool _canPullDown = false;
  bool _canPullLeft = false;
  bool _canPullRight = false;
  bool _closing = false;

  void _down(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch || _closing) return;
    if (_pointer != null) {
      _pointer = null;
      _start = null;
      _finish(dismiss: false);
      return;
    }
    final size = context.size;
    if (size == null || ModalRoute.of(context)?.isCurrent == false) return;
    // The artwork accepts horizontal swipes in either direction. Also
    // accept an inward swipe from either edge, including near the controls.
    final point = event.localPosition;
    final inArtwork = point.dy <= size.height * .60;
    _canPullRight = inArtwork || point.dx <= 26;
    _canPullLeft = inArtwork || point.dx >= size.width - 26;
    _canPullDown = point.dy <= size.height * widget.downStartFraction;
    if (!_canPullRight && !_canPullLeft && !_canPullDown) return;
    _settle.stop();
    _direction = null;
    _pointer = event.pointer;
    _start = point;
  }

  void _move(PointerMoveEvent event) {
    final start = _start;
    if (event.pointer != _pointer || start == null) return;
    final delta = event.localPosition - start;
    if (_direction == null && delta.distance >= 12) {
      if (delta.dy > delta.dx.abs() * 1.25 && _canPullDown) {
        _direction = _Pull.down;
      } else if (delta.dx.abs() > delta.dy.abs() * 1.25) {
        if (delta.dx > 0 && _canPullRight) _direction = _Pull.right;
        if (delta.dx < 0 && _canPullLeft) _direction = _Pull.left;
      }
    }
    final direction = _direction;
    if (direction == null) return;
    setState(() {
      _offset = switch (direction) {
        _Pull.down => Offset(0, delta.dy.clamp(0, double.infinity).toDouble()),
        _Pull.left =>
          Offset(delta.dx.clamp(double.negativeInfinity, 0).toDouble(), 0),
        _Pull.right => Offset(delta.dx.clamp(0, double.infinity).toDouble(), 0),
      };
    });
  }

  void _finish({required bool dismiss}) {
    final size = context.size;
    final direction = _direction;
    _direction = null;
    if (_offset == Offset.zero && !dismiss) return;
    _closing = dismiss;
    final target = !dismiss || size == null
        ? Offset.zero
        : switch (direction) {
            _Pull.down => Offset(0, size.height),
            _Pull.left => Offset(-size.width, 0),
            _Pull.right => Offset(size.width, 0),
            null => Offset.zero,
          };
    _motion = Tween(begin: _offset, end: target);
    _settle.animateFromStart(dismiss
        ? const Duration(milliseconds: 200)
        : const Duration(milliseconds: 220));
  }

  @override
  void initState() {
    super.initState();
    _settle.addStatusListener((status) {
      if (status != AnimationStatus.completed || !_closing || !mounted) return;
      if (ModalRoute.of(context)?.isCurrent == false) {
        _closing = false;
        setState(() => _offset = Offset.zero);
        return;
      }
      widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: (event) {
          if (event.pointer != _pointer) return;
          _pointer = null;
          _start = null;
          _finish(dismiss: _direction != null && _offset.distance >= 74);
        },
        onPointerCancel: (event) {
          if (event.pointer != _pointer) return;
          _pointer = null;
          _start = null;
          _finish(dismiss: false);
        },
        child: ClipRect(
          child: Transform.translate(offset: _offset, child: widget.child),
        ),
      );
}

extension on AnimationController {
  void animateFromStart(Duration duration) {
    value = 0;
    animateTo(1, duration: duration, curve: Curves.easeOutCubic);
  }
}
