import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import 'messaging_repository.dart';

/// A file chosen to send (D-52).
class PickedAttachment {
  const PickedAttachment({required this.bytes, required this.name, required this.type});

  final Uint8List bytes;
  final String name;
  final AttachmentType type;
}

/// Photo (gallery or camera) or PDF chooser; null when the person cancels.
abstract interface class AttachmentPicker {
  /// Camera is not offered on the web portal.
  bool get hasCamera;

  Future<PickedAttachment?> photo({required bool camera});

  Future<PickedAttachment?> pdf();
}

class DeviceAttachmentPicker implements AttachmentPicker {
  DeviceAttachmentPicker({ImagePicker? images}) : _images = images ?? ImagePicker();

  final ImagePicker _images;

  @override
  bool get hasCamera => !kIsWeb;

  @override
  Future<PickedAttachment?> photo({required bool camera}) async {
    // The app declares CAMERA (for PPG), so Android requires it granted for the camera intent.
    if (camera && !kIsWeb && !await Permission.camera.request().isGranted) {
      throw StateError('Camera permission was not granted.');
    }
    final file = await _images.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      // Phone photos are often 5-10 MB; this keeps them well under the 10 MB limit.
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 80,
      requestFullMetadata: false, // no location or camera details in the shared file
    );
    if (file == null) return null;
    return PickedAttachment(
      bytes: await file.readAsBytes(),
      name: file.name,
      type: AttachmentType.image,
    );
  }

  @override
  Future<PickedAttachment?> pdf() async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['pdf']);
    if (file == null) return null;
    return PickedAttachment(
      bytes: await file.readAsBytes(),
      name: file.name,
      type: AttachmentType.pdf,
    );
  }
}
