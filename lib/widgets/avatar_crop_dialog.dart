import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// A square avatar editor shared with Petal's cropping approach.
/// The crop is uploaded as PNG only after the user confirms it.
class AvatarCropDialog extends StatefulWidget {
  final Uint8List image;
  final Future<void> Function(Uint8List image) onSave;

  const AvatarCropDialog({
    super.key,
    required this.image,
    required this.onSave,
  });

  @override
  State<AvatarCropDialog> createState() => _AvatarCropDialogState();
}

class _AvatarCropDialogState extends State<AvatarCropDialog> {
  final CropController _controller = CropController();
  bool _saving = false;
  String? _error;

  Future<void> _save(Uint8List image) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(image);
      if (mounted) closeOverlay(context);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final side = (MediaQuery.sizeOf(context).width - 88)
        .clamp(220.0, 420.0).toDouble();
    return AlertDialog(
    title: const Text('Crop profile picture'),
    content: SizedBox(
      width: side,
      height: side,
      child: Crop(
        image: widget.image,
        controller: _controller,
        aspectRatio: 1,
        withCircleUi: true,
        onCropped: (result) {
          switch (result) {
            case CropSuccess(:final croppedImage):
              _save(croppedImage);
            case CropFailure():
              if (mounted) {
                setState(() => _error = 'Could not crop the selected image.');
              }
          }
        },
      ),
    ),
    actions: [
      if (_error != null)
        Text(_error!, maxLines: 3).small(),
      GhostButton(
        onPressed: _saving ? null : () => closeOverlay(context),
        child: const Text('Cancel'),
      ),
      PrimaryButton(
        onPressed: _saving ? null : () => _controller.crop(),
        child: Text(_saving ? 'Uploading…' : 'Crop and save'),
      ),
    ],
  );
  }
}
