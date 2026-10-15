import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../core/constants/enums.dart';
import '../../../shared/services/api/api_client.dart';

/// Module 6 (FR-6.1, FR-6.2; D-58).
const maxRecordBytes = 10 * 1024 * 1024;
const supportedRecordText = 'PDF, JPG or PNG, up to 10 MB';

/// One `health_records` document.
class HealthRecord {
  const HealthRecord({
    required this.id,
    required this.patientId,
    required this.category,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.uploadedAt,
    this.sharedWithDoctor = false,
    this.sharedAt,
  });

  final String id;
  final String patientId;
  final RecordCategory category;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final DateTime uploadedAt;
  final bool sharedWithDoctor;
  final DateTime? sharedAt;

  bool get isPdf => contentType == 'application/pdf';

  factory HealthRecord.fromFirestore(String id, Map<String, dynamic> d) => HealthRecord(
    id: id,
    patientId: d['patientId'] as String? ?? '',
    category: RecordCategory.fromValue(d['category'] as String? ?? 'other'),
    fileName: d['fileName'] as String? ?? 'Document',
    contentType: d['contentType'] as String? ?? 'application/pdf',
    sizeBytes: (d['sizeBytes'] as num?)?.toInt() ?? 0,
    uploadedAt: (d['uploadedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    sharedWithDoctor: d['sharedWithDoctor'] == true,
    sharedAt: (d['sharedAt'] as Timestamp?)?.toDate(),
  );
}

/// A file the patient chose, before upload.
class PickedRecordFile {
  const PickedRecordFile({required this.bytes, required this.name, required this.contentType});

  final Uint8List bytes;
  final String name;
  final String contentType;
}

/// UC6.1 E1: not PDF/JPG/PNG, or larger than 10 MB.
class UnsupportedRecordFile implements Exception {
  const UnsupportedRecordFile();

  String get message => 'This file is not supported. Please choose $supportedRecordText.';
}

/// PDF/JPG/PNG content type from a file name, or null when unsupported.
String? recordContentType(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.pdf')) return 'application/pdf';
  if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
  if (n.endsWith('.png')) return 'image/png';
  return null;
}

/// UC6.1 E1, checked before anything is uploaded.
PickedRecordFile checkRecordFile(Uint8List bytes, String name) {
  final type = recordContentType(name);
  if (type == null || bytes.length > maxRecordBytes) throw const UnsupportedRecordFile();
  return PickedRecordFile(bytes: bytes, name: name, contentType: type);
}

String fileSizeLabel(int bytes) => bytes >= 1024 * 1024
    ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).ceil()} KB';

abstract interface class RecordsRepository {
  /// The patient's own records, newest first.
  Stream<List<HealthRecord>> myRecords(String patientId);

  /// UC6.3: what the patient has shared with their doctor, newest first.
  Stream<List<HealthRecord>> sharedRecords(String patientId);

  String newRecordId();

  /// UC6.1 steps 1-2 (E2: retried, then throws).
  Future<void> uploadFile(
    String patientId,
    String recordId,
    PickedRecordFile file, {
    void Function(double progress)? onProgress,
  });

  /// The patient closed the category step: remove the uploaded file.
  Future<void> discardUpload(String patientId, String recordId);

  /// UC6.1 steps 3-4.
  Future<void> save(String recordId, RecordCategory category, String fileName);

  Future<void> setCategory(String recordId, RecordCategory category);

  Future<void> delete(String recordId);

  Future<void> share(String recordId);

  Future<void> unshare(String recordId);

  Future<Uint8List> fileBytes(String recordId);
}

class FirebaseRecordsRepository implements RecordsRepository {
  FirebaseRecordsRepository(this._db, this._storage, this._api);

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final ApiClient _api;

  static const _attempts = 3;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection(Collections.healthRecords);

  String _path(String patientId, String recordId) => 'health_records/$patientId/$recordId';

  List<HealthRecord> _list(QuerySnapshot<Map<String, dynamic>> s) => [
    for (final d in s.docs) HealthRecord.fromFirestore(d.id, d.data()),
  ];

  @override
  Stream<List<HealthRecord>> myRecords(String patientId) => _col
      .where('patientId', isEqualTo: patientId)
      .orderBy('uploadedAt', descending: true)
      .snapshots()
      .map(_list);

  @override
  Stream<List<HealthRecord>> sharedRecords(String patientId) => _col
      .where('patientId', isEqualTo: patientId)
      .where('sharedWithDoctor', isEqualTo: true) // required by the rules for the doctor
      .orderBy('uploadedAt', descending: true)
      .snapshots()
      .map(_list);

  @override
  String newRecordId() => _col.doc().id;

  @override
  Future<void> uploadFile(
    String patientId,
    String recordId,
    PickedRecordFile file, {
    void Function(double progress)? onProgress,
  }) async {
    final ref = _storage.ref(_path(patientId, recordId));
    for (var attempt = 1; ; attempt++) {
      try {
        final task = ref.putData(file.bytes, SettableMetadata(contentType: file.contentType));
        final sub = task.snapshotEvents.listen((s) {
          if (s.totalBytes > 0) onProgress?.call(s.bytesTransferred / s.totalBytes);
        });
        try {
          await task;
        } finally {
          await sub.cancel();
        }
        return;
      } on FirebaseException {
        if (attempt >= _attempts) rethrow;
        await Future<void>.delayed(Duration(seconds: attempt));
      }
    }
  }

  @override
  Future<void> discardUpload(String patientId, String recordId) async {
    try {
      await _storage.ref(_path(patientId, recordId)).delete();
    } on FirebaseException {
      // Already gone; nothing to clean up.
    }
  }

  @override
  Future<void> save(String recordId, RecordCategory category, String fileName) =>
      _api.createRecord(recordId: recordId, category: category.value, fileName: fileName);

  @override
  Future<void> setCategory(String recordId, RecordCategory category) =>
      _api.setRecordCategory(recordId, category.value);

  @override
  Future<void> delete(String recordId) => _api.deleteRecord(recordId);

  @override
  Future<void> share(String recordId) => _api.shareRecord(recordId);

  @override
  Future<void> unshare(String recordId) => _api.unshareRecord(recordId);

  @override
  Future<Uint8List> fileBytes(String recordId) async =>
      Uint8List.fromList(await _api.recordFile(recordId));
}
