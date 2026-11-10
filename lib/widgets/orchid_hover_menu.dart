import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter/material.dart' as material;
import 'orchid_style.dart';

/// A contextual ellipsis for media cards. It stays invisible until a mouse
/// hovers the card, while touch users can open the same menu by long-pressing.
class OrchidHoverAction {
  final String label;
  final IconData icon;
  final VoidCallback onSelected;

  const OrchidHoverAction(this.label, this.icon, this.onSelected);
}

class OrchidHoverMenu extends StatefulWidget {
  final Widget child;
  final List<OrchidHoverAction> actions;
  final bool showHoverButton;
  final bool openOnTap;

  const OrchidHoverMenu({
    super.key,
    required this.child,
    required this.actions,
    this.showHoverButton = true,
    this.openOnTap = false,
  });

  @override
  State<OrchidHoverMenu> createState() => _OrchidHoverMenuState();
}

class _OrchidHoverMenuState extends State<OrchidHoverMenu> {
  bool _hovered = false;
  OverlayEntry? _entry;

  void _close() {
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  void _open({Offset? at}) {
    if (widget.actions.isEmpty) return;
    if (MediaQuery.sizeOf(context).width < 850) {
      _openMobileSheet();
      return;
    }
    _close();
    final object = context.findRenderObject();
    if (object is! RenderBox) return;
    final origin = object.localToGlobal(Offset.zero);
    final screen = MediaQuery.sizeOf(context);
    const width = 212.0;
    final left = ((at?.dx ?? (origin.dx + object.size.width)) - width)
      .clamp(8.0, (screen.width - width - 8).clamp(8.0, double.infinity))
      .toDouble();
    final height = widget.actions.length * 43.0 + 16.0;
    final top = (at?.dy ?? (origin.dy + 40))
      .clamp(8.0, (screen.height - height - 8).clamp(8.0, double.infinity))
      .toDouble();
    _entry = OverlayEntry(builder: (context) => Stack(children: [
      Positioned.fill(child: GestureDetector(
        behavior: HitTestBehavior.opaque, onTap: _close)),
      Positioned(
        left: left, top: top, width: width,
        child: OrchidGlassPanel(
          radius: 14,
          transparentOnDesktop: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final action in widget.actions)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _close();
                    action.onSelected();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 11),
                    child: Row(children: [
                      Icon(action.icon, size: 17, color: OrchidStyle.lilac),
                      const SizedBox(width: 12),
                      Expanded(child: Text(action.label).small()),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      ),
    ]));
    Overlay.of(context).insert(_entry!);
  }

  void _openMobileSheet() {
    material.showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: const Color(0x00000000),
      barrierColor: const Color(0x99000000),
      builder: (sheetContext) => material.SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .84),
          decoration: const BoxDecoration(
            color: Color(0xFF2E2239),
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF806F90),
                borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 17),
            Flexible(child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
              children: [
                for (final action in widget.actions)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      action.onSelected();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 16),
                      child: Row(children: [
                        Icon(action.icon, size: 21,
                          color: OrchidStyle.lilac),
                        const SizedBox(width: 16),
                        Expanded(child: Text(action.label,
                          style: const TextStyle(
                            fontSize: 15, color: Color(0xFFF7F0FF)))),
                      ]),
                    ),
                  ),
              ],
            )),
          ]),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) { if (mounted) setState(() => _hovered = true); },
    onExit: (_) { if (mounted) setState(() => _hovered = false); },
    child: GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: () => _open(),
      onTap: widget.openOnTap ? () => _open() : null,
      onSecondaryTapDown: (details) => _open(at: details.globalPosition),
      child: Stack(children: [
        widget.child,
        if (widget.showHoverButton) Positioned(
          right: 4, top: 4,
          child: IgnorePointer(
            ignoring: !(_hovered || MediaQuery.sizeOf(context).width < 850),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: (_hovered || MediaQuery.sizeOf(context).width < 850)
                  ? 1 : 0,
              child: IconButton.ghost(
                onPressed: _open,
                icon: const Icon(LucideIcons.ellipsis, size: 19),
              ),
            ),
          ),
        ),
      ]),
    ),
  );
}
