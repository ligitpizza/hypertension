import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import 'records_repository.dart';

enum RecordSource { files, gallery, camera }

/// UC6.1 step 1: choose a document. Null when the patient cancels; throws
/// [UnsupportedRecordFile] for anything but PDF/JPG/PNG up to 10 MB.
abstract interface class RecordPicker {
  Future<PickedRecordFile?> pick(RecordSource source);
}

class DeviceRecordPicker implements RecordPicker {
  DeviceRecordPicker({ImagePicker? images}) : _images = images ?? ImagePicker();

  final ImagePicker _images;

  @override
  Future<PickedRecordFile?> pick(RecordSource source) async {
    if (source == RecordSource.files) {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      );
      if (file == null) return null;
      return checkRecordFile(await file.readAsBytes(), file.name);
    }
    final camera = source == RecordSource.camera;
    // The app declares CAMERA (for PPG), so Android requires it granted for the camera intent.
    if (camera && !kIsWeb && !await Permission.camera.request().isGranted) {
      throw StateError('Camera permission was not granted.');
    }
    final photo = await _images.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      // Keeps phone photos of documents readable and well under 10 MB.
      maxWidth: 2560,
      maxHeight: 2560,
      imageQuality: 85,
      requestFullMetadata: false, // no location in the stored file
    );
    if (photo == null) return null;
    final name = recordContentType(photo.name) == null ? '${photo.name}.jpg' : photo.name;
    return checkRecordFile(await photo.readAsBytes(), name);
  }
}
