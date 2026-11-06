import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter/cupertino.dart' as ios;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

import '../services/orchid_account.dart';
import 'orchid_style.dart';

/// Global account menu. Uses the signed-in account name for an initials avatar
/// until Orchid receives profile-image data from the account service.
class ProfileMenu extends StatefulWidget {
  final OrchidAccount account;
  final VoidCallback onProfile;
  final VoidCallback onSettings;

  const ProfileMenu({
    super.key,
    required this.account,
    required this.onProfile,
    required this.onSettings,
  });

  @override
  State<ProfileMenu> createState() => _ProfileMenuState();
}

class _ProfileMenuState extends State<ProfileMenu> {
  OverlayEntry? _menu;

  void _close() {
    _menu?.remove();
    _menu?.dispose();
    _menu = null;
  }

  void _open() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      ios.showCupertinoModalPopup<void>(
        context: context,
        builder: (popupContext) => ios.CupertinoActionSheet(
          title: Text(widget.account.username ?? 'Your account'),
          actions: [
            ios.CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(popupContext).pop();
                widget.onProfile();
              },
              child: const Text('Your profile'),
            ),
            ios.CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(popupContext).pop();
                widget.onSettings();
              },
              child: const Text('Settings'),
            ),
          ],
          cancelButton: ios.CupertinoActionSheetAction(
            onPressed: () => Navigator.of(popupContext).pop(),
            child: const Text('Cancel'),
          ),
        ),
      );
      return;
    }
    if (_menu != null) {
      _close();
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final position = box.localToGlobal(Offset.zero);
    final viewport = MediaQuery.sizeOf(context);
    const menuWidth = 248.0;
    final left = (position.dx + box.size.width - menuWidth)
        .clamp(8.0, (viewport.width - menuWidth - 8).clamp(8.0, double.infinity))
        .toDouble();
    final top = position.dy + box.size.height + 8;
    _menu = OverlayEntry(
      builder: (_) => Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: menuWidth,
          child: Container(
            decoration: OrchidStyle.panelDecoration(radius: 18),
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.account.username ?? 'Your account',
                        maxLines: 1, overflow: TextOverflow.ellipsis).semiBold(),
                      const SizedBox(height: 3),
                      Text(widget.account.email ?? '',
                        maxLines: 1, overflow: TextOverflow.ellipsis)
                          .xSmall().muted(),
                    ],
                  ),
                ),
                const Divider(),
                _item('Your profile', LucideIcons.user, () {
                  _close();
                  widget.onProfile();
                }),
                _item('Settings', LucideIcons.settings, () {
                  _close();
                  widget.onSettings();
                }),
              ],
            ),
          ),
        ),
      ]),
    );
    Overlay.of(context).insert(_menu!);
  }

  Widget _item(String title, IconData icon, VoidCallback onTap) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 11),
          child: Row(children: [
            Icon(icon, size: 18, color: OrchidStyle.lilac),
            const SizedBox(width: 12),
            Text(title).semiBold(),
          ]),
        ),
      );

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.account.username ??
        widget.account.email ?? 'O').trim();
    final initial = name.isEmpty ? 'O' : name.substring(0, 1).toUpperCase();
    return GestureDetector(
      onTap: _open,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.fromLTRB(7, 5, 11, 5),
          decoration: OrchidStyle.panelDecoration(radius: 24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 35,
                height: 35,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFC8A2FF), Color(0xFF69468F)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: ClipOval(
                  child: widget.account.avatarUrl == null
                      ? Center(child: Text(initial, style: const TextStyle(
                          color: Color(0xFFFFFFFF),
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        )))
                      : Image.network(
                          widget.account.avatarUrl!,
                          width: 35, height: 35, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Center(child: Text(initial,
                                style: const TextStyle(
                                  color: Color(0xFFFFFFFF),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17,
                                ))),
                        ),
                ),
              ),
              const SizedBox(width: 9),
              const Icon(LucideIcons.chevronDown, size: 16,
                color: OrchidStyle.lilac),
            ],
          ),
        ),
      ),
    );
  }
}
