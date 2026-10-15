import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hypertension/core/constants/enums.dart';
import 'package:hypertension/features/auth/state/auth_providers.dart';
import 'package:hypertension/features/records/data/record_picker.dart';
import 'package:hypertension/features/records/data/records_repository.dart';
import 'package:hypertension/features/records/presentation/records_page.dart';
import 'package:hypertension/features/records/presentation/shared_records_tab.dart';
import 'package:hypertension/features/records/state/records_providers.dart';
import 'package:hypertension/features/settings/data/settings_repository.dart';
import 'package:hypertension/features/settings/state/settings_providers.dart';
import 'package:hypertension/shared/services/api/api_client.dart';

import '../helpers/fakes.dart';

// Module 6 health records (FR-6.1, FR-6.2; UC6.1-UC6.3; D-58).

final pdfBytes = Uint8List.fromList([37, 80, 68, 70]);
// A 1x1 transparent PNG, so the image viewer can decode it.
final pngBytes = Uint8List.fromList(const [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, //
  0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 0, 1, 0, 0, 5, 0, 1, //
  13, 10, 45, 180, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

HealthRecord rec(
  String id, {
  RecordCategory category = RecordCategory.labResult,
  String name = 'blood_test.pdf',
  String type = 'application/pdf',
  bool shared = false,
}) => HealthRecord(
  id: id,
  patientId: 'p1',
  category: category,
  fileName: name,
  contentType: type,
  sizeBytes: 245760,
  uploadedAt: DateTime(2026, 10, 14),
  sharedWithDoctor: shared,
  sharedAt: shared ? DateTime(2026, 10, 15) : null,
);

class FakeRecordsRepository implements RecordsRepository {
  final records = StreamController<List<HealthRecord>>.broadcast();
  List<HealthRecord> current = const [];
  final calls = <String>[];
  bool failUpload = false;
  ApiException? saveError;

  void emit(List<HealthRecord> list) {
    current = list;
    records.add(list);
  }

  @override
  Stream<List<HealthRecord>> myRecords(String patientId) async* {
    yield current;
    yield* records.stream;
  }

  @override
  Stream<List<HealthRecord>> sharedRecords(String patientId) => Stream.value([
    for (final r in current)
      if (r.sharedWithDoctor) r,
  ]);

  @override
  String newRecordId() => 'new1';

  @override
  Future<void> uploadFile(
    String patientId,
    String recordId,
    PickedRecordFile file, {
    void Function(double progress)? onProgress,
  }) async {
    if (failUpload) throw Exception('network');
    onProgress?.call(1);
    calls.add('upload:$patientId:$recordId:${file.name}:${file.contentType}');
  }

  @override
  Future<void> discardUpload(String patientId, String recordId) async =>
      calls.add('discard:$recordId');

  @override
  Future<void> save(String recordId, RecordCategory category, String fileName) async {
    if (saveError != null) throw saveError!;
    calls.add('save:$recordId:${category.value}:$fileName');
  }

  @override
  Future<void> setCategory(String recordId, RecordCategory category) async =>
      calls.add('category:$recordId:${category.value}');

  @override
  Future<void> delete(String recordId) async => calls.add('delete:$recordId');

  @override
  Future<void> share(String recordId) async => calls.add('share:$recordId');

  @override
  Future<void> unshare(String recordId) async => calls.add('unshare:$recordId');

  @override
  Future<Uint8List> fileBytes(String recordId) async =>
      current.firstWhere((r) => r.id == recordId).isPdf ? pdfBytes : pngBytes;
}

class FakeRecordPicker implements RecordPicker {
  PickedRecordFile? next;
  bool unsupported = false;
  RecordSource? asked;

  @override
  Future<PickedRecordFile?> pick(RecordSource source) async {
    asked = source;
    if (unsupported) throw const UnsupportedRecordFile();
    return next;
  }
}

class FakeSharer implements FileSharer {
  final shared = <String>[];

  @override
  Future<void> share(Uint8List bytes, {required String fileName, required String mimeType}) async =>
      shared.add('$fileName|$mimeType');
}

late FakeRecordsRepository repo;
late FakeRecordPicker picker;
late FakeSharer sharer;

Widget host(Widget child) => ProviderScope(
  overrides: [
    recordsRepositoryProvider.overrideWithValue(repo),
    recordPickerProvider.overrideWithValue(picker),
    fileSharerProvider.overrideWithValue(sharer),
    authUidProvider.overrideWith((ref) => Stream.value('p1')),
  ],
  child: MaterialApp(home: child),
);

Future<void> openUpload(WidgetTester t, {String source = 'source-files'}) async {
  await t.tap(find.byKey(const Key('upload-record')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(Key(source)));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    repo = FakeRecordsRepository();
    picker = FakeRecordPicker();
    sharer = FakeSharer();
  });

  group('UC6.1 upload and categorise', () {
    tallTest('empty state, then upload, pick a category, save and share now', (t) async {
      picker.next = PickedRecordFile(
        bytes: pdfBytes,
        name: 'blood_test.pdf',
        contentType: 'application/pdf',
      );
      await t.pumpWidget(host(const RecordsPage()));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('records-empty')), findsOneWidget);
      await openUpload(t);
      expect(picker.asked, RecordSource.files);
      // The category is mandatory: Save stays disabled until one is chosen.
      expect(find.byKey(const Key('record-category-dialog')), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const Key('category-confirm'))).onPressed, isNull);
      await t.tap(find.byKey(const Key('category-lab_result')));
      await t.pump();
      await t.tap(find.byKey(const Key('category-confirm')));
      await t.pumpAndSettle();
      // Fig 3.44: "Share with doctor now?"
      expect(find.byKey(const Key('share-now')), findsOneWidget);
      await t.tap(find.byKey(const Key('share-confirm')));
      await t.pumpAndSettle();
      expect(repo.calls, [
        'upload:p1:new1:blood_test.pdf:application/pdf',
        'save:new1:lab_result:blood_test.pdf',
        'share:new1',
      ]);
      expect(find.text('Shared with your doctor.'), findsOneWidget);
    });

    tallTest('cancelling the category step discards the uploaded file', (t) async {
      picker.next = PickedRecordFile(bytes: pngBytes, name: 'xray.png', contentType: 'image/png');
      await t.pumpWidget(host(const RecordsPage()));
      await t.pumpAndSettle();
      await openUpload(t, source: 'source-camera');
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(repo.calls, ['upload:p1:new1:xray.png:image/png', 'discard:new1']);
      expect(find.text('Upload cancelled.'), findsOneWidget);
    });

    tallTest('E1 an unsupported file lists the supported formats', (t) async {
      picker.unsupported = true;
      await t.pumpWidget(host(const RecordsPage()));
      await t.pumpAndSettle();
      await openUpload(t);
      expect(find.textContaining('PDF, JPG or PNG, up to 10 MB'), findsOneWidget);
      expect(repo.calls, isEmpty);
    });

    tallTest('E2 a failed upload tells the patient after retrying', (t) async {
      picker.next = PickedRecordFile(
        bytes: pdfBytes,
        name: 'a.pdf',
        contentType: 'application/pdf',
      );
      repo.failUpload = true;
      await t.pumpWidget(host(const RecordsPage()));
      await t.pumpAndSettle();
      await openUpload(t);
      expect(find.textContaining('Upload failed after several tries'), findsOneWidget);
      expect(find.byKey(const Key('record-category-dialog')), findsNothing);
    });

    tallTest('a refused save removes the upload and shows the reason', (t) async {
      picker.next = PickedRecordFile(
        bytes: pdfBytes,
        name: 'a.pdf',
        contentType: 'application/pdf',
      );
      repo.saveError = ApiException('UNSUPPORTED_FILE', 'Not supported.');
      await t.pumpWidget(host(const RecordsPage()));
      await t.pumpAndSettle();
      await openUpload(t);
      await t.tap(find.byKey(const Key('category-other')));
      await t.pump();
      await t.tap(find.byKey(const Key('category-confirm')));
      await t.pumpAndSettle();
      expect(repo.calls.last, 'discard:new1');
      expect(find.text('Not supported.'), findsOneWidget);
    });
  });

  group('the list', () {
    tallTest('shows details, the shared badge and filters by category', (t) async {
      repo.current = [
        rec('r1', shared: true),
        rec('r2', category: RecordCategory.imaging, name: 'xray.png', type: 'image/png'),
      ];
      await t.pumpWidget(host(const RecordsPage()));
      await t.pumpAndSettle();
      expect(find.textContaining('Lab result · 240 KB · 14 Oct 2026'), findsOneWidget);
      expect(find.byKey(const Key('shared-r1')), findsOneWidget);
      expect(find.byKey(const Key('shared-r2')), findsNothing);
      await t.tap(find.byKey(const Key('filter-imaging')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('record-r1')), findsNothing);
      expect(find.byKey(const Key('record-r2')), findsOneWidget);
    });

    tallTest('a PDF opens through the system viewer; an image in the app', (t) async {
      repo.current = [
        rec('r1'),
        rec('r2', category: RecordCategory.imaging, name: 'xray.png', type: 'image/png'),
      ];
      await t.pumpWidget(host(const RecordsPage()));
      await t.pumpAndSettle();
      await t.tap(find.text('blood_test.pdf'));
      await t.pumpAndSettle();
      expect(sharer.shared, ['blood_test.pdf|application/pdf']);
      await t.tap(find.text('xray.png'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('record-image')), findsOneWidget);
    });
  });

  group('UC6.2 share and D-58 changes', () {
    Future<void> menu(WidgetTester t, String id, String item) async {
      await t.tap(find.byKey(Key('record-menu-$id')));
      await t.pumpAndSettle();
      await t.tap(find.text(item).last);
      await t.pumpAndSettle();
    }

    tallTest('share, then stop sharing', (t) async {
      repo.current = [rec('r1'), rec('r2', shared: true)];
      await t.pumpWidget(host(const RecordsPage()));
      await t.pumpAndSettle();
      await menu(t, 'r1', 'Share with doctor');
      await menu(t, 'r2', 'Stop sharing');
      expect(repo.calls, ['share:r1', 'unshare:r2']);
    });

    tallTest('change the category', (t) async {
      repo.current = [rec('r1')];
      await t.pumpWidget(host(const RecordsPage()));
      await t.pumpAndSettle();
      await menu(t, 'r1', 'Change category');
      await t.tap(find.byKey(const Key('category-referral_letter')));
      await t.pump();
      await t.tap(find.byKey(const Key('category-confirm')));
      await t.pumpAndSettle();
      expect(repo.calls, ['category:r1:referral_letter']);
    });

    tallTest('delete asks first', (t) async {
      repo.current = [rec('r1', shared: true)];
      await t.pumpWidget(host(const RecordsPage()));
      await t.pumpAndSettle();
      await menu(t, 'r1', 'Delete');
      expect(find.textContaining('your doctor will no longer see it'), findsOneWidget);
      await t.tap(find.byKey(const Key('delete-confirm')));
      await t.pumpAndSettle();
      expect(repo.calls, ['delete:r1']);
    });
  });

  group('UC6.3 doctor view', () {
    tallTest('lists only shared documents and opens them', (t) async {
      repo.current = [rec('r1', shared: true), rec('r2', name: 'private.pdf')];
      await t.pumpWidget(host(const Scaffold(body: SharedRecordsTab(patientId: 'p1'))));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('shared-record-r1')), findsOneWidget);
      expect(find.text('private.pdf'), findsNothing);
      expect(find.textContaining('shared 15 Oct 2026'), findsOneWidget);
      await t.tap(find.byKey(const Key('shared-record-r1')));
      await t.pumpAndSettle();
      expect(sharer.shared, ['blood_test.pdf|application/pdf']);
    });

    tallTest('E1 nothing shared shows an empty state', (t) async {
      repo.current = [rec('r2')];
      await t.pumpWidget(host(const Scaffold(body: SharedRecordsTab(patientId: 'p1'))));
      await t.pumpAndSettle();
      expect(find.text('The patient has not shared any documents yet.'), findsOneWidget);
    });
  });

  group('file checks (UC6.1 E1)', () {
    test('supported types by name; size limit', () {
      expect(recordContentType('Scan.JPEG'), 'image/jpeg');
      expect(recordContentType('report.docx'), isNull);
      expect(checkRecordFile(pdfBytes, 'a.pdf').contentType, 'application/pdf');
      expect(
        () => checkRecordFile(Uint8List(maxRecordBytes + 1), 'big.pdf'),
        throwsA(isA<UnsupportedRecordFile>()),
      );
      expect(fileSizeLabel(245760), '240 KB');
      expect(fileSizeLabel(3 * 1024 * 1024), '3.0 MB');
    });
  });
}
